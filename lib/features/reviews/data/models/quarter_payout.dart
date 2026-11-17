import '../../../auth/data/models/user.dart';
import 'monthly_review.dart';
import 'monthly_review_summary.dart';
import 'incentive_snapshot.dart';
import 'review_stage.dart';

/// One month's share of a quarter's incentive.
///
/// The incentive is **calculated per month** — each month has its own eligible
/// amount and its own final score — and **paid per quarter**. So the quarter's
/// money is the sum of these, never a quarter-average applied to one ceiling:
/// the two agree only while the eligible amount never changes mid-quarter, and
/// an employee whose incentive is raised in August is exactly the case where
/// the shortcut quietly pays the wrong number.
class MonthPayout {
  /// The monthly review this settles. Null when the month has no review at
  /// all (a quarter can be viewed before every month exists).
  final String? reviewId;
  final int year;
  final int month;

  /// That month's own incentive ceiling.
  final double eligibleAmount;

  /// Management-decided final score for the month. An unrated KRA counts 0,
  /// which is the same rule the sheet's Final column prints.
  final double finalScorePct;

  final bool paid;

  /// Management has committed the month with Save & Lock.
  final bool signedOff;

  /// Management has rated (or the month has moved past the management stage).
  final bool managementDone;

  /// The month is over. A month cannot be paid while it is still running.
  final bool ended;

  const MonthPayout({
    required this.reviewId,
    required this.year,
    required this.month,
    required this.eligibleAmount,
    required this.finalScorePct,
    required this.paid,
    required this.signedOff,
    required this.managementDone,
    required this.ended,
  });

  /// This month's share of the quarter payout.
  double get amount => eligibleAmount * finalScorePct / 100;

  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// "September 2026" — the server names months this way in its refusals, so
  /// a client-side block and a server-side one read as the same sentence.
  String get label => '${_monthNames[month - 1]} $year';

  /// Why this month cannot be paid, or null when it can. Mirrors the server's
  /// per-month gates in mark-paid-quarter, minus the one the client cannot
  /// know (a KRA with no management rating) — the server refuses that by name.
  MarkPaidBlocker? get blocker {
    if (paid) return MarkPaidBlocker.alreadyPaid;
    if (!ended) return MarkPaidBlocker.monthNotEnded;
    if (!managementDone) return MarkPaidBlocker.managementNotDone;
    if (!signedOff) return MarkPaidBlocker.notSignedOff;
    return null;
  }
}

/// What a quarter is worth and whether it can be settled.
///
/// Built from the three monthly reviews the quarterly sheet already holds, so
/// the card showing the money and the button settling it read the same data.
class QuarterPayout {
  final List<MonthPayout> months;

  const QuarterPayout(this.months);

  /// Reads the quarter off the sheet's three months. A null entry is a month
  /// with no review — it contributes nothing and blocks nothing, since there
  /// is no incentive to pay for a month that was never generated.
  factory QuarterPayout.fromReviews(
    List<MonthlyReview?> reviews, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    return QuarterPayout([
      for (final r in reviews)
        if (r != null)
          MonthPayout(
            reviewId: r.id,
            year: r.period.year,
            month: r.period.month,
            eligibleAmount: r.eligibleAmount,
            finalScorePct: r.finalScorePct,
            paid: r.payoutStatus == PayoutStatus.paid,
            signedOff: r.isManagementLocked,
            managementDone: _managementDone(r),
            ended: _monthEnded(r.period.year, r.period.month, at),
          ),
    ]);
  }

  /// The quarter's incentive: the months added up, each at its own rate.
  double get amount => months.fold<double>(0, (sum, m) => sum + m.amount);

  /// What the quarter could be worth at 100% — the months' own ceilings
  /// added up, not one month's ceiling multiplied by three.
  double get eligibleAmount =>
      months.fold<double>(0, (sum, m) => sum + m.eligibleAmount);

  /// The quarter as a percentage of what it could have been. Shown rather
  /// than re-derived from an average of averages, which disagrees with the
  /// money whenever the monthly ceilings differ.
  double get finalPct =>
      eligibleAmount <= 0 ? 0 : amount / eligibleAmount * 100;

  bool get anyPaid => months.any((m) => m.paid);
  bool get allPaid => months.isNotEmpty && months.every((m) => m.paid);

  /// The reviews a settle call should name: every month not already paid.
  /// Already-paid months are left out rather than re-sent, so a quarter that
  /// was part-settled completes instead of refusing.
  List<String> get unpaidReviewIds => [
        for (final m in months)
          if (!m.paid && m.reviewId != null) m.reviewId!,
      ];

  /// The month standing in the way, or null when the quarter is payable.
  /// The EARLIEST blocking month: the quarter is settled in one act, so the
  /// first thing still to happen is the one worth naming.
  MonthPayout? get blockingMonth {
    for (final m in months) {
      if (m.blocker != null && m.blocker != MarkPaidBlocker.alreadyPaid) {
        return m;
      }
    }
    return null;
  }

  /// Why [role] cannot settle this quarter now, or null when they can.
  ///
  /// Same shape as [MonthlyReviewSummary.markPaidBlockerFor] and the same
  /// enum, so one set of copy serves both. [employeeId] is the employee the
  /// sheet belongs to — nobody settles their own incentive.
  MarkPaidBlocker? blockerFor(
    UserRole role, {
    String? userId,
    String? employeeId,
  }) {
    if (!ReviewStage.incentivePayout.actorRoles.contains(role)) {
      return MarkPaidBlocker.notPayoutRole;
    }
    if (userId != null && employeeId != null && userId == employeeId) {
      return MarkPaidBlocker.ownReview;
    }
    if (months.isEmpty) return MarkPaidBlocker.managementNotDone;
    if (allPaid) return MarkPaidBlocker.alreadyPaid;
    return blockingMonth?.blocker;
  }

  static bool _managementDone(MonthlyReview r) =>
      r.currentStage == ReviewStage.managementReview ||
      r.currentStage == ReviewStage.incentivePayout ||
      r.currentStage == ReviewStage.completed;

  /// Whether the month is over in IST, the same boundary the server uses
  /// (a month ends at 00:00 IST on the 1st, i.e. 18:30 UTC the day before).
  static bool _monthEnded(int year, int month, DateTime now) {
    final next = month == 12
        ? DateTime.utc(year + 1, 1, 1)
        : DateTime.utc(year, month + 1, 1);
    return !now
        .toUtc()
        .isBefore(next.subtract(const Duration(hours: 5, minutes: 30)));
  }
}
