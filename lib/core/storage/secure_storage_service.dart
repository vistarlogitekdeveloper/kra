import 'dart:convert';

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

  final FlutterSecureStorage _storage;

  SecureStorageService([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  // In-memory cache to prevent heavy secure-storage reads on every API call
  String? _cachedAccessToken;
  String? _cachedRefreshToken;

  // ───── Access token ─────
  Future<String?> readAccessToken() async {
    if (_cachedAccessToken != null) return _cachedAccessToken;
    _cachedAccessToken = await _storage.read(key: _kAccessToken);
    return _cachedAccessToken;
  }

  Future<void> writeAccessToken(String token) async {
    _cachedAccessToken = token;
    await _storage.write(key: _kAccessToken, value: token);
  }

  // ───── Refresh token ─────
  Future<String?> readRefreshToken() async {
    if (_cachedRefreshToken != null) return _cachedRefreshToken;
    _cachedRefreshToken = await _storage.read(key: _kRefreshToken);
    return _cachedRefreshToken;
  }

  Future<void> writeRefreshToken(String token) async {
    _cachedRefreshToken = token;
    await _storage.write(key: _kRefreshToken, value: token);
  }

  // ───── Token expiry (epoch ms) — used for proactive refresh later ─────
  Future<DateTime?> readAccessTokenExpiry() async {
    final raw = await _storage.read(key: _kAccessTokenExpiry);
    if (raw == null) return null;
    final ms = int.tryParse(raw);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> writeAccessTokenExpiry(DateTime expiry) => _storage.write(
        key: _kAccessTokenExpiry,
        value: expiry.millisecondsSinceEpoch.toString(),
      );

  // ───── User payload (JSON-encoded) ─────
  Future<Map<String, dynamic>?> readUserJson() async {
    final raw = await _storage.read(key: _kUserJson);
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

  // ───── Bulk write after a successful login/refresh ─────
  Future<void> writeAuthBundle({
    required String accessToken,
    required String refreshToken,
    required int expiresInSeconds,
    Map<String, dynamic>? userJson,
  }) async {
    final expiry = DateTime.now().add(Duration(seconds: expiresInSeconds));
    await Future.wait([
      writeAccessToken(accessToken),
      writeRefreshToken(refreshToken),
      writeAccessTokenExpiry(expiry),
      if (userJson != null) writeUserJson(userJson),
    ]);
  }

  /// Wipes every key this service writes. Safe to call even if some keys
  /// are missing — `flutter_secure_storage.delete` is a no-op for missing keys.
  Future<void> clearAll() async {
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
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
