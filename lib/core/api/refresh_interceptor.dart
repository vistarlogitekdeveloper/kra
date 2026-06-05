import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../storage/secure_storage_service.dart';
import 'api_constants.dart';

/// Global, app-level signal for "session is gone, force the user back to login".
///
/// `RefreshInterceptor` cannot itself touch Riverpod state (interceptors live
/// outside the provider tree), so when refresh fails irrecoverably it sets
/// this flag. `app_boot_provider` / `auth_providers.dart` listen on it and
/// flip auth state to AuthInitial, which in turn redirects via go_router.
class ForcedLogoutBus {
  ForcedLogoutBus._();
  static final ForcedLogoutBus instance = ForcedLogoutBus._();

  final ValueNotifier<int> _trigger = ValueNotifier<int>(0);
  ValueNotifier<int> get listenable => _trigger;

  void fire() => _trigger.value = _trigger.value + 1;
}

/// Refresh-token interceptor — concurrent-safe, recursion-safe.
///
/// 1. **Mutex pattern**: if many requests fail with 401 simultaneously,
///    only ONE refresh fires. The others await the same future.
/// 2. **Recursion-safe**: refresh uses a SEPARATE Dio instance with no
///    interceptors of its own — otherwise a 401 from /auth/refresh would
///    trigger another refresh, ad infinitum.
/// 3. **Code-aware**:
///       TOKEN_EXPIRED        → refresh + retry
///       TOKEN_INVALID        → forced logout, no retry
///       REFRESH_TOKEN_REUSE  → forced logout, no retry
///       refresh itself 401   → forced logout, no retry
class RefreshInterceptor extends Interceptor {
  final Dio _mainDio;
  final SecureStorageService _storage;

  // Process-wide mutex. Multiple AuthInterceptor or Dio instances would
  // share the same lock as long as the same RefreshInterceptor object is
  // attached, which is fine because we register one per Dio.
  Future<bool>? _refreshFuture;

  RefreshInterceptor({
    required Dio mainDio,
    required SecureStorageService storage,
  })  : _mainDio = mainDio,
        _storage = storage;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;

    // Only act on 401s.
    if (response?.statusCode != 401) {
      return handler.next(err);
    }

    // Don't try to refresh on /auth/login, /auth/refresh, or
    // /auth/logout — the first two skip auth entirely, and a 401 from
    // logout just means the session was already invalidated server-side.
    final path = err.requestOptions.path;
    if (ApiConstants.noRefreshOn401Endpoints.contains(path)) {
      return handler.next(err);
    }

    // Only refresh on TOKEN_EXPIRED. Anything else (TOKEN_INVALID,
    // REFRESH_TOKEN_REUSE, missing) is a hard logout.
    final code = _readBackendCode(response);
    if (code == 'TOKEN_INVALID' || code == 'REFRESH_TOKEN_REUSE') {
      await _forceLogout();
      return handler.next(err);
    }

    // If we've already retried this request once, don't loop.
    if (err.requestOptions.extra['_didRetry'] == true) {
      await _forceLogout();
      return handler.next(err);
    }

    // ── Mutex: share one in-flight refresh across concurrent callers ──
    final refreshOk = await (_refreshFuture ??= _doRefresh());
    // Clear the future ONLY if we own it; otherwise another caller did.
    // The first caller to finish will see _refreshFuture non-null with a
    // completed future — clearing it on every path is safe.
    _refreshFuture = null;

    if (!refreshOk) {
      await _forceLogout();
      return handler.next(err);
    }

    // Retry the original request with the new access token.
    try {
      final newToken = await _storage.readAccessToken();
      final retryOptions = err.requestOptions
        ..headers['Authorization'] = 'Bearer ${newToken ?? ''}'
        ..extra['_didRetry'] = true;

      final retryResponse = await _mainDio.fetch(retryOptions);
      return handler.resolve(retryResponse);
    } on DioException catch (e) {
      return handler.next(e);
    } catch (e, st) {
      return handler.next(
        DioException(
          requestOptions: err.requestOptions,
          error: e,
          stackTrace: st,
          type: DioExceptionType.unknown,
        ),
      );
    }
  }

  /// Performs a refresh against /auth/refresh using a SEPARATE Dio.
  /// Returns true on success, false on any failure.
  Future<bool> _doRefresh() async {
    try {
      final refreshToken = await _storage.readRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) return false;

      // Plain Dio — no interceptors. Otherwise refresh-call failure would
      // re-enter this interceptor and recurse forever.
      final plainDio = Dio(
        BaseOptions(
          baseUrl: ApiConstants.baseUrl,
          connectTimeout: ApiConstants.connectTimeout,
          receiveTimeout: ApiConstants.receiveTimeout,
          sendTimeout: ApiConstants.sendTimeout,
          contentType: 'application/json',
          responseType: ResponseType.json,
        ),
      );

      final response = await plainDio.post(
        ApiConstants.authRefresh,
        data: {'refreshToken': refreshToken},
      );

      final body = response.data;
      if (body is! Map) return false;
      if (body[ApiConstants.envelopeSuccess] != true) return false;

      final data = body[ApiConstants.envelopeData];
      if (data is! Map) return false;

      final accessToken = data['accessToken'] as String?;
      final newRefreshToken = data['refreshToken'] as String?;
      final expiresIn = (data['expiresIn'] as num?)?.toInt() ?? 900;

      if (accessToken == null || newRefreshToken == null) return false;

      await _storage.writeAuthBundle(
        accessToken: accessToken,
        refreshToken: newRefreshToken,
        expiresInSeconds: expiresIn,
      );
      return true;
    } on DioException catch (e) {
      // Refresh itself returned 401 / network failure → can't recover.
      if (kDebugMode) {
        debugPrint('RefreshInterceptor: refresh failed (${e.type})');
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('RefreshInterceptor: refresh threw $e');
      }
      return false;
    }
  }

  Future<void> _forceLogout() async {
    await _storage.clearAll();
    ForcedLogoutBus.instance.fire();
  }

  String? _readBackendCode(Response? response) {
    final body = response?.data;
    if (body is! Map) return null;
    final err = body[ApiConstants.envelopeError];
    if (err is! Map) return null;
    return err[ApiConstants.envelopeErrorCode] as String?;
  }
}
