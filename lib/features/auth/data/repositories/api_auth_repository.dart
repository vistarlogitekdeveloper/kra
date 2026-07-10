import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/api/api_constants.dart';
import '../../../../core/api/api_error.dart';
import '../../../../core/api/envelope.dart';
import '../../../../core/api/json_parse.dart';
import '../../../../core/api/retry_policy.dart';
import '../../../../core/storage/secure_storage_service.dart';
import '../models/token_pair.dart';
import '../models/user.dart';
import 'auth_repository.dart';

/// REST-backed implementation of [AuthRepository].
///
/// Responsibilities:
///   - Call /auth/login, /auth/logout, /auth/me with the correct
///     payloads / headers (auth-skip handled by the interceptor).
///   - On login: persist token bundle and user JSON to secure storage.
///   - On logout: ALWAYS clear local storage, even if the server call
///     fails — being trapped in an "online but logged in" state is worse
///     than a stale refresh token left behind on the server.
///   - Translate transport-level errors into [AuthException] with
///     user-safe messages — the UI never sees a raw DioException.
///
/// Login uses [RetryPolicy] (3 attempts, expo backoff + jitter) for
/// network/5xx errors only. 4xx errors (INVALID_CREDENTIALS, 429, etc.)
/// surface immediately so the user gets fast, clear feedback.
class ApiAuthRepository implements AuthRepository {
  final Dio _dio;
  final SecureStorageService _storage;
  final RetryPolicy _retryPolicy;

  ApiAuthRepository({
    required Dio dio,
    required SecureStorageService storage,
    RetryPolicy? retryPolicy,
  })  : _dio = dio,
        _storage = storage,
        _retryPolicy = retryPolicy ?? RetryPolicy();

  @override
  Future<User> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _retryPolicy.execute(
        () => _dio.post(
          ApiConstants.authLogin,
          data: {'email': email, 'password': password},
          options: Options(extra: {'skipAuth': true}),
        ),
      );

      final payload = unwrapObject(response);
      final tokens = TokenPair.fromJson(
        payload['tokenPair'] as Map<String, dynamic>,
      );
      final userJson = payload['user'] as Map<String, dynamic>;
      final user = User.fromJson(userJson);

      await _storage.writeAuthBundle(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        expiresInSeconds: tokens.expiresIn,
        userJson: userJson,
      );

      return user;
    } on DioException catch (e) {
      throw _toAuthException(ApiError.fromDioException(e));
    } on ApiError catch (e) {
      throw _toAuthException(e);
    } catch (e) {
      throw const AuthException(
        'Something went wrong. Please try again.',
      );
    }
  }

  @override
  Future<void> logout() async {
    // Try the API call but don't let a failure block local cleanup.
    try {
      await _dio.post(ApiConstants.authLogout);
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('logout: server call failed (${e.type}) — proceeding');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('logout: $e');
    }

    await _storage.clearAll();
  }

  @override
  Future<User?> getCurrentUser() async {
    final cached = await _storage.readUserJson();
    if (cached == null) return null;
    try {
      return User.fromJson(cached);
    } catch (_) {
      // Cached user is corrupt — wipe it so we don't loop on bad data.
      await _storage.clearAll();
      return null;
    }
  }

  @override
  Future<User?> refreshCurrentUser() async {
    try {
      final response = await _dio.get(ApiConstants.authMe);
      final userJson = unwrapObject(response);
      final user = User.fromJson(userJson);
      await _storage.writeUserJson(userJson);
      return user;
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('refreshCurrentUser failed: ${e.type}');
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String> forgotPassword(String email) async {
    try {
      final response = await _dio.post(
        ApiConstants.authForgotPassword,
        data: {'email': email},
        options: Options(extra: {'skipAuth': true}),
      );
      final data = unwrapObject(response);
      return JsonParse.parseString(data['message']) ??
          'If that email is registered, a reset link is on its way.';
    } on DioException catch (e) {
      throw _toAuthException(ApiError.fromDioException(e));
    } on ApiError catch (e) {
      throw _toAuthException(e);
    } catch (e) {
      throw const AuthException('Something went wrong. Please try again.');
    }
  }

  @override
  Future<String> resetPassword({
    required String token,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        ApiConstants.authResetPassword,
        data: {'token': token, 'password': password},
        options: Options(extra: {'skipAuth': true}),
      );
      final data = unwrapObject(response);
      return JsonParse.parseString(data['message']) ??
          'Password updated. You can now sign in.';
    } on DioException catch (e) {
      throw _toAuthException(ApiError.fromDioException(e));
    } on ApiError catch (e) {
      throw _toAuthException(e);
    } catch (e) {
      throw const AuthException('Something went wrong. Please try again.');
    }
  }

  AuthException _toAuthException(ApiError error) {
    return AuthException(
      error.message.isEmpty
          ? 'Something went wrong. Please try again.'
          : error.message,
      code: error.code,
    );
  }
}
