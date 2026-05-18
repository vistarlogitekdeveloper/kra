import '../../../employee/data/models/enums.dart';
import '../models/manager_review_detail.dart';
import '../models/monthly_score.dart';
import '../models/previous_review.dart';
import '../models/review_permissions.dart';
import '../models/review_row.dart';
import '../models/review_totals.dart';
import 'manager_review_repository.dart';

/// In-memory fake for the manager-review detail. Returns a fully-
/// populated Q1 review for whichever id the caller asks about — the
/// employee header and review state vary with the id so the demo can
/// exercise every state-dependent UI branch.
///
/// Persists any `setManagerComment` calls in a module-private map so
/// the comment round-trips during a single app session.
class MockManagerReviewRepository implements ManagerReviewRepository {
  final Duration latency;
  MockManagerReviewRepository({
    this.latency = const Duration(milliseconds: 350),
  });

  /// Round-trips the comment within a session.
  final Map<String, String> _commentOverrides = {};

  /// Round-trips score edits made via the manager-rate flow.
  /// `applyManagerScoreOverride` lets the rate-repo mock keep this in
  /// sync — without it, navigating back to the detail would reset
  /// scores to the fixture and confuse the user.
  static final Map<String, ManagerReviewDetail> _stateOverrides = {};
  static void applyManagerScoreOverride(ManagerReviewDetail updated) {
    _stateOverrides[updated.id] = updated;
  }

  @override
  Future<ManagerReviewDetail> getReviewDetail(String reviewId) async {
    await Future<void>.delayed(latency);
    final override = _stateOverrides[reviewId];
    final base = override ?? _fixtureFor(reviewId);
    final comment = _commentOverrides[reviewId] ?? base.managerComment;
    return base.copyWith(managerComment: comment);
  }

  @override
  Future<ManagerReviewDetail> setManagerComment({
    required String reviewId,
    required String comment,
  }) async {
    await Future<void>.delayed(latency);
    _commentOverrides[reviewId] = comment;
    return getReviewDetail(reviewId);
  }

  // ───── Fixture builder ─────

  ManagerReviewDetail _fixtureFor(String reviewId) {
    // Map known review ids to known states so the rate / readonly /
    // waiting flows all have something realistic to render.
    final scenario = _scenarioFor(reviewId);
    final now = DateTime.now();
    final months = [
      ManagerReviewMonth(
        id: 'm-apr-26',
        monthLabel: 'Apr 2026',
        monthDate: DateTime(2026, 4, 1),
        status: ReviewMonthStatus.open,
      ),
      ManagerReviewMonth(
        id: 'm-may-26',
        monthLabel: 'May 2026',
        monthDate: DateTime(2026, 5, 1),
        status: ReviewMonthStatus.open,
      ),
      ManagerReviewMonth(
        id: 'm-jun-26',
        monthLabel: 'Jun 2026',
        monthDate: DateTime(2026, 6, 1),
        status: scenario.lockJune
            ? ReviewMonthStatus.locked
            : ReviewMonthStatus.open,
      ),
    ];

    final rows = [
      _kraRow(
        id: 'kra-quality',
        name: 'Quality of Work',
        category: 'CORE',
        weightagePct: 30,
        sortOrder: 1,
        scoreSource: ScoreSource.manager,
        months: months,
        scenario: scenario,
        selfRatings: const [8, 8.5, 9],
        managerRatings: scenario.populateManagerScores
            ? const [9, 9, 9.5]
            : const [null, null, null],
      ),
      _kraRow(
        id: 'kra-delivery',
        name: 'On-Time Delivery',
        category: 'CORE',
        weightagePct: 25,
        sortOrder: 2,
        scoreSource: ScoreSource.manager,
        months: months,
        scenario: scenario,
        selfRatings: const [7.5, 8, 8.5],
        managerRatings: scenario.populateManagerScores
            ? const [8, 8, 9]
            : const [null, null, null],
      ),
      _kraRow(
        id: 'kra-customer',
        name: 'Customer Escalations',
        category: 'OPS',
        weightagePct: 25,
        sortOrder: 3,
        scoreSource: ScoreSource.feed, // Ops-fed, not manager-editable
        months: months,
        scenario: scenario,
        selfRatings: const [9, 8, 7.5],
        managerRatings: const [9, 8, 7.5],
      ),
      _kraRow(
        id: 'kra-teamwork',
        name: 'Teamwork & Collaboration',
        category: 'SOFT',
        weightagePct: 20,
        sortOrder: 4,
        scoreSource: ScoreSource.manager,
        months: months,
        scenario: scenario,
        selfRatings: const [8.5, 9, 9],
        managerRatings: scenario.populateManagerScores
            ? const [9, 9, 9.5]
            : const [null, null, null],
      ),
    ];

    return ManagerReviewDetail(
      id: reviewId,
      state: scenario.state,
      isLocked: scenario.isLocked,
      employee: ManagerReviewEmployee(
        id: scenario.employeeId,
        name: scenario.employeeName,
        employeeCode: scenario.employeeCode,
        role: 'EMPLOYEE',
        projectLocation: 'Pune HQ',
      ),
      cycle: ManagerReviewCycle(
        id: 'cycle-q1-fy27',
        name: 'Q1 FY 2026-27',
        fyLabel: 'FY 2026-27',
        quarterNum: 1,
        startDate: DateTime(2026, 4, 1),
        endDate: DateTime(2026, 6, 30),
        managerReviewDeadline: now.add(const Duration(days: 5)),
        months: months,
      ),
      rows: rows,
      totals: ReviewTotals(
        selfTotal: scenario.populateSelfTotal ? 81.5 : null,
        managerTotal: scenario.populateManagerScores ? 90.4 : null,
        finalTotal: scenario.state == ReviewState.finalized ||
                scenario.state == ReviewState.acknowledged
            ? 88.0
            : null,
        incentiveAmount: scenario.state == ReviewState.finalized ||
                scenario.state == ReviewState.acknowledged
            ? 5325
            : null,
      ),
      previousReviews: [
        PreviousReview(
          reviewId: 'rev-prev-q4',
          cycleName: 'Q4 FY 2025-26',
          fyLabel: 'FY 2025-26',
          quarterNum: 4,
          state: ReviewState.finalized,
          finalTotal: 85.0,
          endDate: DateTime(2026, 3, 31),
        ),
        PreviousReview(
          reviewId: 'rev-prev-q3',
          cycleName: 'Q3 FY 2025-26',
          fyLabel: 'FY 2025-26',
          quarterNum: 3,
          state: ReviewState.finalized,
          finalTotal: 78.0,
          endDate: DateTime(2025, 12, 31),
        ),
      ],
      managerComment: scenario.populateManagerScores
          ? 'Strong quarter — keep the consistency on customer escalations.'
          : null,
      permissions: ReviewPermissions(
        canRate: scenario.state == ReviewState.employeeSubmittedAll,
        canEdit: scenario.state == ReviewState.managerRatedAll,
        deadlineRemaining: 5,
      ),
    );
  }

