import '../../../auth/data/models/user.dart';
import '../models/monthly_kra_row.dart';
import '../models/monthly_review.dart';
import '../models/monthly_review_summary.dart';
import '../models/review_stage.dart';

/// Who is asking — drives which reviews the repository returns:
///   - employee → only their own review
///   - manager  → their direct reports
///   - HR / finance / admin / management → the whole (scoped) org
class ReviewScope {
  final String userId;
  final UserRole role;

  const ReviewScope({required this.userId, required this.role});
}

/// Management Review outcome.
enum StageDecision { approve, returnForRework }

/// Contract for the monthly-review domain. The UI binds to this; a mock
/// implementation backs it today and an API implementation will replace it
/// once the new monthly backend ships (swap the provider binding only).
abstract class MonthlyReviewRepository {
  /// Calendar months that have reviews, newest first — feeds the month
  /// selector on every dashboard.
  Future<List<ReviewPeriod>> availablePeriods();

  /// Review summaries for [period], scoped to who is asking.
  Future<List<MonthlyReviewSummary>> listForMonth({
    required ReviewPeriod period,
    required ReviewScope scope,
  });

  /// Full review (with KRA rows + per-stage scores) for the detail/rating
  /// screens.
  Future<MonthlyReview> getReview(String reviewId);

  /// Submit/advance the current stage:
  ///   - rating stages (self / accountHr / reportingManager) pass [rowScores]
  ///     keyed by `MonthlyKraRow.id`
  ///   - [ReviewStage.managementReview] passes a [decision] (+ optional
  ///     [comment]); `approve` advances, `returnForRework` sends it back
  ///
  /// Advances `currentStage` and stamps the stage record. Returns the
  /// updated review.
  Future<MonthlyReview> submitStage({
    required String reviewId,
    required ReviewStage stage,
    required ReviewScope actor,
    Map<String, RowScore>? rowScores,
    StageDecision? decision,
    String? comment,
  });

  /// Marks the incentive paid (the [ReviewStage.incentivePayout] action),
  /// moving the review to `completed`.
  Future<MonthlyReview> markPaid({
    required String reviewId,
    required ReviewScope actor,
  });
}
