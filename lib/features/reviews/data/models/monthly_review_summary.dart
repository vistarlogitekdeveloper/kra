import '../../../../core/api/json_parse.dart';
import '../../../auth/data/models/user.dart';
import 'incentive_snapshot.dart';
import 'monthly_review.dart';
import 'review_stage.dart';
import 'stage_status.dart';

/// Lightweight list-row projection of a [MonthlyReview].
///
/// Dashboards fetch a list of these (cheap; no rows / no records) and
/// hydrate the full review lazily when a row is tapped. Whether the
/// current stage needs the caller's action is role-dependent, so it's
/// computed per-caller via [needsActionBy] rather than baked in.
class MonthlyReviewSummary {
  final String id;
  final String employeeId;
  final String employeeName;
  final String employeeCode;
  final String? employeeGrade;

  /// The employee's reporting manager. [managerId] is what decides whether the
  /// caller may rate this review (a relationship, not a role) — see
  /// [needsActionBy]. Null when nobody is mapped as their manager.
  final String? managerId;
  final String? managerName;

  final int year;
  final int month;
  final String monthLabel;

  final ReviewStage currentStage;
  final StageStatus currentStageStatus;

  /// Agreed weighted score so far (0–100) — shown on the tile.
  final double finalScorePct;

  /// The employee's configured monthly-incentive ceiling.
  final double? incentiveEligibleAmount;

  /// Incentive payout lifecycle — PAID once Accounts/Finance has settled it.
  final PayoutStatus payoutStatus;

  /// The employee's project location (e.g. "Adept, Pune") — shown on the
  /// review dashboard to mirror the performance-incentive report. Null when the
  /// employee has no location mapped.
  final String? projectLocation;

  /// The self-rating weighted % for this month (0–100), or null when the
  /// employee hasn't self-rated. Feeds the performance-incentive report.
  final double? selfScorePct;

  /// The management/review weighted % for this month (0–100) — the management
  /// override if present, else the RM/HR/Accounts review average. Null until
  /// the review has been rated. Feeds the performance-incentive report.
  final double? managementReviewPct;

  const MonthlyReviewSummary({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    this.employeeGrade,
    this.managerId,
    this.managerName,
    required this.year,
    required this.month,
    required this.monthLabel,
    required this.currentStage,
    required this.currentStageStatus,
    this.finalScorePct = 0,
    this.incentiveEligibleAmount,
    this.payoutStatus = PayoutStatus.pending,
    this.projectLocation,
    this.selfScorePct,
    this.managementReviewPct,
  });

  /// Wire form from the monthly-review backend's list endpoint.
  ///
  /// The backend sends both the formal pipeline cursor (`currentStage`) and
  /// scores-derived progress (`displayStage`/`displayStageStatus` — the
  /// furthest rating stage that actually carries scores, since in-place
  /// `save-scores` never advances the cursor). The tile should show real
  /// progress, so prefer the display fields and fall back to the cursor for
  /// older backends that don't send them.
  factory MonthlyReviewSummary.fromJson(Map<String, dynamic> json) =>
      MonthlyReviewSummary(
        id: JsonParse.parseString(json['id']) ?? '',
        employeeId: JsonParse.parseString(json['employeeId']) ?? '',
        employeeName: JsonParse.parseString(json['employeeName']) ?? '',
        employeeCode: JsonParse.parseString(json['employeeCode']) ?? '',
        employeeGrade: JsonParse.parseString(json['employeeGrade']),
        managerId: JsonParse.parseString(json['managerId']),
        managerName: JsonParse.parseString(json['managerName']),
        year: JsonParse.parseInt(json['year']) ?? 0,
        month: JsonParse.parseInt(json['month']) ?? 1,
        monthLabel: JsonParse.parseString(json['monthLabel']) ?? '',
        currentStage: ReviewStage.fromApi(
            JsonParse.parseString(json['displayStage']) ??
                JsonParse.parseString(json['currentStage'])),
        currentStageStatus: StageStatus.fromApi(
            JsonParse.parseString(json['displayStageStatus']) ??
                JsonParse.parseString(json['currentStageStatus'])),
        finalScorePct: JsonParse.parseDouble(json['finalScorePct']) ?? 0,
        incentiveEligibleAmount:
            JsonParse.parseDouble(json['incentiveEligibleAmount']),
        payoutStatus:
            PayoutStatus.fromApi(JsonParse.parseString(json['payoutStatus'])),
        projectLocation: JsonParse.parseString(json['projectLocation']),
        selfScorePct: JsonParse.parseDouble(json['selfScorePct']),
        managementReviewPct: JsonParse.parseDouble(json['managementReviewPct']),
      );