  // ───── Helpers ─────

  ReviewRow _kraRow({
    required String id,
    required String name,
    required String category,
    required double weightagePct,
    required int sortOrder,
    required ScoreSource scoreSource,
    required List<ManagerReviewMonth> months,
    required _ReviewScenario scenario,
    required List<double?> selfRatings,
    required List<double?> managerRatings,
  }) {
    final cells = <MonthlyScore>[];
    for (var i = 0; i < months.length; i++) {
      cells.add(
        MonthlyScore(
          monthlyScoreId: '$id-${months[i].id}',
          monthId: months[i].id,
          monthLabel: months[i].monthLabel,
          monthStatus: months[i].status,
          selfRating: selfRatings[i],
          selfRemark: i == 0 ? 'Met all SLAs this month.' : null,
          managerRating: managerRatings[i],
        ),
      );
    }
    return ReviewRow(
      assignmentItemId: id,
      name: name,
      category: category,
      description: '$name — measured monthly across the quarter.',
      weightage: weightagePct / 100,
      maxScore: 10,
      scoreSource: scoreSource,
      sortOrder: sortOrder,
      monthlyScores: cells,
    );
  }

  _ReviewScenario _scenarioFor(String reviewId) {
    switch (reviewId) {
      case 'rev-vikram-q1':
        return const _ReviewScenario(
          state: ReviewState.employeeSubmittedAll,
          employeeId: 'emp-vikram',
          employeeName: 'Vikram Sinha',
          employeeCode: 'VLPL0210',
          populateSelfTotal: true,
        );
      case 'rev-sagar-q1':
        return const _ReviewScenario(
          state: ReviewState.managerRatedAll,
          employeeId: 'emp-sagar',
          employeeName: 'Sagar Patil',
          employeeCode: 'VLPL0117',
          populateSelfTotal: true,
          populateManagerScores: true,
        );
      case 'rev-neha-q1':
        return const _ReviewScenario(
          state: ReviewState.finalized,
          isLocked: true,
          employeeId: 'emp-neha',
          employeeName: 'Neha Kulkarni',
          employeeCode: 'VLPL0089',
          populateSelfTotal: true,
          populateManagerScores: true,
          lockJune: true,
        );
      case 'rev-pravin-q1':
        return const _ReviewScenario(
          state: ReviewState.inProgress,
          employeeId: 'emp-pravin',
          employeeName: 'Pravin Joshi',
          employeeCode: 'VLPL0003',
          populateSelfTotal: false,
        );
      case 'rev-anita-q1':
        return const _ReviewScenario(
          state: ReviewState.draft,
          employeeId: 'emp-anita',
          employeeName: 'Anita Desai',
          employeeCode: 'VLPL0301',
        );
      default:
        return const _ReviewScenario(
          state: ReviewState.employeeSubmittedAll,
          employeeId: 'emp-unknown',
          employeeName: 'Team Member',
          employeeCode: 'VLPL????',
          populateSelfTotal: true,
        );
    }
  }
}

class _ReviewScenario {
  final ReviewState state;
  final bool isLocked;
  final String employeeId;
  final String employeeName;
  final String employeeCode;
  final bool populateSelfTotal;
  final bool populateManagerScores;
  final bool lockJune;

  const _ReviewScenario({
    required this.state,
    this.isLocked = false,
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    this.populateSelfTotal = false,
    this.populateManagerScores = false,
    this.lockJune = false,
  });
}
