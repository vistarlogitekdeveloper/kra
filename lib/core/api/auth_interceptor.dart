import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../storage/secure_storage_service.dart';
import 'api_constants.dart';
import 'refresh_interceptor.dart';

/// Attaches the access token to outgoing requests as a Bearer header.
///
/// Skips auth-issuing endpoints (login, refresh) — these would either
/// have no token yet, or use the refresh-token cookie/body and not the
/// access-token header. Callers can also opt out per-request via
/// `options.extra['skipAuth'] = true`.
///
/// Before stamping the header, asks [RefreshInterceptor] to rotate the
/// access token if it's expired or near-expiry. Without this step every
/// request issued after the 15-minute access-token TTL had to fail with
/// a 401 first and recover via the reactive refresh path — so DevTools
/// kept showing `AUTH_002` failures even when the data did eventually
/// load. With proactive refresh the only 401s left are genuine session
/// terminations (which the reactive path then routes to forced logout).
class AuthInterceptor extends Interceptor {
  final SecureStorageService _storage;
  final RefreshInterceptor _refresher;

  AuthInterceptor(this._storage, this._refresher);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final skipAuth = options.extra['skipAuth'] == true ||
        ApiConstants.noAuthEndpoints.contains(options.path);

    try {
      if (!skipAuth) {
        final sessionAlive = await _refresher.ensureFreshAccessToken();
        if (!sessionAlive) {
          // Refresh token is gone — RefreshInterceptor has already wiped
          // storage and fired ForcedLogoutBus. Abort the outgoing request
          // so we don't burn a 401 in DevTools per concurrent caller while
          // the router redirects to /login.
          return handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
              message: 'Session ended',
            ),
          );
        }
        final token = await _storage.readAccessToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
      }
    } catch (e, st) {
      // CRITICAL: this interceptor is `async`, so anything that throws here
      // (e.g. a secure-storage decrypt error) would escape WITHOUT calling
      // handler.next/resolve/reject — leaving the Dio request future pending
      // forever. That reads as an endless loading shimmer with no network
      // call ever made. Never let that happen: log, then send the request
      // through unauthenticated and let the reactive 401 path recover.
      if (kDebugMode) {
        debugPrint('AuthInterceptor.onRequest failed for ${options.path}: $e');
        debugPrintStack(stackTrace: st);
      }
    }

    handler.next(options);
  }
}
