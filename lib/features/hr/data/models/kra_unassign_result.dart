import '../../../../core/api/json_parse.dart';

/// Outcome of removing ONE KRA assignment.
///
/// From `DELETE /kra-assignments/:id`. The two booleans are the whole reason
/// this is a model rather than a void: unassigning does not always take the
/// review with it, and the user has to be told which happened.
class KraUnassignResult {
  final bool deleted;
  final String id;
  final String? employeeId;
  final String? cycleId;

  /// A DRAFT review generated from this assignment was removed with it.
  final bool reviewRemoved;

  /// A review was KEPT because scores already exist on it.
  ///
  /// The assignment is gone but the review is not, which is a half-done state
  /// the user will otherwise discover later — so it gets its own message.
  final bool reviewLeftInProgress;

  const KraUnassignResult({
    required this.deleted,
    required this.id,
    this.employeeId,
    this.cycleId,
    this.reviewRemoved = false,
    this.reviewLeftInProgress = false,
  });

  factory KraUnassignResult.fromJson(Map<String, dynamic> json) =>
      KraUnassignResult(
        deleted: JsonParse.parseBool(json['deleted']) ?? false,
        id: (json['id'] ?? '') as String,
        employeeId: json['employeeId'] as String?,
        cycleId: json['cycleId'] as String?,
        reviewRemoved: JsonParse.parseBool(json['reviewRemoved']) ?? false,
        reviewLeftInProgress:
            JsonParse.parseBool(json['reviewLeftInProgress']) ?? false,
      );
}

/// Outcome of clearing EVERY KRA assignment for one employee.
///
/// From `DELETE /kra-assignments/employee/:employeeId`. `deletedCount` of 0 is
/// a success, not a failure — it means they had none.
class KraUnassignAllResult {
  final int deletedCount;
  final String? employeeId;

  /// Null when every cycle was cleared; set when the call was scoped to one.
  final String? cycleId;

  final List<KraUnassignResult> items;

  const KraUnassignAllResult({
    required this.deletedCount,
    this.employeeId,
    this.cycleId,
    this.items = const [],
  });

  factory KraUnassignAllResult.fromJson(Map<String, dynamic> json) =>
      KraUnassignAllResult(
        deletedCount: JsonParse.parseInt(json['deletedCount']) ?? 0,
        employeeId: json['employeeId'] as String?,
        cycleId: json['cycleId'] as String?,
        items: JsonParse.parseMapList(json['items'])
            .map(KraUnassignResult.fromJson)
            .toList(),
      );

  /// How many reviews were left behind with scores on them.
  int get reviewsLeftInProgress =>
      items.where((i) => i.reviewLeftInProgress).length;
}
