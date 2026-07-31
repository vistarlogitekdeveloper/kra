import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/reviews/data/models/incentive_snapshot.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review_summary.dart';
import 'package:vistar_app/features/reviews/data/models/performance_incentive_row.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/stage_status.dart';

/// The Performance Incentive Sheet aggregates three monthly summaries per
/// employee into one quarterly row. Lock the maths: fixed = monthly × 3,
/// payable = fixed × total%, total = average of the three months' finals.
void main() {
  MonthlyReviewSummary month({
    required int m,
    required double eligible,
    required double self,
    double? management,
    required double finalPct,
    required ReviewStage stage,
    StageStatus status = StageStatus.inProgress,
    PayoutStatus payoutStatus = PayoutStatus.pending,
  }) {
    return MonthlyReviewSummary(
      id: 'r$m',
      employeeId: 'emp1',
      employeeName: 'Asha',
      employeeCode: 'VLPL0001',
      year: 2026,
      month: m,
      monthLabel: 'x',
      currentStage: stage,
      currentStageStatus: status,
      finalScorePct: finalPct,
      incentiveEligibleAmount: eligible,
      selfScorePct: self,
      managementReviewPct: management,
      projectLocation: 'Adept, Pune',
      payoutStatus: payoutStatus,
    );
  }

  test('all months paid → Incentive Paid; fixed = ×3, payable = fixed × total%',
      () {
    final row = PerformanceIncentiveRow.build(
      srNo: 1,
      employeeId: 'emp1',
      months: [
        for (final mth in [7, 8, 9])
          month(
            m: mth,
            eligible: 8000,
            self: 85,
            management: 90,
            finalPct: 90,
            stage: ReviewStage.completed,
            status: StageStatus.submitted,
            payoutStatus: PayoutStatus.paid,
          ),
      ],
    );

    expect(row.employeeCode, 'VLPL0001');
    expect(row.projectLocation, 'Adept, Pune');
    expect(row.performanceIncentiveAmount, 8000);
    expect(row.selfRatings, [85, 85, 85]);
    expect(row.managementRatings, [90, 90, 90]);
    expect(row.total, closeTo(90, 1e-9));
    expect(row.quarterlyFixedIncentive, 24000);
    expect(row.payableIncentive, closeTo(24000 * 90 / 100, 1e-6)); // 21,600
    expect(row.remark, PerformanceIncentiveRow.remarkPaid);
  });

  test('reviewed but a month still unpaid → KRA Not Submitted', () {
    // All three months present + fully reviewed, but not settled → not paid.
    final row = PerformanceIncentiveRow.build(
      srNo: 1,
      employeeId: 'emp1',
      months: [
        for (final mth in [7, 8, 9])
          month(
            m: mth,
            eligible: 8000,
            self: 85,
            management: 90,
            finalPct: 90,
            stage: ReviewStage.managementReview,
            status: StageStatus.submitted,
          ),
      ],
    );
    expect(row.remark, PerformanceIncentiveRow.remarkNotSubmitted);
  });

  test('a partly-done quarter: missing month counts as 0, not submitted', () {
    final row = PerformanceIncentiveRow.build(
      srNo: 2,
      employeeId: 'emp1',
      months: [
        month(
          m: 7,
          eligible: 5000,
          self: 70,
          finalPct: 70,
          stage: ReviewStage.selfRating,
        ),
        null, // no review generated for month 2
        month(
          m: 9,
          eligible: 5000,
          self: 80,
          finalPct: 80,
          stage: ReviewStage.reportingManagerRating,
        ),
      ],
    );

    expect(row.selfRatings, [70, null, 80]);
    expect(row.managementRatings, [null, null, null]);
    expect(row.total, closeTo((70 + 0 + 80) / 3, 1e-9)); // 50
    expect(row.quarterlyFixedIncentive, 15000);
    expect(row.payableIncentive, closeTo(15000 * 50 / 100, 1e-6)); // 7,500
    expect(row.remark, PerformanceIncentiveRow.remarkNotSubmitted);
  });

  test('no reviews at all → KRA Not Submitted', () {
    final row = PerformanceIncentiveRow.build(
      srNo: 3,
      employeeId: 'emp1',
      months: const [null, null, null],
    );
    expect(row.remark, PerformanceIncentiveRow.remarkNotSubmitted);
    expect(row.total, 0);
    expect(row.payableIncentive, 0);
  });
}
