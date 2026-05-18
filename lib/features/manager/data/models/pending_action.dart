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

  factory PendingAction.fromJson(Map<String, dynamic> json) =>
      PendingAction(
        reviewId: JsonParse.parseString(json['reviewId']) ?? '',
        employeeId: JsonParse.parseString(json['employeeId']) ?? '',
        employeeName: JsonParse.parseString(json['employeeName']) ?? '',
        employeeCode:
            JsonParse.parseString(json['employeeCode']) ?? '',
        monthLabel: JsonParse.parseString(json['monthLabel']) ?? '',
        submittedAt: JsonParse.parseDate(json['submittedAt']),
        deadlineRemaining:
            JsonParse.parseInt(json['deadlineRemaining']),
      );

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
