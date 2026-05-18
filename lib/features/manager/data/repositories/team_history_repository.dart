import '../models/previous_review.dart';

/// Contract for the team-history list — both the combined view (all
/// reports) and the per-employee filtered view.
abstract class TeamHistoryRepository {
  /// Paginated past reviews across the whole team. `cycleId` filters
  /// to a single cycle; omit for all-time. `employeeId` filters to a
  /// single direct report.
  Future<TeamHistoryPage> listHistory({
    String? employeeId,
    String? cycleId,
    int page = 1,
    int pageSize = 20,
  });
}

/// Pagination wrapper for the team-history list. Reuses
/// [PreviousReview] for the row model — the data the list needs
/// (cycle name, final total, state) matches the previous-review strip
/// already defined for the review detail.
class TeamHistoryPage {
  final List<PreviousReview> reviews;
  final int page;
  final int pageSize;
  final int total;

  const TeamHistoryPage({
    required this.reviews,
    this.page = 1,
    this.pageSize = 20,
    this.total = 0,
  });

  bool get hasMore => reviews.length + ((page - 1) * pageSize) < total;
}
