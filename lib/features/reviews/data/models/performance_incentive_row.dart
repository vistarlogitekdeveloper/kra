import 'monthly_review_summary.dart';

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

  /// Derived status remark (NO KRA / KRA Review Pending / Finalized).
  final String remark;

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
    // Identity / static fields — take the first month that actually has data.
    final present = months.whereType<MonthlyReviewSummary>().toList();
    final ref = present.isNotEmpty ? present.first : null;

    final base = present
            .map((s) => s.incentiveEligibleAmount ?? 0)
            .fold<double>(0, (a, b) => a > b ? a : b) // the configured ceiling
        ;
    final selfRatings = [for (final m in months) m?.selfScorePct];
    final managementRatings = [for (final m in months) m?.managementReviewPct];

    // Quarter total = average of the three months' final scores (a missing
    // month counts as 0), matching the quarterly KRA sheet's payout maths.
    var sum = 0.0;
    for (final m in months) {
      sum += m?.finalScorePct ?? 0;
    }
    final total = sum / 3;

    final quarterlyFixed = base * 3;
    final payable = quarterlyFixed * total / 100;

    return PerformanceIncentiveRow(
      srNo: srNo,
      employeeId: employeeId,
      employeeCode: ref?.employeeCode ?? '',
      employeeName: ref?.employeeName ?? '',
      performanceIncentiveAmount: base,
      projectLocation: ref?.projectLocation,
      selfRatings: selfRatings,
      managementRatings: managementRatings,
      total: total,
      quarterlyFixedIncentive: quarterlyFixed,
      payableIncentive: payable,
      remark: _remarkFor(months),
    );
  }

  /// Derives a status remark from the three months.
  static String _remarkFor(List<MonthlyReviewSummary?> months) {
    final present = months.whereType<MonthlyReviewSummary>().toList();
    if (present.isEmpty) return 'NO KRA';
    // Any month whose management review isn't done yet → still pending.
    final anyPending =
        present.any((s) => !s.managementReviewDone) || present.length < 3;
    return anyPending ? 'KRA Review Pending' : 'Finalized';
  }
}
