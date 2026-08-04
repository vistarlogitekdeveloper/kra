// Small pure helpers for turning a person's full name into display bits —
// shared so avatars and greetings read the same everywhere.

/// Two-letter initials for an avatar: the leading letter of the first and last
/// name words, uppercased (a single word gives one letter). Falls back to '·'
/// for a blank name.
String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '·';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

/// The first word of [name], or [fallback] when it's blank — for "Hi, Asha".
String firstNameOf(String name, {String fallback = 'there'}) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts.isEmpty || parts.first.isEmpty ? fallback : parts.first;
}
