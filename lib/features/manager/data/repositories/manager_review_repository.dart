import '../models/manager_review_detail.dart';

/// Contract for fetching a single quarterly review from the manager
/// perspective. Used by the review detail screen and the manager-rate
/// flow (which reads then refetches after each submit).
abstract class ManagerReviewRepository {
  /// Full review payload — rows, monthly scores, totals, permissions,
  /// previous-quarter strip. Throws [ApiError(code: 'NOT_FOUND')] if
  /// [reviewId] doesn't belong to one of the manager's reports.
  Future<ManagerReviewDetail> getReviewDetail(String reviewId);

  /// Sets the top-level manager comment without touching scores or
  /// state. Used by the inline comment editor when the user only
  /// wants to leave a note (e.g. on a finalized review).
  Future<ManagerReviewDetail> setManagerComment({
    required String reviewId,
    required String comment,
  });
}
