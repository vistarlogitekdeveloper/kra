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
class ApiError implements Exception {
  final ApiErrorType type;
  final String code;
  final String message;
  final String? technicalMessage;
  final int? statusCode;

  const ApiError({
    required this.type,
    required this.code,
    required this.message,
    this.technicalMessage,
    this.statusCode,
  });

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

    // ── Try to read the standard envelope: { success, error: { code, message } } ──
    String? backendCode;
    String? backendMessage;
    final body = response.data;
    if (body is Map<String, dynamic>) {
      final err = body[ApiConstants.envelopeError];
      if (err is Map<String, dynamic>) {
        backendCode = err[ApiConstants.envelopeErrorCode] as String?;
        backendMessage = err[ApiConstants.envelopeErrorMessage] as String?;
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
      );
    }

    return ApiError(
      type: ApiErrorType.unknown,
      code: backendCode ?? 'UNKNOWN',
      message: 'Something went wrong. Please try again.',
      technicalMessage: backendMessage,
      statusCode: status,
    );
  }
}
