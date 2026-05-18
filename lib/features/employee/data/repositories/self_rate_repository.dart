import '../models/my_review_detail.dart';
import '../models/self_rate_request.dart';

/// Contract for recording / updating self-ratings.
///
/// One method — the POST endpoint is idempotent and handles both new
/// entries and edits. Validations enforced server-side (in order):
///   1. Review exists and belongs to the caller (404 otherwise)
///   2. review.state ∈ {DRAFT, IN_PROGRESS, EMPLOYEE_SUBMITTED_ALL}
///      (409 once the manager has begun)
///   3. cycle.selfRatingDeadline >= now() (403 past deadline)
///   4. Every monthlyScoreId belongs to this review (400 otherwise)
///   5. Every cell's month.status === 'OPEN' (409 if locked)
///   6. selfRating <= row.maxScore (validated by the underlying svc)
///
/// State transitions:
///   - DRAFT + first score → IN_PROGRESS (automatic)
///   - IN_PROGRESS + all cells rated + autoSubmit !== false →
///     EMPLOYEE_SUBMITTED_ALL
///   - Otherwise: state unchanged
abstract class SelfRateRepository {
  /// Records or updates self-ratings on the named cells. Returns the
  /// fully refreshed [MyReview] (state, totals, all rows / cells).
  Future<MyReview> submitSelfRating({
    required String reviewId,
    required SelfRateRequest request,
  });
}
