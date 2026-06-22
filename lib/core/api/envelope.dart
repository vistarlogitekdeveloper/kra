import 'package:dio/dio.dart';

import 'api_constants.dart';
import 'api_error.dart';
import 'json_parse.dart';

/// Shared response-envelope helpers for repositories. Every module
/// (auth / HR / employee / manager / ops) imports from here — there
/// used to be a duplicate HR-local copy at
/// `lib/features/hr/data/repositories/_envelope.dart`; that was retired
/// during the audit cleanup.

/// Returns `data` from `{ success: true, data: {...} }`.
/// Throws [ApiError] on a `success: false` envelope or malformed body.
Map<String, dynamic> unwrapObject(Response response) {
  final body = _readBody(response);
  final data = body[ApiConstants.envelopeData];
  if (data is Map<String, dynamic>) return data;
  throw const ApiError(
    type: ApiErrorType.unknown,
    code: 'BAD_RESPONSE',
    message: 'Unexpected response from the server. Please try again.',
  );
}

/// Returns `data` from `{ success: true, data: [...] }`.
/// Tolerates list-shaped envelopes nested under common keys (`items`,
/// `assignments`, `reviews`, etc.) so backends can evolve a flat list
/// into a paginated payload without breaking older clients.
List<dynamic> unwrapList(Response response) {
  final body = _readBody(response);
  final data = body[ApiConstants.envelopeData];
  if (data is List) return data;
  if (data is Map<String, dynamic>) {
    for (final key in const [
      'items',
      'assignments',
      'reviews',
      'employees',
      'templates',
      'cycles',
      'slabs',
      'months',
    ]) {
      final v = data[key];
      if (v is List) return v;
    }
  }
  throw const ApiError(
    type: ApiErrorType.unknown,
    code: 'BAD_RESPONSE',
    message: 'Unexpected response from the server. Please try again.',
  );
}

/// Like [unwrapObject] but synthesises a paged envelope when `data` is
/// itself a list — keeps callers' parsing code uniform regardless of
/// whether the endpoint paginates.
///
/// Three response shapes are accepted:
///   1. `{ data: { items: [...], page, pageSize/limit, total, totalPages } }`
///   2. `{ data: [...], meta: { page, limit, total, totalPages } }`
///   3. `{ data: [...] }` (synthesised pagination from the list length)
///
/// In shape #2 the spec'd top-level `meta` block is merged into the
/// returned map under the canonical `page`/`pageSize`/`total`/
/// `totalPages` keys so downstream `*Page.fromJson` parsers see a
/// uniform shape.
Map<String, dynamic> unwrapPaged(Response response) {
  final body = _readBody(response);
  final data = body[ApiConstants.envelopeData];
  final meta = body['meta'];

  if (data is Map<String, dynamic>) {
    // Already a paged object. Fold in top-level `meta` if present so
    // callers get a single source of truth for page/total/totalPages.
    if (meta is Map<String, dynamic>) {
      return {
        ...data,
        if (meta['page'] != null) 'page': meta['page'],
        if (meta['limit'] != null) 'pageSize': meta['limit'],
        if (meta['pageSize'] != null) 'pageSize': meta['pageSize'],
        if (meta['total'] != null) 'total': meta['total'],
        if (meta['totalPages'] != null) 'totalPages': meta['totalPages'],
      };
    }
    return data;
  }
  if (data is List) {
    if (meta is Map<String, dynamic>) {
      // Use the tolerant parsers, not raw `as int` — the backend can
      // serialise numeric fields as strings (Prisma Decimal) or as JSON
      // doubles, either of which would throw on a hard cast and turn a
      // whole paginated list into an error screen.
      final pageSize =
          JsonParse.parseInt(meta['limit'] ?? meta['pageSize']) ?? data.length;
      final total = JsonParse.parseInt(meta['total']) ?? data.length;
      final page = JsonParse.parseInt(meta['page']) ?? 1;
      final totalPages = JsonParse.parseInt(meta['totalPages']) ??
          (pageSize > 0 ? (total / pageSize).ceil() : 1);
      return {
        'items': data,
        'page': page,
        'pageSize': pageSize,
        'total': total,
        'totalPages': totalPages,
      };
    }
    return {
      'items': data,
      'page': 1,
      'pageSize': data.length,
      'total': data.length,
      'totalPages': 1,
    };
  }
  throw const ApiError(
    type: ApiErrorType.unknown,
    code: 'BAD_RESPONSE',
    message: 'Unexpected response from the server. Please try again.',
  );
}

/// Returns the optional `meta` block from a paged response, or `null`
/// if the envelope does not include one.
Map<String, dynamic>? unwrapMeta(Response response) {
  final body = response.data;
  if (body is! Map<String, dynamic>) return null;
  final meta = body['meta'];
  if (meta is Map<String, dynamic>) return meta;
  return null;
}

Map<String, dynamic> _readBody(Response response) {
  final body = response.data;
  if (body is! Map<String, dynamic>) {
    throw const ApiError(
      type: ApiErrorType.unknown,
      code: 'BAD_RESPONSE',
      message: 'Unexpected response from the server. Please try again.',
    );
  }
  if (body[ApiConstants.envelopeSuccess] != true) {
    final err = body[ApiConstants.envelopeError];
    final code = err is Map ? err['code'] as String? : null;
    final msg = err is Map ? err['message'] as String? : null;
    throw ApiError(
      type: ApiErrorType.unknown,
      code: code ?? 'UNKNOWN',
      message: msg ?? 'Something went wrong. Please try again.',
      statusCode: response.statusCode,
    );
  }
  return body;
}

/// Lifts any thrown error from a Dio call into a typed [ApiError].
/// Preserves the original stack via [Error.throwWithStackTrace] so
/// the trace points back to the offending repository line, not here.
Never rethrowAsApiError(Object error, StackTrace stack) {
  if (error is ApiError) {
    Error.throwWithStackTrace(error, stack);
  }
  if (error is DioException) {
    Error.throwWithStackTrace(ApiError.fromDioException(error), stack);
  }
  Error.throwWithStackTrace(
    const ApiError(
      type: ApiErrorType.unknown,
      code: 'UNKNOWN',
      message: 'Something went wrong. Please try again.',
    ),
    stack,
  );
}
