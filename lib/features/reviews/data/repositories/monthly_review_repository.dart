import '../../../auth/data/models/user.dart';
import '../models/monthly_review.dart';
import '../models/monthly_review_summary.dart';
import '../models/review_stage.dart';
import '../models/row_score.dart';

/// Contract the presentation layer binds to. The only implementation
/// today is [MockMonthlyReviewRepository] (in-memory seed data), used
/// until a monthly-review backend ships; a future `ApiMonthlyReview
/// Repository` would implement the same surface against `/reviews/monthly`.
abstract class MonthlyReviewRepository {
  /// Lists review summaries for a specific ([year], [month]).
  ///
  /// Scope filters narrow to what a dashboard needs:
  ///   * [scopeEmployeeId] — one employee (their own home)
  ///   * [scopeManagerId] — a manager's direct reports
  ///   * [scopeRole] — informational (whose lens we filter through)
  ///   * [currentStage] — only reviews sitting on a specific stage
  ///     (e.g. the payout screen wants only [ReviewStage.incentivePayout])
  Future<List<MonthlyReviewSummary>> listMonthlyReviews({
    required int year,
    required int month,
    UserRole? scopeRole,
    String? scopeEmployeeId,
    String? scopeManagerId,
    ReviewStage? currentStage,
  });

  /// Full [MonthlyReview] for [id] — rows and stage records populated.
  Future<MonthlyReview> getReview(String id);

  /// Submits [stage] on [reviewId]. Payload varies by stage:
  ///   * Rating stages — [rowScores] maps row id → the actor's score.
  ///   * Management review — [approved] `true` advances, `false` returns
  ///     the review to the reporting manager; [comment] explains a return.
  ///   * Incentive payout — use [markPaid] instead.
  ///
  /// Rejects the submit if [stage] != the review's `currentStage`.
  Future<MonthlyReview> submitStage(
    String reviewId,
    ReviewStage stage, {
    Map<String, RowScore>? rowScores,
    bool? approved,
    String? comment,
    required String actorId,
    required String actorName,
  });

  /// Marks payout on [reviewId] paid and advances to
  /// [ReviewStage.completed].
  Future<MonthlyReview> markPaid(
    String reviewId, {
    required String actorId,
    required String actorName,
  });
}
