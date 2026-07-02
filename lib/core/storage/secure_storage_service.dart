import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps `flutter_secure_storage` with typed helpers for the auth domain.
///
/// Tokens NEVER touch `SharedPreferences` — that store is plain-text
/// on Android and only mildly obfuscated on iOS. `flutter_secure_storage`
/// uses Keychain (iOS) and EncryptedSharedPreferences (Android).
class SecureStorageService {
  static const _kAccessToken = 'vistar.auth.accessToken';
  static const _kRefreshToken = 'vistar.auth.refreshToken';
  static const _kUserJson = 'vistar.auth.user';
  static const _kAccessTokenExpiry = 'vistar.auth.accessTokenExpiry';
  static const _kRememberedEmail = 'vistar.auth.rememberedEmail';

  final FlutterSecureStorage _storage;

  SecureStorageService([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  // In-memory cache to prevent heavy secure-storage reads on every API call.
  // The expiry is cached alongside the tokens because `AuthInterceptor`
  // reads it on EVERY outgoing request (proactive-refresh check) — serving
  // it from memory keeps the request hot-path off secure storage entirely.
  String? _cachedAccessToken;
  String? _cachedRefreshToken;
  DateTime? _cachedAccessTokenExpiry;

  /// Reads a key, tolerating the failures `flutter_secure_storage` can
  /// throw instead of returning null — most notably a WebCrypto
  /// `OperationError` from its web backend when a value can't be decrypted.
  ///
  /// Such a throw must NEVER reach the request path: unguarded, it escapes
  /// `AuthInterceptor.onRequest` (an async interceptor) without calling
  /// `handler.next`/`reject`, so the Dio request future never completes —
  /// the UI hangs on its loading shimmer forever and no network call is
  /// ever made. Degrading to null lets callers treat it as "no value" and
  /// fall back to the reactive 401 → refresh/relogin flow.
  Future<String?> _readRaw(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SecureStorage: read("$key") failed: $e');
      }
      return null;
    }
  }

  // ───── Access token ─────
  Future<String?> readAccessToken() async {
    if (_cachedAccessToken != null) return _cachedAccessToken;
    _cachedAccessToken = await _readRaw(_kAccessToken);
    return _cachedAccessToken;
  }

  Future<void> writeAccessToken(String token) async {
    _cachedAccessToken = token;
    await _storage.write(key: _kAccessToken, value: token);
  }

  // ───── Refresh token ─────
  Future<String?> readRefreshToken() async {
    if (_cachedRefreshToken != null) return _cachedRefreshToken;
    _cachedRefreshToken = await _readRaw(_kRefreshToken);
    return _cachedRefreshToken;
  }

  Future<void> writeRefreshToken(String token) async {
    _cachedRefreshToken = token;
    await _storage.write(key: _kRefreshToken, value: token);
  }

  // ───── Token expiry (epoch ms) — used for proactive refresh ─────
  Future<DateTime?> readAccessTokenExpiry() async {
    if (_cachedAccessTokenExpiry != null) return _cachedAccessTokenExpiry;
    final raw = await _readRaw(_kAccessTokenExpiry);
    if (raw == null) return null;
    final ms = int.tryParse(raw);
    if (ms == null) return null;
    return _cachedAccessTokenExpiry = DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> writeAccessTokenExpiry(DateTime expiry) async {
    _cachedAccessTokenExpiry = expiry;
    await _storage.write(
      key: _kAccessTokenExpiry,
      value: expiry.millisecondsSinceEpoch.toString(),
    );
  }

  // ───── User payload (JSON-encoded) ─────
  Future<Map<String, dynamic>?> readUserJson() async {
    final raw = await _readRaw(_kUserJson);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeUserJson(Map<String, dynamic> json) =>
      _storage.write(key: _kUserJson, value: jsonEncode(json));

  // ───── Remembered email (for "Remember me" pre-fill on login) ─────
  //
  // Stored under the same Keychain / EncryptedSharedPreferences scope as the
  // tokens so it doesn't survive an OS-level uninstall on either platform.
  // Cleared on explicit opt-out, never on logout — the whole point is to
  // pre-fill after the user has signed out.
  Future<String?> readRememberedEmail() => _readRaw(_kRememberedEmail);

  Future<void> writeRememberedEmail(String email) =>
      _storage.write(key: _kRememberedEmail, value: email);

  Future<void> clearRememberedEmail() =>
      _storage.delete(key: _kRememberedEmail);

  // ───── Bulk write after a successful login/refresh ─────
  Future<void> writeAuthBundle({
    required String accessToken,
    required String refreshToken,
    required int expiresInSeconds,
    Map<String, dynamic>? userJson,
  }) async {
    final expiry = DateTime.now().add(Duration(seconds: expiresInSeconds));
    // Write SEQUENTIALLY, not via Future.wait. On web,
    // `flutter_secure_storage` lazily generates its AES-GCM encryption key
    // on the first write. Firing these writes concurrently on a fresh
    // browser (no key yet) makes each first-write generate and persist a
    // DIFFERENT key, last-one-wins — values encrypted under the overwritten
    // keys then fail to decrypt with a WebCrypto `OperationError` on the
    // next read. That surfaced as: login succeeds, but the very first
    // authenticated request hangs forever (the interceptor's token read
    // threw) and never hit the network. Sequencing lets the first write
    // establish the key so the rest reuse it and reads decrypt cleanly.
    await writeAccessToken(accessToken);
    await writeRefreshToken(refreshToken);
    await writeAccessTokenExpiry(expiry);
    if (userJson != null) await writeUserJson(userJson);
  }

  /// Wipes the auth bundle (tokens + user). Safe to call even if some keys
  /// are missing — `flutter_secure_storage.delete` is a no-op for missing keys.
  ///
  /// The remembered email is intentionally preserved so the next login pre-fills
  /// after an explicit logout. Use [clearRememberedEmail] to remove it.
  Future<void> clearAll() async {
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    _cachedAccessTokenExpiry = null;
    await Future.wait([
      _storage.delete(key: _kAccessToken),
      _storage.delete(key: _kRefreshToken),
      _storage.delete(key: _kAccessTokenExpiry),
      _storage.delete(key: _kUserJson),
    ]);
  }

  /// Convenience: do we have ANY persisted session?
  Future<bool> hasSession() async {
    final results = await Future.wait([
      readAccessToken(),
      readRefreshToken(),
    ]);
    return results.every((v) => v != null && v.isNotEmpty);
  }
}

/// Singleton-scoped Riverpod provider for the secure storage service.
final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});
