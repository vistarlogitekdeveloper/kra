import 'package:dio/dio.dart';

import 'api_constants.dart';

/// Categorical error type — UI can branch on this for analytics or
/// special handling (e.g. "show retry button" vs "force logout").
enum ApiErrorType {
  network,
  server,
  unauthorized,
  tokenExpired,
  tokenInvalid,
  rateLimited,
  validation,
  notFound,
  unknown,
  cancelled,
}

/// Single, sanitised error type that crosses the data → UI boundary.
/// `message` is always safe to show to the end user (Indian English, polite).
/// `technicalMessage` is for logs / Sentry only.
/// `fieldErrors` carries per-field validation messages from the backend's
/// `error.details` envelope (e.g. `{ "selfRatingDeadline": ["...must be on
/// or after endDate"] }`) — empty when there are none. Forms can surface
/// these inline; otherwise [combinedMessage] flattens them for a banner.
class ApiError implements Exception {
  final ApiErrorType type;
  final String code;
  final String message;
  final String? technicalMessage;
  final int? statusCode;
  final Map<String, List<String>> fieldErrors;

  const ApiError({
    required this.type,
    required this.code,
    required this.message,
    this.technicalMessage,
    this.statusCode,
    this.fieldErrors = const {},
  });

  /// User-facing message that includes any backend field errors. When the
  /// backend returns `details`, that is almost always more useful than the
  /// generic "Validation failed" — e.g. it tells the user that the self-
  /// rating deadline must come on or after the cycle end date.
  String get combinedMessage {
    if (fieldErrors.isEmpty) return message;
    final lines = <String>[];
    for (final entry in fieldErrors.entries) {
      for (final msg in entry.value) {
        lines.add(msg);
      }
    }
    return lines.isEmpty ? message : lines.join('\n');
  }

  /// True when this is the backend's "you manage no one" 403 — sent when a
  /// manager-scoped endpoint (e.g. `/manager/dashboard`, `/manager/team`) is
  /// hit by a user with zero direct reports, or by a non-manager.
  ///
  /// This is a normal *data state*, not a failure: the UI must empty-state
  /// the Team area (never a raw 403 / logout). The sentinel arrives
  /// inconsistently across backends — sometimes in `error.code`, sometimes
  /// in `error.message` — and a 403 has no dedicated [ApiError] branch, so
  /// the code often collapses to `VALIDATION_ERROR` with the real marker
  /// landing in [message] / [technicalMessage]. Match all three so a single
  /// backend wording change can't silently reintroduce a raw-403 screen.
  bool get isNoDirectReports {
    if (statusCode != 403) return false;
    const markers = ['NO_DIRECT_REPORTS', 'NOT_A_MANAGER'];
    final haystack = [code, message, technicalMessage ?? '']
        .map((s) => s.toUpperCase())
        .join(' ');
    return markers.any(haystack.contains);
  }

  @override
  String toString() =>
      'ApiError($type, code=$code, status=$statusCode, msg="$message")';

  // ───── Backend code → user-friendly message ─────
  static const Map<String, String> _codeMessages = {
    'INVALID_CREDENTIALS':
        'The email or password you entered is incorrect.',
    'ACCOUNT_INACTIVE':
        'Your account is inactive. Please contact HR.',
    'TOKEN_INVALID':
        'Your session has ended. Please sign in again.',
    'REFRESH_TOKEN_REUSE':
        'Your session has ended. Please sign in again.',
    'TOKEN_EXPIRED':
        'Your session has ended. Please sign in again.',
    'RATE_LIMITED':
        'Too many attempts. Please wait a minute and try again.',
    'VALIDATION_ERROR':
        'Some of the information you entered isn\'t valid. Please check and try again.',
    'NOT_FOUND':
        'We couldn\'t find what you were looking for.',
  };

  /// Builds a typed [ApiError] from any [DioException], handling:
  ///   - timeout / connectivity → ApiErrorType.network
  ///   - cancellation → ApiErrorType.cancelled
  ///   - 401 with backend code → tokenExpired / tokenInvalid / unauthorized
  ///   - 429 → rateLimited
  ///   - 4xx → validation / notFound / unknown
  ///   - 5xx → server
  factory ApiError.fromDioException(DioException e) {
    // ── Transport-level errors (no HTTP response received) ──
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return ApiError(
          type: ApiErrorType.network,
          code: 'TIMEOUT',
          message:
              'The server is taking too long to respond. Please try again.',
          technicalMessage: e.message,
        );
      case DioExceptionType.connectionError:
        return ApiError(
          type: ApiErrorType.network,
          code: 'NO_CONNECTION',
          message: 'No internet connection. Please check your network.',
          technicalMessage: e.message,
        );
      case DioExceptionType.cancel:
        return const ApiError(
          type: ApiErrorType.cancelled,
          code: 'CANCELLED',
          message: '',
        );
      case DioExceptionType.badCertificate:
        return ApiError(
          type: ApiErrorType.network,
          code: 'BAD_CERT',
          message:
              'Could not verify a secure connection to the server. Please try again.',
          technicalMessage: e.message,
        );
      case DioExceptionType.unknown:
      case DioExceptionType.badResponse:
        // fall through to response parsing below
        break;
    }

