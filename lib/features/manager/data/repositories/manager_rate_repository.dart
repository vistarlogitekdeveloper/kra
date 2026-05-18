import '../models/manager_rate_request.dart';
import '../models/manager_rate_response.dart';

/// Contract for the manager rate / re-rate flow.
///
/// Three methods, each with its own endpoint:
///
///   1. [autoSaveScores] — debounced 5s save via the shared
///      `POST /reviews/:id/scores` endpoint with `side: 'MANAGER'`.
///      Persists draft scores without triggering a state transition.
///
///   2. [submitRating] — `POST /manager/reviews/:id/manager-rate` with
///      `autoSubmit: true`. The response carries `transitioned: bool`
///      which the UI MUST honour distinctly from a clean success.
///
///   3. [updateRating] — `PATCH /manager/reviews/:id/manager-rate`.
///      Only valid when state=MANAGER_RATED_ALL and pre-deadline.
///      Same response shape as submit.
abstract class ManagerRateRepository {
  /// Cell-level partial save. Does NOT mutate review state. Returns
  /// the count of cells that were persisted server-side so the UI can
  /// surface a "Saved N cells" indicator on success.
  Future<int> autoSaveScores({
    required String reviewId,
    required ManagerRateRequest scores,
  });

  /// Final submit. `autoSubmit` defaults to true on the request body.
  Future<ManagerRateResponse> submitRating({
    required String reviewId,
    required ManagerRateRequest request,
  });

  /// Re-rate after a previous MANAGER_RATED_ALL — server enforces the
  /// state precondition and deadline.
  Future<ManagerRateResponse> updateRating({
    required String reviewId,
    required ManagerRateRequest request,
  });
}
