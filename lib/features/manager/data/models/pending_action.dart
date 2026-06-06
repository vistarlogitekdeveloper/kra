import '../../../../core/api/json_parse.dart';

/// One row in the dashboard's "Awaiting your review" list. Tappable —
/// routes to the review detail for `reviewId`.
class PendingAction {
  final String reviewId;
  final String employeeId;
  final String employeeName;
  final String employeeCode;

  /// e.g. "Apr 2026" — the month the employee just self-submitted.
  final String monthLabel;

  /// When the employee submitted their self-rating. Used to render
  /// "submitted 2 days ago" via the existing RelativeTime formatter.
  final DateTime? submittedAt;

  /// Days remaining until the manager-review deadline. Drives the
  /// deadline-chip colour (red overdue, orange ≤3, purple otherwise).
  final int? deadlineRemaining;

  const PendingAction({
    required this.reviewId,
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    required this.monthLabel,
    this.submittedAt,
    this.deadlineRemaining,
  });

  bool get isOverdue =>
      deadlineRemaining != null && deadlineRemaining! < 0;

  factory PendingAction.fromJson(Map<String, dynamic> json) {
    // The live backend nests the employee under an `employee` object;
    // older payloads inline the fields. Read live shape first, fall
    // back to flat — same pattern as TeamMember.fromJson.
    final employee = json['employee'];
    final empMap = employee is Map<String, dynamic> ? employee : const {};

    // Month label may come nested as `month.monthLabel` on live.
    final month = json['month'];
    final monthMap = month is Map<String, dynamic> ? month : const {};

    return PendingAction(
      reviewId: JsonParse.parseString(json['reviewId']) ??
          JsonParse.parseString(json['id']) ??
          '',
      employeeId: JsonParse.parseString(empMap['id']) ??
          JsonParse.parseString(json['employeeId']) ??
          '',
      employeeName: JsonParse.parseString(empMap['name']) ??
          JsonParse.parseString(empMap['fullName']) ??
          JsonParse.parseString(json['employeeName']) ??
          '',
      employeeCode: JsonParse.parseString(empMap['employeeCode']) ??
          JsonParse.parseString(empMap['code']) ??
          JsonParse.parseString(json['employeeCode']) ??
          '',
      monthLabel: JsonParse.parseString(monthMap['monthLabel']) ??
          JsonParse.parseString(monthMap['label']) ??
          JsonParse.parseString(json['monthLabel']) ??
          '',
      submittedAt: JsonParse.parseDate(json['submittedAt']),
      // Live backend names this `daysRemaining`; older payloads use
      // `deadlineRemaining`. Accept either so the deadline/overdue chip
      // isn't silently stuck at null.
      deadlineRemaining: JsonParse.parseInt(json['deadlineRemaining']) ??
          JsonParse.parseInt(json['daysRemaining']),
    );
  }

  Map<String, dynamic> toJson() => {
        'reviewId': reviewId,
        'employeeId': employeeId,
        'employeeName': employeeName,
        'employeeCode': employeeCode,
        'monthLabel': monthLabel,
        'submittedAt': submittedAt?.toIso8601String(),
        'deadlineRemaining': deadlineRemaining,
      };
}
