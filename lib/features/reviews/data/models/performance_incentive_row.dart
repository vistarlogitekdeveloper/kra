import 'monthly_review_summary.dart';
import 'quarter_aggregate.dart';

/// One employee's row in the quarterly Performance Incentive Sheet — a
/// read-only report that mirrors the "Performance Incentive" Excel: every field
/// from that sheet, for one employee across the three months of a quarter.
///
/// Built by aggregating the three monthly [MonthlyReviewSummary] lists (one per
/// month of the quarter) for the same employee — see [PerformanceIncentiveRow.build].
class PerformanceIncentiveRow {
  final int srNo;
  final String employeeId;
  final String employeeCode;
  final String employeeName;

  /// The monthly incentive ceiling ("Performance Incentive Amount").
  final double performanceIncentiveAmount;

  final String? projectLocation;

  /// Self-rating % per month of the quarter (3 entries; null = not rated).
  final List<double?> selfRatings;

  /// Management-review rating % per month (3 entries; null = not rated).
  final List<double?> managementRatings;

  /// Quarter total % — the average of the three months' final scores.
  final double total;

  /// Fixed incentive for the quarter — monthly amount × 3.
  final double quarterlyFixedIncentive;

  /// Payable incentive — quarterly fixed × total %.
  final double payableIncentive;

  /// Derived status remark — [remarkPaid] once the incentive is settled, or an
  /// empty string otherwise (the "not submitted" state is intentionally shown
  /// blank for now, per product decision).
  final String remark;

  /// The remark values shown in the sheet. Only "Incentive Paid" is surfaced;
  /// every other state renders blank ([remarkNotSubmitted] is empty for now).
  static const String remarkPaid = 'Incentive Paid';
  static const String remarkNotSubmitted = '';

  const PerformanceIncentiveRow({
    required this.srNo,
    required this.employeeId,
    required this.employeeCode,
    required this.employeeName,
    required this.performanceIncentiveAmount,
    required this.projectLocation,
    required this.selfRatings,
    required this.managementRatings,
    required this.total,
    required this.quarterlyFixedIncentive,
    required this.payableIncentive,
    required this.remark,
  });

  /// Builds a row from the three months' summaries for one employee. Any month
  /// with no review is `null` in [months]. [srNo] is the 1-based row number.
  factory PerformanceIncentiveRow.build({
    required int srNo,
    required String employeeId,
    required List<MonthlyReviewSummary?> months,
  }) {
    // Shared quarter maths (score total + incentive) so this report and the
    // Review Dashboard agree exactly. Identity fields come from the first month
    // that has data.
    final agg = QuarterAggregate.of(months);
    final selfRatings = [for (final m in months) m?.selfScorePct];
    final managementRatings = [for (final m in months) m?.managementReviewPct];

    return PerformanceIncentiveRow(
      srNo: srNo,
      employeeId: employeeId,
      employeeCode: agg.ref?.employeeCode ?? '',
      employeeName: agg.ref?.employeeName ?? '',
      performanceIncentiveAmount: agg.base,
      projectLocation: agg.ref?.projectLocation,
      selfRatings: selfRatings,
      managementRatings: managementRatings,
      total: agg.totalPct,
      quarterlyFixedIncentive: agg.quarterlyFixed,
      payableIncentive: agg.payable,
      remark: _remarkFor(months),
    );
  }

  /// Derives the status remark. Only the PAID state is surfaced: the incentive
  /// is "Incentive Paid" once every month of the quarter has its payout settled.
  /// Anything short of that (a missing month, or any month not yet paid) renders
  /// blank — the "not submitted" label is intentionally suppressed for now.
  static String _remarkFor(List<MonthlyReviewSummary?> months) {
    final present = months.whereType<MonthlyReviewSummary>().toList();
    final paid = present.length == months.length &&
        present.isNotEmpty &&
        present.every((s) => s.payoutPaid);
    return paid ? remarkPaid : remarkNotSubmitted;
  }
}
