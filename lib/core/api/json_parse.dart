/// JSON parsing helpers tolerant of the backend's serialization quirks.
///
/// The backend persists money / scores / weightages with Prisma `Decimal`,
/// which serialises to a JSON **string** ("0.05", "7000.00") to preserve
/// precision. A direct `as num` cast throws on those values, so every
/// numeric field that originates from a Decimal column must be read via
/// [parseDouble] / [parseInt].
///
/// Also tolerates the inverse: dev-mode mock servers occasionally send
/// numbers where the contract specifies strings. Both shapes round-trip
/// cleanly here.
class JsonParse {
  JsonParse._();

  /// Parses a value that may be `num`, numeric `String`, or `null`.
  /// Returns `null` for anything unrecognisable rather than throwing —
  /// callers can supply their own default with `?? 0`.
  static double? parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      if (value.isEmpty) return null;
      return double.tryParse(value);
    }
    return null;
  }

  /// Like [parseDouble] but for integer fields. Truncates non-integer
  /// numerics — callers wanting strict integer-only behaviour should
  /// validate at the call site.
  static int? parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      if (value.isEmpty) return null;
      final asInt = int.tryParse(value);
      if (asInt != null) return asInt;
      return double.tryParse(value)?.toInt();
    }
    return null;
  }

  /// Parses an ISO 8601 date / datetime. Returns `null` on malformed
  /// input rather than throwing — date parsing failures should not
  /// take down the whole screen.
  static DateTime? parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  /// Parses a string field, tolerating `null` and non-string types
  /// (returns `null` for the latter rather than throwing).
  static String? parseString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  /// Parses a `bool` field, tolerating numeric `0` / `1` and string
  /// `"true"` / `"false"` for unmodelled backends.
  static bool? parseBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final lower = value.toLowerCase();
      if (lower == 'true') return true;
      if (lower == 'false') return false;
    }
    return null;
  }

  /// Returns the value at [key] as a `Map<String, dynamic>` if it is one,
  /// otherwise `null`. Useful for nested-object fields that may be omitted.
  static Map<String, dynamic>? parseMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  /// Returns a `List<Map<String, dynamic>>` from a value that may be a
  /// `List<dynamic>` of maps or `null`. Non-map entries are filtered out.
  static List<Map<String, dynamic>> parseMapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map(parseMap)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }
}
