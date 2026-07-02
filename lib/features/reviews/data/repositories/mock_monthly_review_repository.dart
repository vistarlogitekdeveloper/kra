import '../../../auth/data/models/user.dart';
import '../models/incentive_snapshot.dart';
import '../models/monthly_kra_row.dart';
import '../models/monthly_review.dart';
import '../models/monthly_review_summary.dart';
import '../models/review_stage.dart';
import '../models/row_score.dart';
import '../models/stage_record.dart';
import 'monthly_review_repository.dart';

/// In-memory [MonthlyReviewRepository] used until the monthly backend
/// ships. Seeds a small team across two months at various pipeline stages
/// so every dashboard and stage screen is reachable without a network.
///
/// Pass a fixed [now] in tests for deterministic periods.
class MockMonthlyReviewRepository implements MonthlyReviewRepository {
  final Map<String, MonthlyReview> _byId = {};
  final DateTime _now;

  /// Seeded demo manager id — the presentation layer maps any real
  /// manager login onto this so the demo team is visible.
  static const String demoManagerId = 'm1';

  /// Seeded demo employee id — any real employee login maps here.
  static const String demoEmployeeId = 'emp1';

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
    const manager = (id: demoManagerId, name: 'Manish Rao');
    final team = <({String id, String name, String code, String grade})>[
      (id: 'emp1', name: 'Asha Iyer', code: 'VIS-1001', grade: 'E1'),
      (id: 'emp2', name: 'Ravi Kumar', code: 'VIS-1002', grade: 'E1'),
      (id: 'emp3', name: 'Neha Shah', code: 'VIS-1003', grade: 'M1'),
    ];

    // Current month — reviews at different stages so each role has
    // something to act on.
    final currentStages = [
      ReviewStage.selfRating, // emp1 — employee self-rates
      ReviewStage.reportingManagerRating, // emp2 — manager rates
      ReviewStage.incentivePayout, // emp3 — finance/HR pays
    ];

