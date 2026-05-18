import 'package:dio/dio.dart';

import '../storage/secure_storage_service.dart';
import 'api_constants.dart';

/// Attaches the access token to outgoing requests as a Bearer header.
///
/// Skips auth-issuing endpoints (login, refresh) — these would either
/// have no token yet, or use the refresh-token cookie/body and not the
/// access-token header. Callers can also opt out per-request via
/// `options.extra['skipAuth'] = true`.
class AuthInterceptor extends Interceptor {
  final SecureStorageService _storage;

  AuthInterceptor(this._storage);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final skipAuth = options.extra['skipAuth'] == true ||
        ApiConstants.noAuthEndpoints.contains(options.path);

    if (!skipAuth) {
      final token = await _storage.readAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }

    handler.next(options);
  }
}