    final response = e.response;
    final status = response?.statusCode;

    // ── No response despite type ── treat as unknown network failure
    if (response == null) {
      return ApiError(
        type: ApiErrorType.unknown,
        code: 'UNKNOWN',
        message: 'Something went wrong. Please try again in a moment.',
        technicalMessage: e.message,
      );
    }

    // ── Try to read the standard envelope:
    //    { success, error: { code, message, details?: {field: [msg, …]} } } ──
    String? backendCode;
    String? backendMessage;
    Map<String, List<String>> fieldErrors = const {};
    final body = response.data;
    if (body is Map<String, dynamic>) {
      final err = body[ApiConstants.envelopeError];
      if (err is Map<String, dynamic>) {
        backendCode = err[ApiConstants.envelopeErrorCode] as String?;
        backendMessage = err[ApiConstants.envelopeErrorMessage] as String?;
        fieldErrors = _parseFieldErrors(err[ApiConstants.envelopeErrorDetails]);
      }
    }

    // ── 5xx → server ──
    if (status != null && status >= 500 && status < 600) {
      return ApiError(
        type: ApiErrorType.server,
        code: backendCode ?? 'SERVER_ERROR',
        message: 'Our servers are having trouble. Please try again in a moment.',
        technicalMessage: backendMessage ?? 'HTTP $status',
        statusCode: status,
        fieldErrors: fieldErrors,
      );
    }

    // ── 429 → rate limited ──
    if (status == 429) {
      return ApiError(
        type: ApiErrorType.rateLimited,
        code: backendCode ?? 'RATE_LIMITED',
        message: _codeMessages['RATE_LIMITED']!,
        technicalMessage: backendMessage,
        statusCode: status,
        fieldErrors: fieldErrors,
      );
    }

    // ── 401 → split into expired / invalid / generic unauthorized ──
    if (status == 401) {
      final ApiErrorType type;
      switch (backendCode) {
        case 'TOKEN_EXPIRED':
          type = ApiErrorType.tokenExpired;
          break;
        case 'TOKEN_INVALID':
        case 'REFRESH_TOKEN_REUSE':
          type = ApiErrorType.tokenInvalid;
          break;
        default:
          type = ApiErrorType.unauthorized;
      }
      return ApiError(
        type: type,
        code: backendCode ?? 'UNAUTHORIZED',
        message: _codeMessages[backendCode] ??
            'The email or password you entered is incorrect.',
        technicalMessage: backendMessage,
        statusCode: status,
        fieldErrors: fieldErrors,
      );
    }

    // ── 404 ──
    if (status == 404) {
      return ApiError(
        type: ApiErrorType.notFound,
        code: backendCode ?? 'NOT_FOUND',
        message: _codeMessages['NOT_FOUND']!,
        technicalMessage: backendMessage,
        statusCode: status,
        fieldErrors: fieldErrors,
      );
    }

    // ── 4xx (validation, etc.) ──
    if (status != null && status >= 400 && status < 500) {
      return ApiError(
        type: ApiErrorType.validation,
        code: backendCode ?? 'VALIDATION_ERROR',
        message: _codeMessages[backendCode] ??
            backendMessage ??
            _codeMessages['VALIDATION_ERROR']!,
        technicalMessage: backendMessage,
        statusCode: status,
        fieldErrors: fieldErrors,
      );
    }

    return ApiError(
      type: ApiErrorType.unknown,
      code: backendCode ?? 'UNKNOWN',
      message: 'Something went wrong. Please try again.',
      technicalMessage: backendMessage,
      statusCode: status,
      fieldErrors: fieldErrors,
    );
  }

  /// Normalises the `error.details` payload, which the backend sends as
  /// `{ "fieldName": ["msg1", "msg2"], ... }`. Any non-conforming shape
  /// (string, list, missing) is dropped silently — this is a UX hint, not
  /// a contract — so a backend change can never break the error pipeline.
  static Map<String, List<String>> _parseFieldErrors(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, List<String>>{};
    raw.forEach((key, value) {
      if (key is! String) return;
      if (value is List) {
        final msgs = value.whereType<String>().toList();
        if (msgs.isNotEmpty) out[key] = msgs;
      } else if (value is String) {
        out[key] = [value];
      }
    });
    return out;
  }
}
