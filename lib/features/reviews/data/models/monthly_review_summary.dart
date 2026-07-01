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
    this.managerName,
    required this.year,
    required this.month,
    required this.monthLabel,
    required this.currentStage,
    required this.currentStageStatus,
    this.finalScorePct = 0,
    this.incentiveEligibleAmount,
  });

  /// Projection from a full review — used by the mock and any backend
  /// summary endpoint that returns whole reviews.
  factory MonthlyReviewSummary.fromReview(MonthlyReview r) =>
      MonthlyReviewSummary(
        id: r.id,
        employeeId: r.employeeId,
        employeeName: r.employeeName,
        employeeCode: r.employeeCode,
        employeeGrade: r.grade,
        managerName: r.managerName,
        year: r.period.year,
        month: r.period.month,
        monthLabel: r.period.label,
        currentStage: r.currentStage,
        currentStageStatus: r.statusOf(r.currentStage),
        finalScorePct: r.finalScorePct,
        incentiveEligibleAmount: r.eligibleAmount,
      );

  /// True when [role] can act on the current stage — i.e. the caller's
  /// dashboard should badge this row as "needs my action".
  bool needsActionBy(UserRole role) {
    if (currentStage.isTerminal) return false;
    if (currentStageStatus == StageStatus.submitted) return false;
    return currentStage.isActionableBy(role);
  }
}
