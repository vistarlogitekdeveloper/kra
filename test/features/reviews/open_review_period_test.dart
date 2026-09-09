import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/utils/monthly_deadlines.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';

/// "Which month are we rating?" — one answer, in one place.
///
/// A month is rated once it has FINISHED: through September you rate August.
/// The app used to answer this independently in five places (the backend's
/// `findCurrentMonth`, the employee dashboard's fallback, the month picker, the
/// sheet's due-month banner and the cell gate) and they disagreed — the home
/// screen announced "Sep-26 Self-rating pending" on 9 September while the
/// outstanding work was August's.
void main() {
  group('openForRating is always the previous calendar month', () {
    test('mid-September gives August', () {
      expect(
        ReviewPeriod.openForRating(DateTime(2026, 9, 9)).key,
        const ReviewPeriod(2026, 8).key,
      );
    });

    test('the first of the month gives the month that just ended', () {
      expect(
        ReviewPeriod.openForRating(DateTime(2026, 9, 1)).key,
        const ReviewPeriod(2026, 8).key,
      );
    });

    test('the last day of the month still gives the PREVIOUS month', () {
      // 30 September is not "September is over"; it is the last day of it.
      expect(
        ReviewPeriod.openForRating(DateTime(2026, 9, 30, 23, 59)).key,
        const ReviewPeriod(2026, 8).key,
      );
    });

    test('January rolls back to December of the previous year', () {
      expect(
        ReviewPeriod.openForRating(DateTime(2027, 1, 4)).key,
        const ReviewPeriod(2026, 12).key,
      );
    });

    test('it never returns the current month, on any day of any month', () {
      for (var month = 1; month <= 12; month++) {
        for (final day in [1, 15, 28]) {
          final now = DateTime(2026, month, day);
          final open = ReviewPeriod.openForRating(now);
          expect(open.key, isNot(ReviewPeriod.fromDate(now).key),
              reason: 'on ${now.toIso8601String()} it returned the live month');
        }
      }
    });
  });

  group('previous / next roll the year correctly', () {
    test('January previous is December of last year', () {
      expect(const ReviewPeriod(2026, 1).previous.key,
          const ReviewPeriod(2025, 12).key);
    });

    test('December next is January of next year', () {
      expect(const ReviewPeriod(2026, 12).next.key,
          const ReviewPeriod(2027, 1).key);
    });

    test('previous and next are inverses across a year boundary', () {
      for (final p in [
        const ReviewPeriod(2026, 1),
        const ReviewPeriod(2026, 12),
        const ReviewPeriod(2026, 6),
      ]) {
        expect(p.previous.next.key, p.key, reason: p.key);
        expect(p.next.previous.key, p.key, reason: p.key);
      }
    });
  });

  group('ordering', () {
    test('compares across years, not just month numbers', () {
      // A naive month-only comparison makes Dec 2025 look "later" than Jan 2026.
      expect(const ReviewPeriod(2025, 12) <= const ReviewPeriod(2026, 1), isTrue);
      expect(const ReviewPeriod(2026, 1) > const ReviewPeriod(2025, 12), isTrue);
    });

    test('a month is not greater than itself', () {
      expect(const ReviewPeriod(2026, 8) > const ReviewPeriod(2026, 8), isFalse);
      expect(
          const ReviewPeriod(2026, 8) <= const ReviewPeriod(2026, 8), isTrue);
    });
  });

  group('isRatableOn', () {
    final now = DateTime(2026, 9, 9);

    test('the open month is ratable', () {
      expect(const ReviewPeriod(2026, 8).isRatableOn(now), isTrue);
    });

    test('older months stay ratable — a late entry is still allowed', () {
      expect(const ReviewPeriod(2026, 7).isRatableOn(now), isTrue);
      expect(const ReviewPeriod(2025, 12).isRatableOn(now), isTrue);
    });

    test('the CURRENT month is not ratable — it has not ended', () {
      expect(const ReviewPeriod(2026, 9).isRatableOn(now), isFalse);
    });

    test('future months are not ratable', () {
      expect(const ReviewPeriod(2026, 10).isRatableOn(now), isFalse);
      expect(const ReviewPeriod(2027, 1).isRatableOn(now), isFalse);
    });
  });

  group('the deadline schedule agrees with this rule', () {
    test('the self-rating deadline falls AFTER the month it covers', () {
      // This is the evidence the rule is right rather than a preference.
      // Self-rating is due on the 10th; if the month under review were the
      // current one, the deadline would land with two-thirds of that month
      // still to come.
      final now = DateTime(2026, 9, 9);
      final under = ReviewPeriod.openForRating(now);
      final deadline = MonthlyDeadlines.selfRating(now);

      expect(deadline.month, 9);
      expect(deadline.day, ReviewStage.selfRating.deadlineDay);
      expect(under.month, 8);
      // The deadline is in the month after the one being rated.
      expect(ReviewPeriod.fromDate(deadline).key, under.next.key,
          reason: 'the deadline must sit in the month after the review month');
    });

    test('and there is still time left: 9 Sep is one day before the 10th', () {
      final days = MonthlyDeadlines.daysRemaining(
        MonthlyDeadlines.selfRating(DateTime(2026, 9, 9)),
        DateTime(2026, 9, 9),
      );
      expect(days, 1, reason: 'matches the "closes in 1 day" banner');
    });
  });
}
