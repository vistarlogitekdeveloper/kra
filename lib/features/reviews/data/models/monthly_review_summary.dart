import '../../../../core/api/json_parse.dart';
import '../../../auth/data/models/user.dart';
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
      );

  /// True when the caller can act on the current stage — i.e. their dashboard
  /// should badge this row as "needs my action".
  ///
  /// The rating stages that involve a person are relationships, not roles, so
  /// [userId] resolves them against this row: self-rating belongs to
  /// [employeeId], reporting-manager rating to [managerId] — whatever either
  /// party's role happens to be. Org-level stages stay role-gated.
  bool needsActionBy(UserRole role, {String? userId}) {
    if (currentStage.isTerminal) return false;
    if (currentStageStatus == StageStatus.submitted) return false;
    if (currentStage == ReviewStage.selfRating) {
      return userId != null && userId == employeeId;
    }
    if (currentStage == ReviewStage.reportingManagerRating) {
      return userId != null && managerId != null && userId == managerId;
    }
    return currentStage.isActionableBy(role);
  }

  /// Management review (approve/return) and incentive payout (mark paid) are
  /// non-rating actions performed on the single-review detail screen; the
  /// rating stages are edited on the per-employee quarterly KRA sheet. This
  /// picks the right destination so a tap lands where the action lives.
  bool get opensReviewDetail =>
      currentStage == ReviewStage.managementReview ||
      currentStage == ReviewStage.incentivePayout;
}
