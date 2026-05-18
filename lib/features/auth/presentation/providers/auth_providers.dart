import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/dio_client.dart';
import '../../../../core/api/refresh_interceptor.dart';
import '../../../../core/storage/secure_storage_service.dart';
import '../../data/models/user.dart';
import '../../data/repositories/api_auth_repository.dart';
import '../../data/repositories/auth_repository.dart';

// ────────────────────────────────────────────────────────────────────
// Repository wiring
// ────────────────────────────────────────────────────────────────────

/// Single SWAP point.
///
/// Production: returns [ApiAuthRepository] backed by Dio + secure storage.
/// To switch to mock for offline UI work, replace the body with:
///
///     return MockAuthRepository();
///
/// (and add the corresponding import). No other file needs to change.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return ApiAuthRepository(
    dio: ref.read(dioProvider),
    storage: ref.read(secureStorageProvider),
  );
});

// ────────────────────────────────────────────────────────────────────
// State
// ────────────────────────────────────────────────────────────────────

sealed class AuthState {
  const AuthState();
}

/// No session known yet (cold start before boot, or post-logout).
class AuthInitial extends AuthState {
  const AuthInitial();
}

/// A login attempt is in flight.
class AuthLoading extends AuthState {
  const AuthLoading();
}

/// User is authenticated; carry the [User] payload.
class AuthAuthenticated extends AuthState {
  final User user;
  const AuthAuthenticated(this.user);
}

/// A login attempt failed; carry a UI-safe message.
class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);
}

// ────────────────────────────────────────────────────────────────────
// Notifier
// ────────────────────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;

  AuthNotifier(this._repository) : super(const AuthInitial());

  /// Used by [appBootProvider] to seed the state from secure storage
  /// BEFORE the first frame renders, so already-logged-in users go
  /// straight to their dashboard without a flicker of the login screen.
  void hydrate(User user) {
    state = AuthAuthenticated(user);
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    state = const AuthLoading();
    try {
      final user = await _repository.login(email: email, password: password);
      state = AuthAuthenticated(user);
    } on AuthException catch (e) {
      state = AuthError(e.message);
    } catch (e, st) {
      // Log unexpected errors (TypeError from a model schema mismatch,
      // etc.) so they don't disappear silently behind the generic
      // snackbar — the user still sees a polite message, but the
      // developer console gets the real stack trace.
      if (kDebugMode) {
        debugPrint('Unexpected login error: $e');
        debugPrintStack(stackTrace: st);
      }
      state = const AuthError('Something went wrong. Please try again.');
    }
  }

  Future<void> logout() async {
    // Optimistically flip to Initial so the UI redirects fast,
    // then clear server + local state in the background.
    state = const AuthInitial();
    await _repository.logout();
  }

  /// Called by the forced-logout bus when refresh fails irrecoverably.
  void forceLogout() {
    state = const AuthInitial();
  }

  void clearError() {
    if (state is AuthError) {
      state = const AuthInitial();
    }
  }
}

/// Holds the current login state. The login screen and the router
/// both watch this provider.
final authStateProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final notifier = AuthNotifier(ref.read(authRepositoryProvider));

  // Bridge the interceptor's forced-logout signal into Riverpod.
  // When the refresh interceptor decides the session is unrecoverable
  // (TOKEN_INVALID, REFRESH_TOKEN_REUSE, refresh-call 401), it bumps
  // [ForcedLogoutBus] — we listen and flip auth state to Initial so
  // the router can redirect to /login.
  void onForcedLogout() => notifier.forceLogout();
  ForcedLogoutBus.instance.listenable.addListener(onForcedLogout);
  ref.onDispose(
    () => ForcedLogoutBus.instance.listenable.removeListener(onForcedLogout),
  );

  return notifier;
});