  /// Projection from a full review — used by the mock and any backend
  /// summary endpoint that returns whole reviews.
  factory MonthlyReviewSummary.fromReview(MonthlyReview r) =>
      MonthlyReviewSummary(
        id: r.id,
        employeeId: r.employeeId,
        employeeName: r.employeeName,
        employeeCode: r.employeeCode,
        employeeGrade: r.grade,
        managerId: r.managerId,
        managerName: r.managerName,
        year: r.period.year,
        month: r.period.month,
        monthLabel: r.period.label,
        // Derived from actual scores, not the frozen pipeline cursor —
        // in-place `save-scores` never advances `currentStage`.
        currentStage: r.displayStage,
        currentStageStatus: r.displayStatus,
        finalScorePct: r.finalScorePct,
        incentiveEligibleAmount: r.eligibleAmount,
        payoutStatus: r.payoutStatus,
        selfScorePct: r.weightedScorePct(ReviewStage.selfRating),
        managementReviewPct:
            r.weightedScorePct(ReviewStage.managementReview) > 0
                ? r.weightedScorePct(ReviewStage.managementReview)
                : r.reviewWeightedPct,
      );

  /// True when the employee's self-rating for this month has actually been
  /// filled in.
  ///
  /// [currentStage] here is the backend's `displayStage` — derived from the
  /// scores that really exist, not the pipeline cursor (in-place `save-scores`
  /// never advances that cursor). So self-rating counts as done when the review
  /// has moved past it, or it IS the display stage and carries scores.
  ///
  /// The home dashboard needs this because its card/banner state comes from the
  /// LEGACY `kra.reviews` table, which a monthly self-rating never updates.
  bool get selfRatingSubmitted {
    if (currentStage.isTerminal) return true;
    if (currentStage == ReviewStage.selfRating) {
      return currentStageStatus == StageStatus.submitted;
    }
    return currentStage.index > ReviewStage.selfRating.index;
  }

  /// True when the caller can act on the current stage — i.e. their dashboard
  /// should badge this row as "needs my action".
  ///
  /// The rating stages that involve a person are relationships, not roles, so
  /// [userId] resolves them against this row: self-rating belongs to
  /// [employeeId], reporting-manager rating to [managerId] — whatever either
  /// party's role happens to be. Org-level stages stay role-gated.
  bool needsActionBy(UserRole role, {String? userId}) =>
      needsActionByAny({role}, userId: userId);

  /// Multi-role form of [needsActionBy]: true when ANY of [roles] is asked to
  /// act. The relationship stages are unaffected — they answer to
  /// [employeeId] / [managerId], never to a role — so only the org-level tail
  /// consults the set.
  bool needsActionByAny(Set<UserRole> roles, {String? userId}) {
    if (currentStage.isTerminal) return false;
    if (currentStageStatus == StageStatus.submitted) return false;
    if (currentStage == ReviewStage.selfRating) {
      return userId != null && userId == employeeId;
    }
    if (currentStage == ReviewStage.reportingManagerRating) {
      return userId != null && managerId != null && userId == managerId;
    }
    return currentStage.isActionableByAny(roles);
  }

  /// The FIXED incentive for the whole quarter — the monthly eligible ceiling
  /// × 3 months. The maximum the employee could earn across the quarter,
  /// independent of performance.
  double get quarterlyFixedIncentive => (incentiveEligibleAmount ?? 0) * 3;

  /// The incentive actually PAYABLE for this month's review — the monthly
  /// eligible ceiling scaled by the achieved score. What the employee earns
  /// this month before the quarterly settlement.
  double get payableIncentive =>
      (incentiveEligibleAmount ?? 0) * finalScorePct / 100;

  /// The incentive has been settled.
  bool get payoutPaid => payoutStatus == PayoutStatus.paid;

  /// True when this review carries a score ANYWHERE — the only honest evidence
  /// that somebody actually rated it.
  ///
  /// Note what is NOT evidence: [payoutPaid]. A payout flag is bookkeeping, not
  /// a rating, and treating it as proof of work is what let a review with an
  /// entirely empty sheet render as "Completed · Paid · 0%".
  ///
  /// A genuine zero is distinguishable from never-rated: an employee who scored
  /// 0 has `selfScorePct == 0`, which is non-null, so this still reports true
  /// for them.
  bool get hasAnyScore =>
      finalScorePct > 0 || selfScorePct != null || managementReviewPct != null;

  /// The payout flag CORROBORATED by an actual score.
  ///
  /// What a "Paid" badge should be driven by: claiming an incentive was settled
  /// for a review nobody ever rated is worse than showing nothing, because it
  /// reads as money already out of the door. [payoutPaid] itself is left alone —
  /// the incentive maths and the quarterly report depend on the raw flag.
  bool get payoutSettled => payoutPaid && hasAnyScore;

