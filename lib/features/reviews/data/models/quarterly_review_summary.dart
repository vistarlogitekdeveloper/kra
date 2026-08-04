import '../../../auth/data/models/user.dart';
import 'monthly_review_summary.dart';
import 'quarter_aggregate.dart';
import 'review_stage.dart';
import 'stage_status.dart';

/// One employee's row on the quarter-level Review Dashboard.
///
/// The reviews module is quarter-oriented everywhere else (the Quarterly KRA
/// Sheet and the Performance Incentive Sheet both aggregate three months), so
/// the dashboard does too: a single monthly snapshot would read "Self-Rating /
/// 0%" for an employee whose quarter is actually well underway in another
/// month. This aggregates the quarter's three [MonthlyReviewSummary]s into one
/// row —
///   * **stage/status** = the FURTHEST-along month (so July's completed
///     Management Review shows even while August is still empty), read from each
///     month's scores-aware [MonthlyReviewSummary.displayStage];
///   * **scorePct** = the quarter total, the average of the three months' final
///     scores (a missing month counts as 0) — the same figure the Performance
///     Incentive Sheet prints;
///   * **incentive** = quarterly fixed (monthly ceiling × 3) and the payable
///     amount scaled by the quarter total, matching that sheet.
class QuarterlyReviewSummary {
  final String employeeId;
  final String employeeName;
  final String employeeCode;
  final String? employeeGrade;
  final String? projectLocation;
  final String? managerId;

  /// Furthest-along stage across the quarter, and its status.
  final ReviewStage stage;
  final StageStatus stageStatus;

  /// Quarter total % — the average of the three months' final scores.
  final double scorePct;

  /// Fixed incentive for the quarter — the monthly ceiling × 3.
  final double quarterlyFixedIncentive;

  /// Payable incentive — quarterly fixed × [scorePct].
  final double payableIncentive;

  /// True once every month of the quarter that exists has been settled.
  final bool payoutPaid;

  /// The three months as fetched (any absent month is null) — retained so the
  /// dashboard can reuse each month's per-caller [MonthlyReviewSummary.needsActionBy].
  final List<MonthlyReviewSummary?> months;

  const QuarterlyReviewSummary({
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    required this.employeeGrade,
    required this.projectLocation,
    required this.managerId,
    required this.stage,
    required this.stageStatus,
    required this.scorePct,
    required this.quarterlyFixedIncentive,
    required this.payableIncentive,
    required this.payoutPaid,
    required this.months,
  });

  /// Aggregates the quarter's [months] (one entry per month, null when a month
  /// has no review yet) into a single dashboard row for [employeeId].
  factory QuarterlyReviewSummary.build({
    required String employeeId,
    required List<MonthlyReviewSummary?> months,
  }) {
    // Shared quarter maths (score total + incentive) so this row and the
    // Performance Incentive Sheet agree exactly.
    final agg = QuarterAggregate.of(months);

    // Identity — take the first present month that carries each field.
    String? grade;
    String? location;
    String? managerId;
    for (final m in agg.present) {
      if (grade == null && (m.employeeGrade?.trim().isNotEmpty ?? false)) {
        grade = m.employeeGrade;
      }
      if (location == null && (m.projectLocation?.trim().isNotEmpty ?? false)) {
        location = m.projectLocation;
      }
      managerId ??= m.managerId;
    }

    // Furthest-along month drives the stage chip. Read each month's scores-aware
    // display stage, then keep the one that's deepest in the pipeline.
    MonthlyReviewSummary? furthest;
    for (final m in agg.present) {
      if (furthest == null ||
          m.displayStage.pipelineIndex > furthest.displayStage.pipelineIndex) {
        furthest = m;
      }
    }
    final stage = furthest?.displayStage ?? ReviewStage.selfRating;
    final stageStatus = furthest?.displayStatus ?? StageStatus.inProgress;

    // Paid only when every month that exists is settled (the dashboard's rule,
    // looser than the report's "all three months present AND paid").
    final paid =
        agg.present.isNotEmpty && agg.present.every((s) => s.payoutPaid);

    return QuarterlyReviewSummary(
      employeeId: employeeId,
      employeeName: agg.ref?.employeeName ?? '',
      employeeCode: agg.ref?.employeeCode ?? '',
      employeeGrade: grade,
      projectLocation: location,
      managerId: managerId,
      stage: stage,
      stageStatus: stageStatus,
      scorePct: agg.totalPct,
      quarterlyFixedIncentive: agg.quarterlyFixed,
      payableIncentive: agg.payable,
      payoutPaid: paid,
      months: months,
    );
  }

  /// True when any month of the quarter is awaiting [role]'s action — reuses the
  /// per-month, per-caller predicate so the dashboard's "needs review" highlight
  /// stays consistent with the monthly view.
  bool needsActionBy(UserRole role, {String? userId}) =>
      months.any((m) => m != null && m.needsActionBy(role, userId: userId));
}
