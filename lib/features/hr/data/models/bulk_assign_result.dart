import 'kra_assignment.dart';
import 'review_generation.dart';

/// Result of `POST /kra-assignments/bulk`. The backend is idempotent —
/// re-assigning a template to an employee who already has it for the same
/// cycle does NOT error; the employee id goes into [skippedEmployeeIds] and
/// [createdCount] reflects only the genuinely-new assignments.
///
/// The wire shape (verified against the live backend, 2026-06-06):
///   { data: { createdCount, skippedCount, skippedEmployeeIds, created: [] } }
///
/// `unwrapList` could not parse this — `data` is a Map, not a List — which
/// caused the confirm step to throw BAD_RESPONSE even on a 201 success.
class BulkAssignResult {
  final int createdCount;

  /// Employees who already had a KRA this cycle and whose assignment was
  /// REPLACED with the newly-picked template (re-assign). The backend upserts
  /// rather than silently skipping, so a "different KRA" actually takes effect.
  final int updatedCount;
  final int skippedCount;
  final List<String> skippedEmployeeIds;
  final List<KraAssignment> created;

  /// Outcome of the auto review generation the backend runs after assigning.
  /// Null when the response doesn't carry a `reviewGeneration` block.
  final ReviewGeneration? reviewGeneration;

  const BulkAssignResult({
    required this.createdCount,
    this.updatedCount = 0,
    required this.skippedCount,
    required this.skippedEmployeeIds,
    required this.created,
    this.reviewGeneration,
  });

  factory BulkAssignResult.fromJson(Map<String, dynamic> json) {
    final rawCreated = json['created'];
    final createdList = rawCreated is List
        ? rawCreated
            .whereType<Map<String, dynamic>>()
            .map(KraAssignment.fromJson)
            .toList()
        : const <KraAssignment>[];
    final rawSkipped = json['skippedEmployeeIds'];
    final skippedList = rawSkipped is List
        ? rawSkipped.whereType<String>().toList()
        : const <String>[];
    final rawReviewGen = json['reviewGeneration'];
    return BulkAssignResult(
      createdCount: _asInt(json['createdCount']) ?? createdList.length,
      updatedCount: _asInt(json['updatedCount']) ?? 0,
      skippedCount: _asInt(json['skippedCount']) ?? skippedList.length,
      skippedEmployeeIds: skippedList,
      created: createdList,
      reviewGeneration: rawReviewGen is Map<String, dynamic>
          ? ReviewGeneration.fromJson(rawReviewGen)
          : null,
    );
  }

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
