import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/reviews/data/models/incentive_snapshot.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review_summary.dart';
import 'package:vistar_app/features/reviews/data/models/quarterly_review_summary.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/stage_status.dart';

/// The Review Dashboard is quarter-level: it folds an employee's three monthly
/// summaries into one row. Lock the aggregation — the FURTHEST-along month sets
/// the stage chip (so a completed July still shows even while August is empty),
/// the score is the quarter average, and the incentive mirrors the Performance
/// Incentive Sheet.
void main() {
  MonthlyReviewSummary month({
    required int m,
    required ReviewStage stage,
    StageStatus status = StageStatus.inProgress,
    double finalPct = 0,
    double? self,
    double? management,
    double eligible = 5000,
    String? grade,
    String? location,
    PayoutStatus payoutStatus = PayoutStatus.pending,
  }) {
    return MonthlyReviewSummary(
      id: 'r$m',
      employeeId: 'emp1',
      employeeName: 'Amit',
      employeeCode: 'VLPL1463',
      employeeGrade: grade,
      year: 2026,
      month: m,
      monthLabel: 'x',
      currentStage: stage,
      currentStageStatus: status,
      finalScorePct: finalPct,
      incentiveEligibleAmount: eligible,
      selfScorePct: self,
      managementReviewPct: management,
      projectLocation: location,
      payoutStatus: payoutStatus,
    );
  }

  test('furthest month drives the stage — July done, Aug/Sep empty → '
      'Management Review even though the cursor is frozen at Self-Rating', () {
    final row = QuarterlyReviewSummary.build(
      employeeId: 'emp1',
      months: [
        // July: fully reviewed (self + management scored), cursor NOT advanced.
        month(
          m: 7,
          stage: ReviewStage.selfRating,
          status: StageStatus.inProgress,
          finalPct: 90,
          self: 85,
          management: 90,
          grade: 'A4',
          location: 'Knorr Bremse, Hinjewadi',
        ),
        null, // August — not generated yet
        null, // September
      ],
    );

    expect(row.stage, ReviewStage.managementReview);
    expect(row.stageStatus, StageStatus.submitted);
    expect(row.employeeCode, 'VLPL1463');
    expect(row.employeeGrade, 'A4');
    expect(row.projectLocation, 'Knorr Bremse, Hinjewadi');
    // Quarter total = (90 + 0 + 0) / 3.
    expect(row.scorePct, closeTo(30, 1e-9));
    expect(row.quarterlyFixedIncentive, 15000); // 5000 × 3
    expect(row.payableIncentive, closeTo(15000 * 30 / 100, 1e-6)); // 4,500
    expect(row.payoutPaid, isFalse);
  });

  test('a quarter with no scores anywhere stays at Self-Rating (in progress)',
      () {
    final row = QuarterlyReviewSummary.build(
      employeeId: 'emp1',
      months: [
        month(m: 7, stage: ReviewStage.selfRating),
        month(m: 8, stage: ReviewStage.selfRating),
        month(m: 9, stage: ReviewStage.selfRating),
      ],
    );
    expect(row.stage, ReviewStage.selfRating);
    expect(row.stageStatus, StageStatus.inProgress);
    expect(row.scorePct, 0);
    expect(row.payableIncentive, 0);
    expect(row.payoutPaid, isFalse);
  });

  test('an empty quarter (no reviews at all) is a safe Self-Rating row', () {
    final row = QuarterlyReviewSummary.build(
      employeeId: 'emp1',
      months: const [null, null, null],
    );
    expect(row.stage, ReviewStage.selfRating);
    expect(row.stageStatus, StageStatus.inProgress);
    expect(row.scorePct, 0);
    expect(row.quarterlyFixedIncentive, 0);
    expect(row.employeeName, '');
  });

  test('every month settled → Completed and paid', () {
    final row = QuarterlyReviewSummary.build(
      employeeId: 'emp1',
      months: [
        for (final m in [7, 8, 9])
          month(
            m: m,
            stage: ReviewStage.completed,
            status: StageStatus.submitted,
            finalPct: 90,
            self: 85,
            management: 90,
            payoutStatus: PayoutStatus.paid,
          ),
      ],
    );
    expect(row.stage, ReviewStage.completed);
    expect(row.payoutPaid, isTrue);
    expect(row.scorePct, closeTo(90, 1e-9));
  });
}
