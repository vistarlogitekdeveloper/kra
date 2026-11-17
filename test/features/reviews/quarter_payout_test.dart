import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';
import 'package:vistar_app/features/reviews/data/models/incentive_snapshot.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review_summary.dart';
import 'package:vistar_app/features/reviews/data/models/quarter_payout.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';

/// The incentive is CALCULATED PER MONTH and PAID PER QUARTER.
///
/// The sheet used to show `monthly incentive × 3 × quarter final average`,
/// taking the highest month's ceiling as "the" monthly incentive. That is the
/// same number only while the incentive never moves mid-quarter — and an
/// employee raised in August is exactly the case where it quietly pays the
/// wrong amount. [QuarterPayout] adds the months up instead, each at its own
/// amount and its own final score.
void main() {
  /// One KRA at full weight, scored by management at [finalPct] — enough to
  /// drive [MonthlyReview.finalScorePct] without modelling a whole sheet.
  MonthlyReview month(
    int m, {
    required double eligible,
    required double finalPct,
    ReviewStage stage = ReviewStage.managementReview,
    bool locked = true,
    PayoutStatus payout = PayoutStatus.pending,
  }) {
    const row = MonthlyKraRow(
      id: 'k1',
      name: 'Business development',
      weightagePercent: 100,
      maxScore: 100,
    );
    return MonthlyReview(
      id: 'r-$m',
      employeeId: 'emp1',
      employeeName: 'Dattatraya',
      period: ReviewPeriod(2026, m),
      currentStage: stage,
      stageRecords: const {},
      rows: [
        row.withStageScore(
          ReviewStage.managementReview,
          RowScore(value: finalPct),
        ),
      ],
      incentive: IncentiveSnapshot(
        eligibleAmount: eligible,
        payoutStatus: payout,
      ),
      managementLockedAt: locked ? DateTime.utc(2026, 10, 5) : null,
    );
  }

  // After the quarter: Jul, Aug and Sep 2026 are all over.
  final afterQuarter = DateTime.utc(2026, 10, 20);

  group('the money', () {
    test('a quarter is its months added up, each at its own rate', () {
      final q = QuarterPayout.fromReviews(
        [
          month(7, eligible: 40000, finalPct: 50),
          month(8, eligible: 40000, finalPct: 60),
          month(9, eligible: 40000, finalPct: 70),
        ],
        now: afterQuarter,
      );

      // 20,000 + 24,000 + 28,000
      expect(q.amount, closeTo(72000, 1e-9));
      expect(q.eligibleAmount, closeTo(120000, 1e-9));
      expect(q.finalPct, closeTo(60, 1e-9));
    });

    test('a mid-quarter raise is paid at the rate of each month', () {
      // The case the old formula got wrong: ₹40k in July, ₹60k from August.
      final q = QuarterPayout.fromReviews(
        [
          month(7, eligible: 40000, finalPct: 100),
          month(8, eligible: 60000, finalPct: 100),
          month(9, eligible: 60000, finalPct: 100),
        ],
        now: afterQuarter,
      );

      expect(q.amount, closeTo(160000, 1e-9));
      // The old rule — highest month × 3 × average final — would have paid
      // ₹1,80,000 here, ₹20,000 of it for a July that was never worth it.
      expect(q.amount, isNot(closeTo(180000, 1e-9)));
    });

    test('a month with no review contributes nothing and blocks nothing', () {
      final q = QuarterPayout.fromReviews(
        [month(7, eligible: 40000, finalPct: 50), null, null],
        now: afterQuarter,
      );

      expect(q.months.length, 1);
      expect(q.amount, closeTo(20000, 1e-9));
      expect(q.blockerFor(UserRole.finance), isNull);
    });

    test('each month carries its own working, so the total can be checked', () {
      final q = QuarterPayout.fromReviews(
        [month(7, eligible: 40000, finalPct: 25)],
        now: afterQuarter,
      );

      final july = q.months.single;
      expect(july.label, 'July 2026');
      expect(july.amount, closeTo(10000, 1e-9));
      expect(q.amount, closeTo(july.amount, 1e-9));
    });
  });

  group('what gets settled', () {
    test('only the unpaid months are sent', () {
      final q = QuarterPayout.fromReviews(
        [
          month(7, eligible: 40000, finalPct: 50, payout: PayoutStatus.paid),
          month(8, eligible: 40000, finalPct: 50),
          month(9, eligible: 40000, finalPct: 50),
        ],
        now: afterQuarter,
      );

      // A quarter part-settled by the old per-month button must complete, not
      // refuse — so July is left out rather than re-sent.
      expect(q.unpaidReviewIds, ['r-8', 'r-9']);
      expect(q.anyPaid, isTrue);
      expect(q.allPaid, isFalse);
    });

    test('a fully paid quarter is paid, and offers nothing more', () {
      final q = QuarterPayout.fromReviews(
        [
          for (final m in [7, 8, 9])
            month(m, eligible: 40000, finalPct: 50, payout: PayoutStatus.paid),
        ],
        now: afterQuarter,
      );

      expect(q.allPaid, isTrue);
      expect(q.unpaidReviewIds, isEmpty);
      expect(q.blockerFor(UserRole.finance), MarkPaidBlocker.alreadyPaid);
    });
  });

  group('why it cannot be paid yet', () {
    test('a month still running blocks the quarter, and is named', () {
      final q = QuarterPayout.fromReviews(
        [
          month(7, eligible: 40000, finalPct: 50),
          month(8, eligible: 40000, finalPct: 50),
          month(9, eligible: 40000, finalPct: 50),
        ],
        // Late September: July and August are over, September is not.
        now: DateTime.utc(2026, 9, 28),
      );

      expect(q.blockerFor(UserRole.finance), MarkPaidBlocker.monthNotEnded);
      expect(q.blockingMonth?.label, 'September 2026');
    });

    test('the month boundary is IST, like the server\'s', () {
      final one = [month(7, eligible: 40000, finalPct: 50)];
      // 31 July 23:59 IST — still July.
      expect(
        QuarterPayout.fromReviews(one, now: DateTime.utc(2026, 7, 31, 18, 29))
            .blockerFor(UserRole.finance),
        MarkPaidBlocker.monthNotEnded,
      );
      // 1 August 00:01 IST — over.
      expect(
        QuarterPayout.fromReviews(one, now: DateTime.utc(2026, 7, 31, 18, 31))
            .blockerFor(UserRole.finance),
        isNull,
      );
    });

    test('a month without Save & Lock blocks the quarter', () {
      final q = QuarterPayout.fromReviews(
        [
          month(7, eligible: 40000, finalPct: 50),
          month(8, eligible: 40000, finalPct: 50, locked: false),
        ],
        now: afterQuarter,
      );

      expect(q.blockerFor(UserRole.finance), MarkPaidBlocker.notSignedOff);
      expect(q.blockingMonth?.label, 'August 2026');
    });

    test('a month still in the review phase blocks the quarter', () {
      final q = QuarterPayout.fromReviews(
        [
          month(7, eligible: 40000, finalPct: 50),
          month(8,
              eligible: 40000,
              finalPct: 50,
              stage: ReviewStage.reportingManagerRating),
        ],
        now: afterQuarter,
      );

      expect(q.blockerFor(UserRole.finance), MarkPaidBlocker.managementNotDone);
    });

    test('the EARLIEST blocking month is the one named', () {
      // Both August and September are unfinished; the quarter is settled in
      // one act, so the first thing still to happen is what to say.
      final q = QuarterPayout.fromReviews(
        [
          month(7, eligible: 40000, finalPct: 50),
          month(8, eligible: 40000, finalPct: 50, locked: false),
          month(9, eligible: 40000, finalPct: 50, locked: false),
        ],
        now: afterQuarter,
      );

      expect(q.blockingMonth?.label, 'August 2026');
    });

    test('an already-paid month never counts as the blocker', () {
      final q = QuarterPayout.fromReviews(
        [
          month(7, eligible: 40000, finalPct: 50, payout: PayoutStatus.paid),
          month(8, eligible: 40000, finalPct: 50),
        ],
        now: afterQuarter,
      );

      expect(q.blockingMonth, isNull);
      expect(q.blockerFor(UserRole.finance), isNull);
    });
  });

  group('who may settle it', () {
    final ready = [
      for (final m in [7, 8, 9]) month(m, eligible: 40000, finalPct: 50),
    ];

    test('Accounts and HR admin may; plain HR and a manager may not', () {
      final q = QuarterPayout.fromReviews(ready, now: afterQuarter);

      expect(q.blockerFor(UserRole.finance), isNull);
      expect(q.blockerFor(UserRole.hrAdmin), isNull);
      // The server's ACTOR_ROLES.INCENTIVE_PAYOUT is FINANCE + HR_ADMIN, so a
      // button for anyone else would be a 403 waiting to happen.
      expect(q.blockerFor(UserRole.hr), MarkPaidBlocker.notPayoutRole);
      expect(q.blockerFor(UserRole.manager), MarkPaidBlocker.notPayoutRole);
      expect(q.blockerFor(UserRole.employee), MarkPaidBlocker.notPayoutRole);
    });

    test('nobody settles their own quarter', () {
      final q = QuarterPayout.fromReviews(ready, now: afterQuarter);

      expect(
        q.blockerFor(UserRole.finance, userId: 'emp1', employeeId: 'emp1'),
        MarkPaidBlocker.ownReview,
      );
      expect(
        q.blockerFor(UserRole.finance, userId: 'fin1', employeeId: 'emp1'),
        isNull,
      );
    });
  });
}
