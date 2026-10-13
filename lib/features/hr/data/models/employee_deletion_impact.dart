import '../../../../core/api/json_parse.dart';

/// What a permanent delete would remove, previewed before it happens.
///
/// From `GET /employees/:id/deletion-impact`, which deletes nothing. The counts
/// fall into three groups that mean genuinely different things to the person
/// confirming, so they are kept apart here rather than summed:
///
///   * [ownCounts] — this employee's own record.
///   * [marksOnOthers] — what this person did to OTHER people's records. These
///     are deleted too, and it is the group nobody expects: purging a manager
///     removes the reviews they rated for their whole team.
///   * [subordinates] — reports who are DETACHED, not deleted. Their manager
///     becomes empty.
class EmployeeDeletionImpact {
  final String employeeId;
  final String? employeeCode;
  final String? name;
  final bool isActive;

  // ── the employee's own data ──
  final int reviewsAsEmployee;
  final int assignmentsOwn;
  final int monthlyReviews;

  // ── their marks on other people's records ──
  final int reviewsAsManager;
  final int assignmentsMade;
  final int hrFeedsEntered;
  final int accountsFeedsEntered;
  final int opsFeedsEntered;
  final int opsScopesAssigned;

  // ── detached, not deleted ──
  final int subordinates;

  const EmployeeDeletionImpact({
    required this.employeeId,
    this.employeeCode,
    this.name,
    this.isActive = true,
    this.reviewsAsEmployee = 0,
    this.assignmentsOwn = 0,
    this.monthlyReviews = 0,
    this.reviewsAsManager = 0,
    this.assignmentsMade = 0,
    this.hrFeedsEntered = 0,
    this.accountsFeedsEntered = 0,
    this.opsFeedsEntered = 0,
    this.opsScopesAssigned = 0,
    this.subordinates = 0,
  });

  factory EmployeeDeletionImpact.fromJson(Map<String, dynamic> json) {
    // The counts arrive nested under `removes`; tolerate a flat shape too, the
    // way every other model here dual-reads its live and spec forms.
    final removes = JsonParse.parseMap(json['removes']) ?? json;
    int count(String key) => JsonParse.parseInt(removes[key]) ?? 0;

    return EmployeeDeletionImpact(
      employeeId: (json['employeeId'] ?? '') as String,
      employeeCode: json['employeeCode'] as String?,
      name: json['name'] as String?,
      isActive: JsonParse.parseBool(json['isActive']) ?? true,
      reviewsAsEmployee: count('reviewsAsEmployee'),
      assignmentsOwn: count('assignmentsOwn'),
      monthlyReviews: count('monthlyReviews'),
      reviewsAsManager: count('reviewsAsManager'),
      assignmentsMade: count('assignmentsMade'),
      hrFeedsEntered: count('hrFeedsEntered'),
      accountsFeedsEntered: count('accountsFeedsEntered'),
      opsFeedsEntered: count('opsFeedsEntered'),
      opsScopesAssigned: count('opsScopesAssigned'),
      subordinates: count('subordinates'),
    );
  }

  /// Everything belonging to this employee alone.
  int get ownTotal => reviewsAsEmployee + assignmentsOwn + monthlyReviews;

  /// Everything this person entered against SOMEBODY ELSE's record.
  ///
  /// Called out separately because it is the surprising half: deleting a
  /// manager takes their team's ratings with them.
  int get marksOnOthersTotal =>
      reviewsAsManager +
      assignmentsMade +
      hrFeedsEntered +
      accountsFeedsEntered +
      opsFeedsEntered +
      opsScopesAssigned;

  /// True when the delete removes nothing but the employee row itself.
  bool get isEmpty =>
      ownTotal == 0 && marksOnOthersTotal == 0 && subordinates == 0;

  /// True when other people's records lose data — the case worth a louder
  /// warning than "this employee will be deleted".
  bool get touchesOthers => marksOnOthersTotal > 0 || subordinates > 0;
}
