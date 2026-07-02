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

  /// The employee's real assigned KRA rows. Empty → the repo falls back
  /// to a generic template.
  final List<MonthlyKraRow> rows;

  const RosterEntry({
    required this.id,
    required this.name,
    this.code = '',
    this.grade,
    this.managerId,
    this.managerName,
    this.eligibleAmount = 0,
    this.rows = const [],
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

  /// Materialises [period] for the caller's roster and returns that roster
  /// so reads can be scoped to it. The [_store] is process-wide and outlives
  /// logout, so a prior (e.g. HR org-wide) session can leave other people's
  /// reviews in it — reads MUST intersect with the current roster or a later
  /// employee/manager login would see everyone. See [listMonthlyReviews].
  Future<List<RosterEntry>> _ensure(ReviewPeriod period) async {
    final roster = await loadRoster();
    for (final e in roster) {
      final id = '${period.key}-${e.id}';
      // putIfAbsent so a review that's already advanced this session isn't
      // reset back to Self-Rating on the next refresh.
      _store.putIfAbsent(id, () => _build(id, period, e));
    }
    _materialised.add(period.key);
    return roster;
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
        // Real assigned KRAs when available; a generic template otherwise.
        rows: e.rows.isNotEmpty ? e.rows : _templateRows(),
        incentive: IncentiveSnapshot(eligibleAmount: e.eligibleAmount),
      );

  /// Fallback KRA template applied when an employee has no assigned KRAs
  /// yet. A real backend would snapshot the employee's assigned template.
  List<MonthlyKraRow> _templateRows() => const [
        MonthlyKraRow(
          id: 'kra-delivery',
          name: 'Delivery & targets',
          category: 'Output',
          weightagePercent: 40,
          maxScore: MonthlyKraRow.defaultMaxScore,
          displayOrder: 0,
        ),
        MonthlyKraRow(
          id: 'kra-quality',
          name: 'Quality of work',
          category: 'Quality',
          weightagePercent: 35,
          maxScore: MonthlyKraRow.defaultMaxScore,
          displayOrder: 1,
        ),
        MonthlyKraRow(
          id: 'kra-conduct',
          name: 'Conduct & adherence',
          category: 'Ops',
          weightagePercent: 25,
          maxScore: MonthlyKraRow.defaultMaxScore,
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
    // [mine] is a live-backend scope hint; this in-memory repo already builds
    // a role-scoped roster in [_ensure], so there's nothing extra to filter.
    final period = ReviewPeriod(year, month);
    final roster = await _ensure(period);
    // Scope to THIS caller's roster ids — never the whole store, which may
    // hold reviews materialised for a different user earlier this session.
    final allowedIds = roster.map((e) => e.id).toSet();
    final list = _store.values.where((r) {
      if (r.period != period) return false;
      if (!allowedIds.contains(r.employeeId)) return false;
      // Extra filters support the payout / stage-specific dashboards.
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
    // The payout stage is settled via markPaid (it flips payout status).
    // submitStage would advance to completed leaving payout still pending.
    if (stage == ReviewStage.incentivePayout || stage.isTerminal) {
      throw StateError('Use markPaid to settle ${stage.label}');
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
      // Keep WHY it was returned (the comment is mandatory in the UI) so the
      // reporting manager can see it. Cleared again when they resubmit below.
      records[ReviewStage.managementReview] = StageRecord(
        actorId: actorId,
        actorName: actorName,
        submittedAt: _clock(),
        comment: comment,
      );
      final updated = review.copyWith(
        rows: rows,
        currentStage: ReviewStage.reportingManagerRating,
        stageRecords: records,
      );
      _store[reviewId] = updated;
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
    _store[reviewId] = updated;
    return updated;
  }
}