    for (var i = 0; i < team.length; i++) {
      final e = team[i];
      _add(_buildReview(
        id: '${_currentPeriod.key}-${e.id}',
        period: _currentPeriod,
        employee: e,
        manager: manager,
        currentStage: currentStages[i],
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

  /// Builds a review whose stages BEFORE [currentStage] are recorded as
  /// submitted (with seeded scores for rating stages) so the pipeline
  /// looks realistic.
  MonthlyReview _buildReview({
    required String id,
    required ReviewPeriod period,
    required ({String id, String name, String code, String grade}) employee,
    required ({String id, String name}) manager,
    required ReviewStage currentStage,
  }) {
    var rows = _seedRows();
    final records = <ReviewStage, StageRecord>{};

    for (final stage in ReviewStage.values) {
      if (stage.isTerminal) continue;
      final done = stage.pipelineIndex < currentStage.pipelineIndex;
      if (!done) continue;
      records[stage] = StageRecord(
        actorId: stage == ReviewStage.selfRating ? employee.id : manager.id,
        actorName: stage == ReviewStage.selfRating ? employee.name : 'System',
        submittedAt: period.dateOn(stage.deadlineDay ?? 1),
      );
      if (stage.isRatingStage) {
        rows = [
          for (var r = 0; r < rows.length; r++)
            rows[r].withStageScore(
              stage,
              // A little variation per stage/row so the matrix isn't flat.
              RowScore(value: 7.0 + ((r + stage.pipelineIndex) % 3)),
            ),
        ];
      }
    }

    final isPaid = currentStage == ReviewStage.completed;
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
      incentive: IncentiveSnapshot(
        eligibleAmount: 5000,
        payoutStatus: isPaid ? PayoutStatus.paid : PayoutStatus.pending,
        paidAt: isPaid ? period.dateOn(20) : null,
      ),
    );
  }

  List<MonthlyKraRow> _seedRows() => const [
        MonthlyKraRow(
          id: 'k1',
          name: 'Revenue target',
          category: 'Sales',
          weightagePercent: 40,
          maxScore: 10,
          displayOrder: 0,
          target: '₹5L',
          trackingMethod: 'CRM',
        ),
        MonthlyKraRow(
          id: 'k2',
          name: 'Customer satisfaction',
          category: 'Quality',
          weightagePercent: 35,
          maxScore: 10,
          displayOrder: 1,
        ),
        MonthlyKraRow(
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
  Future<List<MonthlyReviewSummary>> listMonthlyReviews({
    required int year,
    required int month,
    bool mine = false,
    UserRole? scopeRole,
    String? scopeEmployeeId,
    String? scopeManagerId,
    ReviewStage? currentStage,
  }) async {
    final visible = _byId.values.where((r) {
      if (r.period.year != year || r.period.month != month) return false;
      if (scopeEmployeeId != null && r.employeeId != scopeEmployeeId) {
        return false;
      }
      if (scopeManagerId != null && r.managerId != scopeManagerId) return false;
      if (currentStage != null && r.currentStage != currentStage) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.employeeName.compareTo(b.employeeName));
    return visible.map(MonthlyReviewSummary.fromReview).toList();
  }

  @override
  Future<MonthlyReview> getReview(String id) async {
    final r = _byId[id];
    if (r == null) throw StateError('Review $id not found');
    return r;
  }

  // ── Writes (state machine) ────────────────────────────────────────────

  @override
  Future<MonthlyReview> submitStage(
    String reviewId,
    ReviewStage stage, {
    Map<String, RowScore>? rowScores,
    bool? approved,
    String? comment,
    required String actorId,
    required String actorName,
  }) async {
    final review = await getReview(reviewId);
    if (review.currentStage != stage) {
      throw StateError(
        'Review is at ${review.currentStage.label}, not ${stage.label}',
      );
    }
    // The payout stage is settled via markPaid (it flips payout status).
    // submitStage would advance to completed leaving payout still pending.
    if (stage == ReviewStage.incentivePayout || stage.isTerminal) {
      throw StateError('Use markPaid to settle ${stage.label}');
    }

    // Apply rating-stage scores onto the rows.
    var rows = review.rows;
    if (stage.isRatingStage && rowScores != null) {
      rows = [
        for (final row in rows)
          rowScores.containsKey(row.id)
              ? row.withStageScore(stage, rowScores[row.id]!)
              : row,
      ];
    }

    final records = Map<ReviewStage, StageRecord>.from(review.stageRecords);

    // Management review can send the review back a step instead of
    // advancing — clear the reporting-manager record so it re-opens.
    final returning = stage == ReviewStage.managementReview && approved == false;
    if (returning) {
      records.remove(ReviewStage.reportingManagerRating);
      // Keep WHY it was returned (the comment is mandatory in the UI) so the
      // reporting manager can see it. Cleared again when they resubmit below.
      records[ReviewStage.managementReview] = StageRecord(
        actorId: actorId,
        actorName: actorName,
        submittedAt: _now,
        comment: comment,
      );
      final updated = review.copyWith(
        rows: rows,
        currentStage: ReviewStage.reportingManagerRating,
        stageRecords: records,
      );
      _byId[reviewId] = updated;
      return updated;
    }

    // Manager resubmitting after a return: drop the stale return note so the
    // management stage reads as in-progress (and re-badges) on its next pass.
    if (stage == ReviewStage.reportingManagerRating) {
      records.remove(ReviewStage.managementReview);
    }

    records[stage] = StageRecord(
      actorId: actorId,
      actorName: actorName,
      submittedAt: _now,
      comment: comment,
    );
    final updated = review.copyWith(
      rows: rows,
      currentStage: stage.next,
      stageRecords: records,
    );
    _byId[reviewId] = updated;
    return updated;
  }

  @override
  Future<MonthlyReview> markPaid(
    String reviewId, {
    required String actorId,
    required String actorName,
  }) async {
    final review = await getReview(reviewId);
    if (review.currentStage != ReviewStage.incentivePayout) {
      throw StateError('Review is not awaiting payout');
    }
    final records = Map<ReviewStage, StageRecord>.from(review.stageRecords);
    records[ReviewStage.incentivePayout] = StageRecord(
      actorId: actorId,
      actorName: actorName,
      submittedAt: _now,
    );
    final updated = review.copyWith(
      currentStage: ReviewStage.completed,
      stageRecords: records,
      incentive: review.incentive.copyWith(
        payoutStatus: PayoutStatus.paid,
        paidAt: _now,
      ),
    );
    _byId[reviewId] = updated;
    return updated;
  }

  @override
  Future<MonthlyReview> saveStageScores(
    String reviewId,
    ReviewStage stage, {
    required Map<String, RowScore> rowScores,
  }) async {
    final review = await getReview(reviewId);
    final rows = [
      for (final row in review.rows)
        rowScores.containsKey(row.id)
            ? row.withStageScore(stage, rowScores[row.id]!)
            : row,
    ];
    final updated = review.copyWith(rows: rows);
    _byId[reviewId] = updated;
    return updated;
  }
}
