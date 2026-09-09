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
import '../../../../core/observability/app_logger.dart';

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
        AppLog.w('auth', 'logout server call failed (${e.type}) — proceeding');
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
  Future<User?> adoptTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    try {
      // The switch response carries no expiry, so fall back to the same
      // lifetime login assumes rather than inventing a second number.
      await _storage.writeAuthBundle(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresInSeconds: TokenPair.defaultExpiresIn,
      );
      // Deliberately AFTER the write, so /auth/me is signed with the NEW
      // token. Called before it, the server would answer for the PREVIOUS
      // organisation and the app would show one tenant's name over another
      // tenant's data.
      // Awaited so a failure lands in this catch rather than escaping as an
      // unhandled rejection past the try block.
      final user = await refreshCurrentUser();
      if (user == null) {
        // refreshCurrentUser() swallows its own errors and answers null, so
        // this is the only place the failure can still be reported. Returning
        // null here instead made a failed organisation switch look exactly
        // like a successful one: the tokens were written, the user was not
        // republished, and the UI still said "Switched organization" while
        // showing the previous tenant.
        throw const ApiError(
          type: ApiErrorType.unknown,
          code: 'ADOPT_TOKENS_FAILED',
          message: 'Signed in with the new token but could not read the '
              'account back. Please try again.',
        );
      }
      return user;
    } catch (e) {
      if (kDebugMode) debugPrint('adoptTokens failed: $e');
      // Rethrown, not swallowed. The caller decides what a failure means; this
      // layer must not pretend it did not happen.
      rethrow;
    }
  }

  @override
  Future<User?> refreshCurrentUser() async {
    try {
      final response = await _dio.get(ApiConstants.authMe);
      final userJson = await _withPreservedReviewFlow(unwrapObject(response));
      final user = User.fromJson(userJson);
      await _storage.writeUserJson(userJson);
      return user;
    } on DioException catch (e) {
      AppLog.w('auth', 'refreshCurrentUser failed (${e.type})');
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Carries a known review flow across an `/auth/me` response that omits it.
  ///
  /// `/auth/login` and `/auth/me` build their user payloads SEPARATELY on the
  /// server, and for a while only login returned `reviewFlow`. Because
  /// [refreshCurrentUser] REPLACES the stored user wholesale, an omission here
  /// does not leave the field alone — it erases it, and `ReviewFlow.fromApi`
  /// resolves absent to [ReviewFlow.standard]. So an organisation's real
  /// pipeline survived login and reverted on the next boot, page reload or
  /// organisation switch:
  ///
  ///     log in          -> ADMIN_ONLY   the sheet is correct
  ///     reload the page -> STANDARD     the sheet reverts, silently
  ///
  /// which presented as "the administrators-only flow doesn't work", with
  /// nothing on screen saying otherwise. Fixed on the server too
  /// (docs/install_review_flow.mjs edit 2b); kept here because this client
  /// talks to deployments that may not carry that patch, and quietly
  /// downgrading someone's pipeline is the one failure mode invisible to the
  /// person it affects.
  ///
  /// Only ABSENCE is treated as unknown. A server that has the field always
  /// sends a value — `'STANDARD'` included — so flipping an organisation back
  /// to the standard pipeline still takes effect immediately; this cannot pin a
  /// stale flow against an explicit answer.
  Future<Map<String, dynamic>> _withPreservedReviewFlow(
    Map<String, dynamic> fresh,
  ) async {
    final incoming = fresh['reviewFlow'];
    if (incoming is String && incoming.trim().isNotEmpty) return fresh;

    final cached = await _storage.readUserJson();
    final previous = cached?['reviewFlow'];
    if (previous is String && previous.trim().isNotEmpty) {
      if (kDebugMode) {
        AppLog.i('auth', '/auth/me omitted reviewFlow — keeping $previous');
      }
      return {...fresh, 'reviewFlow': previous};
    }
    return fresh;
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
  @override
  Future<String> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await _dio.post(
        ApiConstants.authChangePassword,
        data: {
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        },
        // NOT skipAuth: the endpoint is authenticated, and identifying the user
        // from the token is what stops one person changing another's password.
      );
      final data = unwrapObject(response);
      return JsonParse.parseString(data['message']) ?? 'Password updated.';
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
