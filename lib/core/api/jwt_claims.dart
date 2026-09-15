import 'dart:convert';

/// Minimal reader for the *unverified* claims in a JWT payload.
///
/// Verification is the server's job — this only reads what the server already
/// signed, to answer a question the API does not otherwise expose.
///
/// Specifically: which organisation is this token acting as?
///
/// `/auth/me` returns the employee record's own `organizationId` — their HOME
/// organisation, the column on their row. A super admin who switches tenant
/// gets a token whose `organizationId` claim is the organisation they are
/// acting AS, and every backend query scopes by that claim. Those two values
/// disagree after a switch, and the claim is the one that decides what the
/// server returns. Measured:
///
///     token claim      -> be7b0ad6…  (vistar-logitek)
///     /auth/me         -> org_vistar_test
///     GET /employees   -> vistar-logitek's employees
///
/// So the claim is authoritative for scoping, and reading it here is how the
/// client stays honest about which tenant it is showing.
class JwtClaims {
  const JwtClaims._();

  /// The `organizationId` claim, or null when the token is absent,
  /// malformed, or carries no such claim.
  ///
  /// Never throws: a token this cannot parse simply yields null and the caller
  /// falls back to the user's home organisation.
  static String? organizationId(String? token) {
    final claims = decode(token);
    final value = claims?['organizationId'];
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  /// The payload segment as a map, or null if it cannot be read.
  static Map<String, dynamic>? decode(String? token) {
    if (token == null || token.isEmpty) return null;
    final parts = token.split('.');
    // header.payload.signature — anything else is not a JWS compact token.
    if (parts.length != 3) return null;
    try {
      // base64Url in a JWT is unpadded; normalize() adds the '=' back, which
      // base64Url.decode requires.
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      // A token we cannot read is not an error worth surfacing — the caller
      // has a sensible fallback.
      return null;
    }
  }
}
