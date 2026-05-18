/// Immutable representation of an access + refresh token pair returned
/// by /auth/login and /auth/refresh.
///
/// `expiresIn` is in seconds and represents the lifetime of the access
/// token (NOT the refresh token). Refresh tokens rotate on every use,
/// so their lifetime is policy-defined by the backend.
class TokenPair {
  final String accessToken;
  final String refreshToken;
  final int expiresIn;

  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  factory TokenPair.fromJson(Map<String, dynamic> json) {
    return TokenPair(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresIn: (json['expiresIn'] as num?)?.toInt() ?? 900,
    );
  }
}
