import '../../../../core/api/json_parse.dart';

/// FY-wide review counts displayed on the team-member profile screen.
/// Cheap aggregate — no per-cycle drill-down here (that's the History
/// tab's job).
class FyReviewSummary {
  final int totalReviews;
  final int finalizedCount;
  final int pendingCount;
  final double? averageFinalScore;

  const FyReviewSummary({
    required this.totalReviews,
    required this.finalizedCount,
    required this.pendingCount,
    this.averageFinalScore,
  });

  factory FyReviewSummary.fromJson(Map<String, dynamic> json) =>
      FyReviewSummary(
        totalReviews: JsonParse.parseInt(json['totalReviews']) ?? 0,
        finalizedCount: JsonParse.parseInt(json['finalizedCount']) ?? 0,
        pendingCount: JsonParse.parseInt(json['pendingCount']) ?? 0,
        averageFinalScore:
            JsonParse.parseDouble(json['averageFinalScore']),
      );

  Map<String, dynamic> toJson() => {
        'totalReviews': totalReviews,
        'finalizedCount': finalizedCount,
        'pendingCount': pendingCount,
        'averageFinalScore': averageFinalScore,
      };
}
