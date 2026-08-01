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

  /// Derived status remark — exactly one of [remarkPaid] / [remarkNotSubmitted].
  final String remark;

  /// The two remark values shown in the sheet.
  static const String remarkPaid = 'Incentive Paid';
  static const String remarkNotSubmitted = 'KRA Not Submitted';

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

  /// Derives the status remark. Only two states are surfaced: the incentive is
  /// PAID once every month of the quarter has its payout settled; anything short
  /// of that (a missing month, or any month not yet paid) reads as the KRA not
  /// being submitted / settled.
  static String _remarkFor(List<MonthlyReviewSummary?> months) {
    final present = months.whereType<MonthlyReviewSummary>().toList();
    final paid = present.length == months.length &&
        present.isNotEmpty &&
        present.every((s) => s.payoutPaid);
    return paid ? remarkPaid : remarkNotSubmitted;
  }
}
