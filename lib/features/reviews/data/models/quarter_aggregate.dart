import 'monthly_review_summary.dart';

/// The shared quarter maths behind the Performance Incentive Sheet and the
/// quarter-level Review Dashboard — computed once so both agree to the rupee.
///
/// Given an employee's three monthly summaries (`[m0, m1, m2]`, null where a
/// month has no review), it derives:
///   * [base] — the monthly incentive ceiling (the max across the months);
///   * [totalPct] — the quarter score, the average of the three months' final
///     scores (a missing month counts as 0);
///   * [quarterlyFixed] — [base] × 3;
///   * [payable] — [quarterlyFixed] scaled by [totalPct].
///
/// The "is it paid?" question is deliberately NOT answered here: the two
/// surfaces use different rules (the report requires every month present AND
/// settled; the dashboard only requires the present months settled), so each
/// computes that itself from [present].
class QuarterAggregate {
  /// The months that actually have a review, in month order.
  final List<MonthlyReviewSummary> present;

  /// The first present month — the source for identity fields (name, code, …).
  final MonthlyReviewSummary? ref;

  /// Monthly incentive ceiling (the configured eligible amount).
  final double base;

  /// Quarter score % — average of the three months' final scores.
  final double totalPct;

  /// Fixed incentive for the quarter — [base] × 3.
  final double quarterlyFixed;

  /// Payable incentive — [quarterlyFixed] × [totalPct] / 100.
  final double payable;

  const QuarterAggregate._({
    required this.present,
    required this.ref,
    required this.base,
    required this.totalPct,
    required this.quarterlyFixed,
    required this.payable,
  });

  factory QuarterAggregate.of(List<MonthlyReviewSummary?> months) {
    final present = months.whereType<MonthlyReviewSummary>().toList();

    var sum = 0.0;
    for (final m in months) {
      sum += m?.finalScorePct ?? 0;
    }
    final total = months.isEmpty ? 0.0 : sum / months.length;

    final base = present
        .map((s) => s.incentiveEligibleAmount ?? 0)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final fixed = base * 3;

    return QuarterAggregate._(
      present: present,
      ref: present.isNotEmpty ? present.first : null,
      base: base,
      totalPct: total,
      quarterlyFixed: fixed,
      payable: fixed * total / 100,
    );
  }
}
