import '../../../auth/data/models/user.dart';
import '../models/monthly_kra_row.dart';
import '../models/monthly_review.dart';
import '../models/monthly_review_summary.dart';
import '../models/review_stage.dart';
import 'monthly_review_repository.dart';

/// In-memory [MonthlyReviewRepository] used until the monthly backend
/// ships. Seeds a small team across two months at various pipeline stages
/// so every dashboard and stage screen is reachable without a network.
///
/// Pass a fixed [now] in tests for deterministic periods.
class MockMonthlyReviewRepository implements MonthlyReviewRepository {
  final Map<String, MonthlyReview> _byId = {};
  final DateTime _now;

  MockMonthlyReviewRepository({DateTime? now}) : _now = now ?? DateTime.now() {
    _seed();
  }

  // ── Seed ──────────────────────────────────────────────────────────────

  ReviewPeriod get _currentPeriod => ReviewPeriod(_now.year, _now.month);

  ReviewPeriod get _previousPeriod {
    final m = _now.month == 1 ? 12 : _now.month - 1;
    final y = _now.month == 1 ? _now.year - 1 : _now.year;
    return ReviewPeriod(y, m);
  }

  void _seed() {
    const manager = (id: 'm1', name: 'Manish Rao');
    final team = <({String id, String name, String code, String grade})>[
      (id: 'emp1', name: 'Asha Iyer', code: 'VIS-1001', grade: 'E1'),
      (id: 'emp2', name: 'Ravi Kumar', code: 'VIS-1002', grade: 'E1'),
      (id: 'emp3', name: 'Neha Shah', code: 'VIS-1003', grade: 'M1'),
    ];

    // Current month — reviews sitting at different stages so each role has
    // something to act on.
    final currentStages = [
      ReviewStage.selfRating, // emp1 — employee self-rates
      ReviewStage.reportingManagerRating, // emp2 — manager rates
      ReviewStage.incentivePayout, // emp3 — finance/HR pays
    ];

    for (var i = 0; i < team.length; i++) {
      final e = team[i];
      final stage = currentStages[i];
      _add(_buildReview(
        id: '${_currentPeriod.key}-${e.id}',
        period: _currentPeriod,
        employee: e,
        manager: manager,
        currentStage: stage,
      ));
      // Previous month — everything finished.
      _add(_buildReview(
        id: '${_previousPeriod.key}-${e.id}',
        period: _previousPeriod,
        employee: e,
        manager: manager,
        currentStage: ReviewStage.completed,
      ));
    }
  }

  void _add(MonthlyReview r) => _byId[r.id] = r;

  /// Builds a review whose stages BEFORE [currentStage] are marked done
  /// (with seeded scores for rating stages), so the pipeline looks
  /// realistic.
  MonthlyReview _buildReview({
    required String id,
    required ReviewPeriod period,
    required ({String id, String name, String code, String grade}) employee,
    required ({String id, String name}) manager,
    required ReviewStage currentStage,
  }) {
    final rows = _seedRows();
    final records = <ReviewStage, StageRecord>{};

    // For every stage strictly before currentStage: mark done and, for
    // rating stages, fill in seeded scores.
    for (final stage in ReviewStage.values) {
      if (stage.isTerminal) continue;
      final done = stage.pipelineIndex < currentStage.pipelineIndex;
      if (done) {
        records[stage] = StageRecord(
          status: StageStatus.done,
          actorId: stage == ReviewStage.selfRating ? employee.id : 'system',
          actorName: stage.label,
          actedAt: period.dateOn(stage.deadlineDay ?? 1),
        );
        if (stage.isRatingStage) {
          for (var r = 0; r < rows.length; r++) {
            // Slightly different score per stage so the matrix isn't flat.
            final base = 7.0 + ((r + stage.pipelineIndex) % 3);
            rows[r] = rows[r].withStageScore(
              stage,
              RowScore(value: base, remark: null),
            );
          }
        }
      } else if (stage == currentStage) {
        records[stage] = const StageRecord(status: StageStatus.pending);
      }
    }

    final payout = currentStage == ReviewStage.completed
        ? PayoutStatus.paid
        : currentStage == ReviewStage.incentivePayout
            ? PayoutStatus.ready
            : PayoutStatus.notReady;

    return MonthlyReview(
      id: id,
      employeeId: employee.id,
      employeeName: employee.name,
      employeeCode: employee.code,
      grade: employee.grade,
      managerId: manager.id,
      managerName: manager.name,
      period: period,
      currentStage: currentStage,
      stageRecords: records,
      rows: rows,
      eligibleAmount: 5000,
      payoutStatus: payout,
      paidAt: currentStage == ReviewStage.completed ? period.dateOn(20) : null,
    );
  }

