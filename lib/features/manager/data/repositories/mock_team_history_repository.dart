import '../../../employee/data/models/enums.dart';
import '../models/previous_review.dart';
import 'team_history_repository.dart';

/// Mock combined / per-employee history. Returns 6 past quarters
/// across the team, optionally filtered to one employee. The fixture
/// is intentionally diverse (3 finalized, 2 manager-rated, 1
/// in-progress) so the state badge + score colouring on
/// `history_review_tile.dart` exercises every branch.
class MockTeamHistoryRepository implements TeamHistoryRepository {
  final Duration latency;
  MockTeamHistoryRepository({
    this.latency = const Duration(milliseconds: 350),
  });

  static final List<_HistoryRow> _fixtures = [
    _HistoryRow(
      employeeId: 'emp-sagar',
      review: PreviousReview(
        reviewId: 'rev-sagar-q4',
        cycleName: 'Q4 FY 2025-26',
        fyLabel: 'FY 2025-26',
        quarterNum: 4,
        state: ReviewState.finalized,
        finalTotal: 91.0,
        endDate: DateTime(2026, 3, 31),
      ),
    ),
    _HistoryRow(
      employeeId: 'emp-neha',
      review: PreviousReview(
        reviewId: 'rev-neha-q4',
        cycleName: 'Q4 FY 2025-26',
        fyLabel: 'FY 2025-26',
        quarterNum: 4,
        state: ReviewState.finalized,
        finalTotal: 68.0,
        endDate: DateTime(2026, 3, 31),
      ),
    ),
    _HistoryRow(
      employeeId: 'emp-vikram',
      review: PreviousReview(
        reviewId: 'rev-vikram-q4',
        cycleName: 'Q4 FY 2025-26',
        fyLabel: 'FY 2025-26',
        quarterNum: 4,
        state: ReviewState.finalized,
        finalTotal: 79.0,
        endDate: DateTime(2026, 3, 31),
      ),
    ),
    _HistoryRow(
      employeeId: 'emp-pravin',
      review: PreviousReview(
        reviewId: 'rev-pravin-q4',
        cycleName: 'Q4 FY 2025-26',
        fyLabel: 'FY 2025-26',
        quarterNum: 4,
        state: ReviewState.managerRatedAll,
        finalTotal: 58.0,
        endDate: DateTime(2026, 3, 31),
      ),
    ),
    _HistoryRow(
      employeeId: 'emp-sagar',
      review: PreviousReview(
        reviewId: 'rev-sagar-q3',
        cycleName: 'Q3 FY 2025-26',
        fyLabel: 'FY 2025-26',
        quarterNum: 3,
        state: ReviewState.finalized,
        finalTotal: 88.0,
        endDate: DateTime(2025, 12, 31),
      ),
    ),
    _HistoryRow(
      employeeId: 'emp-anita',
      review: PreviousReview(
        reviewId: 'rev-anita-q4',
        cycleName: 'Q4 FY 2025-26',
        fyLabel: 'FY 2025-26',
        quarterNum: 4,
        state: ReviewState.inProgress,
        endDate: DateTime(2026, 3, 31),
      ),
    ),
  ];

  @override
  Future<TeamHistoryPage> listHistory({
    String? employeeId,
    String? cycleId,
    int page = 1,
    int pageSize = 20,
  }) async {
    await Future<void>.delayed(latency);
    final filtered = _fixtures.where((row) {
      if (employeeId != null && employeeId.isNotEmpty) {
        if (row.employeeId != employeeId) return false;
      }
      return true;
    }).map((r) => r.review).toList();
    final start = (page - 1) * pageSize;
    final end = (start + pageSize).clamp(0, filtered.length);
    final slice =
        start >= filtered.length ? const <PreviousReview>[] : filtered.sublist(start, end);
    return TeamHistoryPage(
      reviews: slice,
      page: page,
      pageSize: pageSize,
      total: filtered.length,
    );
  }
}

class _HistoryRow {
  final String employeeId;
  final PreviousReview review;
  const _HistoryRow({required this.employeeId, required this.review});
}
