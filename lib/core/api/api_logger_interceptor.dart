import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Lightweight request/response logger.
///
/// Active ONLY when `kDebugMode == true`. In release builds this
/// interceptor is effectively a no-op — production must never log
/// request bodies, headers, or tokens.
///
/// Sensitive fields (Authorization, refreshToken, accessToken,
/// password) are redacted to `[REDACTED]` even in debug.
class ApiLoggerInterceptor extends Interceptor {
  static const _redacted = '[REDACTED]';
  static const _sensitiveHeaders = {
    'authorization',
    'cookie',
    'set-cookie',
  };
  static const _sensitiveBodyKeys = {
    'password',
    'newPassword',
    'oldPassword',
    'accessToken',
    'refreshToken',
    'token',
  };

  // Track request start time so we can measure latency on response.
  final Map<int, Stopwatch> _watches = {};

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    if (!kDebugMode) {
      handler.next(options);
      return;
    }
    _watches[options.hashCode] = Stopwatch()..start();
    debugPrint('→ ${options.method} ${options.path}');
    handler.next(options);
  }

  @override
  void onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) {
    if (!kDebugMode) {
      handler.next(response);
      return;
    }
    final ms = _watches.remove(response.requestOptions.hashCode)?.elapsedMilliseconds;
    debugPrint(
      '← ${response.requestOptions.method} ${response.requestOptions.path} '
      '(${response.statusCode}) ${ms ?? '?'}ms',
    );
    handler.next(response);
  }

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) {
    if (!kDebugMode) {
      handler.next(err);
      return;
    }
    final ms = _watches.remove(err.requestOptions.hashCode)?.elapsedMilliseconds;
    final status = err.response?.statusCode;
    debugPrint(
      '✕ ${err.requestOptions.method} ${err.requestOptions.path} '
      '(${status ?? err.type.name}) ${ms ?? '?'}ms',
    );

    // On error, dump request + response bodies (sanitised) so we can debug.
    final sanitisedReqHeaders = _sanitiseHeaders(err.requestOptions.headers);
    final sanitisedReqBody = _sanitiseBody(err.requestOptions.data);
    final sanitisedResBody = _sanitiseBody(err.response?.data);

    debugPrint('  request headers : $sanitisedReqHeaders');
    if (sanitisedReqBody != null) {
      debugPrint('  request body    : $sanitisedReqBody');
    }
    if (sanitisedResBody != null) {
      debugPrint('  response body   : $sanitisedResBody');
    }

    handler.next(err);
  }

  Map<String, dynamic> _sanitiseHeaders(Map<String, dynamic> headers) {
    return {
      for (final entry in headers.entries)
        entry.key: _sensitiveHeaders.contains(entry.key.toLowerCase())
            ? _redacted
            : entry.value,
    };
  }

  Object? _sanitiseBody(dynamic body) {
    if (body == null) return null;
    try {
      if (body is String) {
        // Try to parse JSON-string bodies so we can sanitise them.
        try {
          final parsed = jsonDecode(body);
          return _sanitiseValue(parsed);
        } catch (_) {
          return body;
        }
      }
      return _sanitiseValue(body);
    } catch (_) {
      return _redacted;
    }
  }

  dynamic _sanitiseValue(dynamic value) {
    if (value is Map) {
      return {
        for (final e in value.entries)
          e.key: _sensitiveBodyKeys.contains(e.key.toString())
              ? _redacted
              : _sanitiseValue(e.value),
      };
    }
    if (value is List) {
      return value.map(_sanitiseValue).toList();
    }
    return value;
  }
}