  List<MonthlyKraRow> _seedRows() => [
        const MonthlyKraRow(
          id: 'k1',
          name: 'Revenue target',
          category: 'Sales',
          weightagePercent: 40,
          maxScore: 10,
          displayOrder: 0,
          target: '₹5L',
          trackingMethod: 'CRM',
        ),
        const MonthlyKraRow(
          id: 'k2',
          name: 'Customer satisfaction',
          category: 'Quality',
          weightagePercent: 35,
          maxScore: 10,
          displayOrder: 1,
        ),
        const MonthlyKraRow(
          id: 'k3',
          name: 'Process adherence',
          category: 'Ops',
          weightagePercent: 25,
          maxScore: 10,
          displayOrder: 2,
        ),
      ];

  // ── Reads ─────────────────────────────────────────────────────────────

  @override
  Future<List<ReviewPeriod>> availablePeriods() async {
    final seen = <String, ReviewPeriod>{};
    for (final r in _byId.values) {
      seen[r.period.key] = r.period;
    }
    final list = seen.values.toList()
      ..sort((a, b) => b.key.compareTo(a.key)); // newest first
    return list;
  }

  @override
  Future<List<MonthlyReviewSummary>> listForMonth({
    required ReviewPeriod period,
    required ReviewScope scope,
  }) async {
    final inMonth = _byId.values.where((r) => r.period == period).toList();
    final visible = inMonth.where((r) => _visibleTo(r, scope)).toList()
      ..sort((a, b) => a.employeeName.compareTo(b.employeeName));
    return visible.map(MonthlyReviewSummary.fromReview).toList();
  }

  bool _visibleTo(MonthlyReview r, ReviewScope scope) {
    switch (scope.role) {
      case UserRole.employee:
      case UserRole.ops:
        return r.employeeId == scope.userId;
      case UserRole.manager:
      case UserRole.bdManager:
      case UserRole.warehouseMgr:
        return r.managerId == scope.userId;
      case UserRole.hr:
      case UserRole.finance:
      case UserRole.hrAdmin:
      case UserRole.admin:
        return true; // org-wide
    }
  }

  @override
  Future<MonthlyReview> getReview(String reviewId) async {
    final r = _byId[reviewId];
    if (r == null) {
      throw StateError('Review $reviewId not found');
    }
    return r;
  }

  // ── Writes (state machine) ────────────────────────────────────────────

  @override
  Future<MonthlyReview> submitStage({
    required String reviewId,
    required ReviewStage stage,
    required ReviewScope actor,
    Map<String, RowScore>? rowScores,
    StageDecision? decision,
    String? comment,
  }) async {
    final review = await getReview(reviewId);
    if (review.currentStage != stage) {
      throw StateError(
        'Review is at ${review.currentStage.label}, not ${stage.label}',
      );
    }

    // Apply rating-stage scores onto the rows.
    var rows = review.rows;
    if (stage.isRatingStage && rowScores != null) {
      rows = [
        for (final row in rows)
          rowScores.containsKey(row.id)
              ? row.withStageScore(stage, rowScores[row.id])
              : row,
      ];
    }

    // Management review can send the review back a step instead of advancing.
    final returning = stage == ReviewStage.managementReview &&
        decision == StageDecision.returnForRework;

    final records = Map<ReviewStage, StageRecord>.from(review.stageRecords);
    records[stage] = StageRecord(
      status: returning ? StageStatus.skipped : StageStatus.done,
      actorId: actor.userId,
      actorName: actor.role.displayName,
      actedAt: _now,
      comment: comment,
    );

    final nextStage =
        returning ? ReviewStage.reportingManagerRating : stage.next;
    if (returning) {
      records[ReviewStage.reportingManagerRating] =
          const StageRecord(status: StageStatus.pending);
    } else {
      records[nextStage] = StageRecord(
        status: nextStage.isTerminal ? StageStatus.done : StageStatus.pending,
      );
    }

    final updated = review.copyWith(
      rows: rows,
      currentStage: nextStage,
      stageRecords: records,
      payoutStatus: nextStage == ReviewStage.incentivePayout
          ? PayoutStatus.ready
          : review.payoutStatus,
    );
    _byId[reviewId] = updated;
    return updated;
  }

  @override
  Future<MonthlyReview> markPaid({
    required String reviewId,
    required ReviewScope actor,
  }) async {
    final review = await getReview(reviewId);
    if (review.currentStage != ReviewStage.incentivePayout) {
      throw StateError('Review is not awaiting payout');
    }
    final records = Map<ReviewStage, StageRecord>.from(review.stageRecords);
    records[ReviewStage.incentivePayout] = StageRecord(
      status: StageStatus.done,
      actorId: actor.userId,
      actorName: actor.role.displayName,
      actedAt: _now,
    );
    final updated = review.copyWith(
      currentStage: ReviewStage.completed,
      stageRecords: records,
      payoutStatus: PayoutStatus.paid,
      paidAt: _now,
    );
    _byId[reviewId] = updated;
    return updated;
  }
}
