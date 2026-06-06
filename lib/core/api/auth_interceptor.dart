import 'package:dio/dio.dart';

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

    if (!skipAuth) {
      await _refresher.ensureFreshAccessToken();
      final token = await _storage.readAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }

    handler.next(options);
  }
}
