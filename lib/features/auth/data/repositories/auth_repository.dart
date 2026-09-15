import '../models/user.dart';

/// Contract for authentication.
///
/// The UI depends ONLY on this interface — it does not know whether
/// the data is coming from a mock, REST API, or anything else. To plug
/// in a different implementation, register it in [auth_providers.dart];
/// no other code needs to change.
abstract class AuthRepository {
  /// Authenticates the user and persists tokens / user data on success.
  /// Throws [AuthException] (with a UI-safe message) on any failure.
  Future<User> login({
    required String email,
    required String password,
  });

  /// Revokes the session server-side and clears local storage.
  /// MUST clear local storage even if the API call fails — otherwise
  /// a network outage would trap the user in a logged-in state.
  Future<void> logout();

  /// Replaces the stored token pair and re-reads the signed-in user.
  ///
  /// Used when the SERVER hands back a new pair outside the login flow — today
  /// only the organisation switch, which re-issues a super admin's tokens
  /// against a different tenant. The organisation is a JWT claim, so nothing in
  /// the app changes tenant until the stored tokens do.
  ///
  /// Re-reads the user rather than trusting the caller: the new token carries a
  /// different `organizationId`, and every org-scoped read depends on the
  /// [User] reflecting it. Returns null when the swap or the re-read fails, so
  /// the previous session is left intact.
  Future<User?> adoptTokens({
    required String accessToken,
    required String refreshToken,
  });

  /// Returns the cached user if a valid session exists, else null.
  /// Consults local storage only — does not make a network call.
  Future<User?> getCurrentUser();

  /// Hits GET /auth/me and updates the cached user. Returns the fresh
  /// user on success, or null on any failure (caller decides whether
  /// to surface the error).
  Future<User?> refreshCurrentUser();

  /// Requests a password-reset email for [email]. Resolves with a
  /// user-safe message; the backend returns the same response whether or
  /// not the address exists (no account enumeration). Throws
  /// [AuthException] only on transport failure.
  Future<String> forgotPassword(String email);

  /// Completes a password reset using the emailed [token] + a new
  /// [password]. Returns a user-safe success message. Throws
  /// [AuthException] (e.g. "Invalid or expired reset token") on failure.
  Future<String> resetPassword({
    required String token,
    required String password,
  });

  /// Changes the SIGNED-IN user's password.
  ///
  /// Unlike [resetPassword], which trusts an emailed token, this proves intent
  /// with [currentPassword] — verified server-side — so an unlocked, borrowed
  /// device can't be used to take an account over. Returns a user-safe success
  /// message; throws [AuthException] on failure (wrong current password, or a
  /// new one the server rejects).
  Future<String> changePassword({
    required String currentPassword,
    required String newPassword,
  });
}

/// UI-safe exception type. The repository implementation is responsible
/// for translating low-level errors (network, HTTP) into messages that
/// can be shown directly to the user.
class AuthException implements Exception {
  final String message;
  final String? code;

  const AuthException(this.message, {this.code});

  @override
  String toString() => message;
}
