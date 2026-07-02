/// Outcome of the auto review-sync the backend runs after a (re-)assignment.
/// Ships as `data.reviewGeneration` on the bulk-assign response:
///
///   { created: <int>, updated: <int>, skipped: [{ employeeId, reason }], message: <string> }
///
/// A user only actually sees & fills the generated **Review** (built from the
/// template), so the backend creates a review for each new assignment and
/// rebuilds it for each replaced one. HR surfaces [message] as a toast so they
/// know whether the employee's review is ready — or why it wasn't touched
/// (e.g. a review already in progress with the previous KRA).
///
/// Every field is parsed tolerantly so an unexpected/partial shape can never
/// throw BAD_RESPONSE on an otherwise-successful assign.
class ReviewGeneration {
  /// Number of reviews freshly created (new assignments).
  final int created;

  /// Number of reviews rebuilt to reflect a replaced KRA (re-assignments).
  final int updated;

  /// Human-readable summary the UI shows as a toast.
  final String message;

  /// Per-employee reasons a review was left unchanged (already in progress,
  /// missing manager/location, etc.).
  final List<String> skippedReasons;

  const ReviewGeneration({
    this.created = 0,
    this.updated = 0,
    this.message = '',
    this.skippedReasons = const [],
  });

  factory ReviewGeneration.fromJson(Map<String, dynamic> json) {
    final rawSkipped = json['skipped'];
    final skippedReasons = rawSkipped is List
        ? rawSkipped
            .map((e) {
              if (e is Map && e['reason'] is String) return e['reason'] as String;
              if (e is String) return e;
              return null;
            })
            .whereType<String>()
            .toList()
        : const <String>[];
    return ReviewGeneration(
      created: _asInt(json['created']),
      updated: _asInt(json['updated']),
      message: json['message'] is String ? json['message'] as String : '',
      skippedReasons: skippedReasons,
    );
  }

  /// True when there's a human-readable message worth showing to HR.
  bool get hasMessage => message.trim().isNotEmpty;

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    if (v is bool) return v ? 1 : 0; // tolerate the single-assign {created:bool} shape
    return 0;
  }
}
