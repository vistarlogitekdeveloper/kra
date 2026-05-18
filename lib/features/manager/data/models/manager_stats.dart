import '../../../../core/api/json_parse.dart';

/// 2×2 KPI grid on the manager dashboard. Each card maps 1:1 to a
/// pre-applied team-list filter — tap → list scoped to that bucket.
class ManagerStats {
  final int totalReports;
  final int pendingMyReview;
  final int completedThisMonth;
  final int overdueReviews;

  const ManagerStats({
    required this.totalReports,
    required this.pendingMyReview,
    required this.completedThisMonth,
    required this.overdueReviews,
  });

  /// True if the manager has any pending work right now — used by the
  /// "My Team" mode pill's notification badge.
  bool get hasPendingWork =>
      pendingMyReview > 0 || overdueReviews > 0;

  factory ManagerStats.fromJson(Map<String, dynamic> json) => ManagerStats(
        totalReports: JsonParse.parseInt(json['totalReports']) ?? 0,
        pendingMyReview: JsonParse.parseInt(json['pendingMyReview']) ?? 0,
        completedThisMonth:
            JsonParse.parseInt(json['completedThisMonth']) ?? 0,
        overdueReviews: JsonParse.parseInt(json['overdueReviews']) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'totalReports': totalReports,
        'pendingMyReview': pendingMyReview,
        'completedThisMonth': completedThisMonth,
        'overdueReviews': overdueReviews,
      };
}