  /// The furthest rating stage the summary's SCORES prove was reached, or null
  /// when nothing beyond Self-Rating has a score yet. Read off the score fields
  /// the list endpoint carries, so it survives a stage cursor that in-place
  /// score saves left frozen (the backend advances [currentStage] on a formal
  /// stage submit, not on an edit-in-place `save-scores`).
  ///
  /// `managementReviewPct` is non-null once the Review/Management cycle has any
  /// score, so it maps to Management Review — the phase a completed Review sits
  /// at. (The summary can't tell a management override from a Review average, so
  /// this can read one notch ahead for a still-in-progress Review; that only
  /// ever applies when the cursor is frozen, and never regresses a live cursor.)
  ReviewStage? get _scoredStage {
    // A settled payout implies the pipeline ran to the end — but only when a
    // score corroborates it. Reading `payoutPaid` alone contradicted this
    // getter's own contract ("what the SCORES prove"), so a stale payout flag on
    // an unrated review promoted it all the way to Completed.
    if (payoutPaid && hasAnyScore) return ReviewStage.completed;
    if (managementReviewPct != null) return ReviewStage.managementReview;
    if (selfScorePct != null) return ReviewStage.selfRating;
    return null;
  }

  /// Stage to SHOW on dashboards. Trusts the backend's stage cursor once it has
  /// advanced past Self-Rating (it's authoritative then), and only repairs the
  /// specific frozen-at-Self-Rating case: a review whose scores prove more work
  /// was done still reads as Self-Rating because the cursor never moved. This
  /// mirrors the quarterly KRA sheet, which derives the same stage from the full
  /// review's scores.
  ReviewStage get displayStage {
    if (currentStage != ReviewStage.selfRating) return currentStage;
    final scored = _scoredStage;
    if (scored == null) return currentStage;
    return scored.pipelineIndex >= currentStage.pipelineIndex
        ? scored
        : currentStage;
  }

  /// Status of [displayStage]: submitted once the review is terminal/paid or the
  /// scores prove the shown stage was reached; otherwise the cursor's own status
  /// (nothing scored yet → still in progress / pending).
  StageStatus get displayStatus {
    if (currentStage.isTerminal || (payoutPaid && hasAnyScore)) {
      return StageStatus.submitted;
    }
    if (currentStage != ReviewStage.selfRating) return currentStageStatus;
    return _scoredStage == null ? currentStageStatus : StageStatus.submitted;
  }

  /// True when this month's review carries real rating ACTIVITY — a score
  /// exists somewhere, or the pipeline has moved past Self-Rating. A freshly
  /// generated month (the row exists, nobody has rated yet) is false.
  ///
  /// This is what tells "this month hasn't started" apart from "this month is
  /// at Self-Rating with the self-rating already in" — a distinction the stage
  /// chip alone can't express, since both read "Self-Rating".
  /// Reads the cursor and the scores DIRECTLY rather than going through
  /// [displayStatus]: that getter reports "submitted" for a paid review, and
  /// since a payout flag is not a rating, routing through it made an unrated
  /// review look like real activity — circular, and wrong in exactly the case
  /// this is meant to detect.
  bool get hasRatingActivity =>
      hasAnyScore ||
      currentStage != ReviewStage.selfRating ||
      currentStageStatus == StageStatus.submitted;

  /// True when a month's [summaries] are worth LANDING on: somebody has rated
  /// something, or a row still awaits this caller's own action.
  ///
  /// The "needs my action" half matters as much as the activity half. An
  /// employee whose current month is untouched still owes a self-rating there,
  /// so the dashboard must never skip past it to an older, busier month and
  /// hide the one thing they have to do.
  static bool anyWorthLanding(
    Iterable<MonthlyReviewSummary> summaries, {
    Set<UserRole> roles = const {},
    String? userId,
  }) =>
      summaries.any((s) =>
          s.hasRatingActivity || s.needsActionByAny(roles, userId: userId));

  /// The management review has been done (management scored, or the review has
  /// already moved on to payout / completed) — so the incentive can be settled.
  bool get managementReviewDone {
    if (currentStage == ReviewStage.incentivePayout ||
        currentStage == ReviewStage.completed) {
      return true;
    }
    return currentStage == ReviewStage.managementReview &&
        currentStageStatus == StageStatus.submitted;
  }

  /// Whether [role] may settle the incentive for THIS review right now — the
  /// management review is done, it isn't already paid, and the role is a payout
  /// actor (Accounts / HR / HR-admin). Drives the dashboard's "mark paid" check.
  bool canMarkPaidBy(UserRole role) =>
      managementReviewDone &&
      !payoutPaid &&
      ReviewStage.incentivePayout.actorRoles.contains(role);
}
