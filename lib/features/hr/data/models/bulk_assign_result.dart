import 'kra_assignment.dart';

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
  final int skippedCount;
  final List<String> skippedEmployeeIds;
  final List<KraAssignment> created;

  const BulkAssignResult({
    required this.createdCount,
    required this.skippedCount,
    required this.skippedEmployeeIds,
    required this.created,
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
    return BulkAssignResult(
      createdCount: _asInt(json['createdCount']) ?? createdList.length,
      skippedCount: _asInt(json['skippedCount']) ?? skippedList.length,
      skippedEmployeeIds: skippedList,
      created: createdList,
    );
  }

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
