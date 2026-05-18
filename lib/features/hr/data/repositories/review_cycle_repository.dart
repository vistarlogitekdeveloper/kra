import '../models/review_cycle.dart';

abstract class ReviewCycleRepository {
  Future<List<ReviewCycle>> list({ReviewCycleStatus? status});
  Future<ReviewCycle> getById(String id);
  Future<ReviewCycle> create({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    DateTime? selfRatingDeadline,
    DateTime? managerReviewDeadline,
    DateTime? opsScoringDeadline,
    DateTime? financeScoringDeadline,
  });
  Future<ReviewCycle> update(String id, Map<String, dynamic> changes);

  /// Moves a DRAFT cycle to ACTIVE. Server enforces "only one ACTIVE
  /// cycle at a time" — this call may fail with `CYCLE_ALREADY_ACTIVE`.
  Future<ReviewCycle> activate(String id);

  /// Moves an ACTIVE cycle to CLOSED. Irreversible client-side; HR has
  /// to open a fresh cycle to make further changes.
  Future<ReviewCycle> close(String id);
}
