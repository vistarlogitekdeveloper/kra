import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

import 'api_error.dart';

/// Exponential-backoff retry helper.
///
/// Used for operations where transient transport errors (no internet,
/// timeout, 5xx) are likely. NOT used for permanent failures such as
/// 401 INVALID_CREDENTIALS — those must surface immediately so the
/// user gets clear feedback.
///
/// Default backoff: 1s, 2s, 4s — each multiplied by a random jitter
/// factor in [0.8, 1.2] so concurrent clients don't synchronise their
/// retries (the "thundering herd" problem).
class RetryPolicy {
  final Random _random;

  RetryPolicy({Random? random}) : _random = random ?? Random();

  /// Runs [task] up to [maxAttempts] times.
  ///
  /// [shouldRetry] receives the thrown error. Return true to retry.
  /// If null, defaults to [_defaultShouldRetry] (network + 5xx + timeouts).
  ///
  /// Throws the LAST error if every attempt fails.
  Future<T> execute<T>(
    Future<T> Function() task, {
    int maxAttempts = 3,
    bool Function(Object error)? shouldRetry,
  }) async {
    final retryCheck = shouldRetry ?? _defaultShouldRetry;
    Object? lastError;
    StackTrace? lastStack;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await task();
      } catch (e, st) {
        lastError = e;
        lastStack = st;

        final isLast = attempt == maxAttempts;
        if (isLast || !retryCheck(e)) {
          rethrow;
        }
        await Future.delayed(_backoff(attempt));
      }
    }

    // Unreachable in practice — the loop either returns or rethrows.
    Error.throwWithStackTrace(lastError ?? StateError('retry exhausted'),
        lastStack ?? StackTrace.current);
  }

  /// 1s · 2s · 4s · ... with ±20% jitter.
  Duration _backoff(int attempt) {
    final baseMs = (1000 * pow(2, attempt - 1)).toInt();
    final jitterFactor = 0.8 + _random.nextDouble() * 0.4; // [0.8, 1.2)
    return Duration(milliseconds: (baseMs * jitterFactor).round());
  }

  /// Retries on transport errors (no internet, timeouts) and 5xx.
  /// Does NOT retry on 4xx — those are permanent client errors.
  bool _defaultShouldRetry(Object error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.connectionError:
          return true;
        case DioExceptionType.cancel:
        case DioExceptionType.badCertificate:
          return false;
        case DioExceptionType.unknown:
        case DioExceptionType.badResponse:
          final s = error.response?.statusCode;
          return s != null && s >= 500 && s < 600;
      }
    }
    if (error is ApiError) {
      return error.type == ApiErrorType.network ||
          error.type == ApiErrorType.server;
    }
    return false;
  }
}
