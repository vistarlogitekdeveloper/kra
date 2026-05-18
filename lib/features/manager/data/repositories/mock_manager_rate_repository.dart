import '../../../employee/data/models/enums.dart';
import '../models/manager_rate_request.dart';
import '../models/manager_rate_response.dart';
import '../models/manager_review_detail.dart';
import '../models/monthly_score.dart';
import '../models/review_row.dart';
import '../models/transition_error.dart';
import 'manager_rate_repository.dart';
import 'mock_manager_review_repository.dart';

/// In-memory fake of the manager-rate flow. Persists score edits via
/// `MockManagerReviewRepository.applyManagerScoreOverride` so that
/// navigating to the detail screen after a submit shows the saved
/// state — matching the real backend's behaviour.
///
/// Exercises both the clean-success path (transitioned=true) and the
/// partial-success path: any review id with `partial` in it returns
/// `transitioned=false` with an `INCOMPLETE_AFTER_COPY` error so the
/// partial-success screen can be developed without a backend.
class MockManagerRateRepository implements ManagerRateRepository {
  final Duration latency;
  MockManagerRateRepository({
    this.latency = const Duration(milliseconds: 400),
  });

  final MockManagerReviewRepository _reviewRepo =
      MockManagerReviewRepository();

  @override
  Future<int> autoSaveScores({
    required String reviewId,
    required ManagerRateRequest scores,
  }) async {
    // Auto-save: just apply the scores to the in-memory override and
    // return the count. No state transition, no response payload.
    await Future<void>.delayed(latency);
    await _applyScoresToReview(reviewId, scores);
    return scores.scores.length;
  }

  @override
  Future<ManagerRateResponse> submitRating({
    required String reviewId,
    required ManagerRateRequest request,
  }) {
    return _submitOrUpdate(
      reviewId: reviewId,
      request: request,
      transitionTo: ReviewState.managerRatedAll,
    );
  }

  @override
  Future<ManagerRateResponse> updateRating({
    required String reviewId,
    required ManagerRateRequest request,
  }) {
    // PATCH: scores update but the review stays at MANAGER_RATED_ALL.
    return _submitOrUpdate(
      reviewId: reviewId,
      request: request,
      transitionTo: ReviewState.managerRatedAll,
    );
  }

  // ───── Internals ─────

  Future<ManagerRateResponse> _submitOrUpdate({
    required String reviewId,
    required ManagerRateRequest request,
    required ReviewState transitionTo,
  }) async {
    await Future<void>.delayed(latency);
    final updatedReview = await _applyScoresToReview(reviewId, request);

    // Demo: any id containing "partial" simulates the
    // transitioned=false case so the partial-success screen has a
    // realistic trigger during development.
    if (reviewId.contains('partial')) {
      return ManagerRateResponse(
        state: updatedReview.state,
        totals: updatedReview.totals,
        transitioned: false,
        transitionError: const TransitionError(
          code: 'INCOMPLETE_AFTER_COPY',
          message:
              'Ops or Finance hasn\'t filled in some scores yet.',
        ),
      );
    }

    final next = updatedReview.copyWith(state: transitionTo);
    MockManagerReviewRepository.applyManagerScoreOverride(next);
    return ManagerRateResponse(
      state: next.state,
      totals: next.totals,
      transitioned: true,
    );
  }

  /// Folds the request's scores into the review's matrix and persists
  /// the updated detail back into the review-repo override map. Also
  /// recomputes the manager total so the submit response carries the
  /// right number for the success screen.
  Future<ManagerReviewDetail> _applyScoresToReview(
    String reviewId,
    ManagerRateRequest request,
  ) async {
    final current = await _reviewRepo.getReviewDetail(reviewId);
    final byId = {for (final s in request.scores) s.monthlyScoreId: s};
    final newRows = <ReviewRow>[];
    for (final row in current.rows) {
      final newCells = <MonthlyScore>[];
      for (final cell in row.monthlyScores) {
        final patch = byId[cell.monthlyScoreId];
        if (patch == null) {
          newCells.add(cell);
        } else {
          newCells.add(cell.copyWith(
            managerRating: patch.managerRating,
            managerRemark: patch.managerRemark,
          ));
        }
      }
      newRows.add(row.copyWith(monthlyScores: newCells));
    }
    final updated = current.copyWith(
      rows: newRows,
      managerComment: request.managerComment ?? current.managerComment,
      totals: current.totals.copyWith(
        managerTotal: _computeManagerTotal(newRows),
      ),
    );
    MockManagerReviewRepository.applyManagerScoreOverride(updated);
    return updated;
  }

  /// Crude weighted-average of manager ratings for the demo. Matches
  /// the shape of `KraScoreEntry.weightedContribution` from the
  /// employee module — N/A cells excluded from the denominator.
  double? _computeManagerTotal(List<ReviewRow> rows) {
    double weightedSum = 0;
    double remainingWeight = 0;
    for (final row in rows) {
      for (final cell in row.monthlyScores) {
        if (cell.isNotApplicable) continue;
        final r = cell.managerRating;
        if (r == null) continue;
        final pct = row.weightagePercent / row.monthlyScores.length;
        weightedSum += (r / row.maxScore) * pct;
        remainingWeight += pct;
      }
    }
    if (remainingWeight <= 0) return null;
    return (weightedSum * 100 / remainingWeight).clamp(0.0, 100.0);
  }
}
