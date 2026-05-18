import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secure_storage_service.dart';
import 'api_constants.dart';
import 'api_logger_interceptor.dart';
import 'auth_interceptor.dart';
import 'refresh_interceptor.dart';

/// Configured Dio for all backend calls.
///
/// Interceptor order matters:
///   1. AuthInterceptor   — attaches Bearer on outgoing requests
///   2. RefreshInterceptor — handles 401s (refresh + retry, or force logout)
///   3. ApiLoggerInterceptor — logs (debug-only, redacted)
///
/// Auth-issuing endpoints (login, refresh) are skipped by AuthInterceptor
/// based on `ApiConstants.noAuthEndpoints` — login/refresh do not carry
/// (or accept) a Bearer header.
final dioProvider = Provider<Dio>((ref) {
  final storage = ref.read(secureStorageProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: ApiConstants.connectTimeout,
      receiveTimeout: ApiConstants.receiveTimeout,
      sendTimeout: ApiConstants.sendTimeout,
      contentType: 'application/json',
      responseType: ResponseType.json,
    ),
  );

  dio.interceptors.add(AuthInterceptor(storage));
  dio.interceptors.add(RefreshInterceptor(mainDio: dio, storage: storage));
  dio.interceptors.add(ApiLoggerInterceptor());

  ref.onDispose(() => dio.close(force: true));
  return dio;
});
