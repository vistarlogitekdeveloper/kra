import '../../../auth/data/models/user.dart';
import '../models/incentive_snapshot.dart';
import '../models/monthly_kra_row.dart';
import '../models/monthly_review.dart';
import '../models/monthly_review_summary.dart';
import '../models/review_stage.dart';
import '../models/row_score.dart';
import '../models/stage_record.dart';
import 'monthly_review_repository.dart';

/// One real employee, reduced to what a monthly review needs. The
/// provider builds these from the live backend (HR → /employees,
/// manager → /manager/team, employee → self).
class RosterEntry {
  final String id;
  final String name;
  final String code;
  final String? grade;
  final String? managerId;
  final String? managerName;

  /// The employee's configured monthly incentive ceiling.
  final double eligibleAmount;

  const RosterEntry({
    required this.id,
    required this.name,
    this.code = '',
    this.grade,
    this.managerId,
    this.managerName,
    this.eligibleAmount = 0,
  });
}

/// A [MonthlyReviewRepository] whose **roster comes from the live
/// backend** (via [loadRoster]) instead of hardcoded demo people.
///
/// There is no monthly-review backend yet, so the *pipeline state* still
/// lives in memory: reviews are materialised at [ReviewStage.selfRating]
/// for each real employee on first view, and stage submissions persist
/// for the session. Once a monthly backend ships, this whole class is
/// replaced by a straight API implementation.
class LiveMonthlyReviewRepository implements MonthlyReviewRepository {
  /// Fetches the role-appropriate set of real employees. Called lazily
  /// the first time a given month is viewed.
  final Future<List<RosterEntry>> Function() loadRoster;

  /// Injectable clock so `submitStage`/`markPaid` timestamps are
  /// deterministic in tests.
  final DateTime Function() _clock;

  final Map<String, MonthlyReview> _store = {};
  final Set<String> _materialised = {};

  LiveMonthlyReviewRepository({
    required this.loadRoster,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  // ── Materialisation ────────────────────────────────────────────────────

  Future<void> _ensure(ReviewPeriod period) async {
    final roster = await loadRoster();
    for (final e in roster) {
      final id = '${period.key}-${e.id}';
      // putIfAbsent so a review that's already advanced this session isn't
      // reset back to Self-Rating on the next refresh.
      _store.putIfAbsent(id, () => _build(id, period, e));
    }
    _materialised.add(period.key);
  }

  MonthlyReview _build(String id, ReviewPeriod period, RosterEntry e) =>
      MonthlyReview(
        id: id,
        employeeId: e.id,
        employeeName: e.name,
        employeeCode: e.code,
        grade: e.grade,
        managerId: e.managerId,
        managerName: e.managerName,
        period: period,
        currentStage: ReviewStage.selfRating,
        rows: _templateRows(),
        incentive: IncentiveSnapshot(eligibleAmount: e.eligibleAmount),
      );

  /// Default KRA template applied to a freshly generated review. These
  /// are the *KRA structure*, not employee data — a real backend would
  /// snapshot them from the employee's assigned template.
  List<MonthlyKraRow> _templateRows() => const [
        MonthlyKraRow(
          id: 'kra-delivery',
          name: 'Delivery & targets',
          category: 'Output',
          weightagePercent: 40,
          maxScore: 10,
          displayOrder: 0,
        ),
        MonthlyKraRow(
          id: 'kra-quality',
          name: 'Quality of work',
          category: 'Quality',
          weightagePercent: 35,
          maxScore: 10,
          displayOrder: 1,
        ),
        MonthlyKraRow(
          id: 'kra-conduct',
          name: 'Conduct & adherence',
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
    UserRole? scopeRole,
    String? scopeEmployeeId,
    String? scopeManagerId,
    ReviewStage? currentStage,
  }) async {
    final period = ReviewPeriod(year, month);
    await _ensure(period);
    final list = _store.values.where((r) {
      if (r.period != period) return false;
      // The roster is already role-scoped by [loadRoster]; these extra
      // filters just support the payout/stage-specific dashboards.
      if (scopeEmployeeId != null && r.employeeId != scopeEmployeeId) {
        return false;
      }
      if (scopeManagerId != null && r.managerId != scopeManagerId) return false;
      if (currentStage != null && r.currentStage != currentStage) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.employeeName.compareTo(b.employeeName));
    return list.map(MonthlyReviewSummary.fromReview).toList();
  }

  @override
  Future<MonthlyReview> getReview(String id) async {
    final r = _store[id];
    if (r == null) throw StateError('Review $id not found');
    return r;
  }

  // ── Writes (state machine — mirrors the mock) ──────────────────────────

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

    final returning = stage == ReviewStage.managementReview && approved == false;
    if (returning) {
      records.remove(ReviewStage.reportingManagerRating);
      final updated = review.copyWith(
        rows: rows,
        currentStage: ReviewStage.reportingManagerRating,
        stageRecords: records,
      );
      _store[reviewId] = updated;
      return updated;
    }

    records[stage] = StageRecord(
      actorId: actorId,
      actorName: actorName,
      submittedAt: _clock(),
      comment: comment,
    );
    final updated = review.copyWith(
      rows: rows,
      currentStage: stage.next,
      stageRecords: records,
    );
    _store[reviewId] = updated;
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
      submittedAt: _clock(),
    );
    final updated = review.copyWith(
      currentStage: ReviewStage.completed,
      stageRecords: records,
      incentive: review.incentive.copyWith(
        payoutStatus: PayoutStatus.paid,
        paidAt: _clock(),
      ),
    );
    _store[reviewId] = updated;
    return updated;
  }
}
