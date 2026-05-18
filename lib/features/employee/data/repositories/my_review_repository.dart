import '../models/my_review_detail.dart';
import '../models/my_review_summary.dart';

/// Contract for fetching the logged-in employee's review history.
///
/// Two operations: a paginated list (history tab) and a single-id
/// detail (drill-down). Both filtered server-side by employeeId.
abstract class MyReviewRepository {
  /// Paginated list of my reviews. Newest first. Filter by [cycleId]
  /// to narrow to one cycle. [page] is 1-indexed.
  Future<MyReviewPage> listMyReviews({
    String? cycleId,
    int page = 1,
    int pageSize = 20,
  });

  /// Full detail (per-rater score blocks, comments, totals) for one
  /// review. Throws [ApiError(code: NOT_FOUND)] if [reviewId] doesn't
  /// belong to the current user.
  Future<MyReviewDetail> getReviewDetail(String reviewId);
}
