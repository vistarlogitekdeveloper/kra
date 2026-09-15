import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/constants/app_strings.dart';
import 'package:vistar_app/core/utils/monthly_deadlines.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';

/// The published KRA deadline schedule, pinned as ONE table.
///
/// The app already had these dates written down — `MonthlyDeadlines`' own
/// documentation listed Account & HR on the 12th — while the code returned the
/// 13th for all three Review raters. Nothing failed, because the only
/// assertions restated whatever the code happened to do.
///
/// So this file asserts the schedule as published, in one place, and then
/// checks that every derived surface agrees with it rather than restating the
/// numbers. Changing a date means changing the table here and
/// [ReviewStage.deadlineDay]; anything else that disagrees fails.
void main() {
  /// Stage → day of month, exactly as circulated.
  const published = <ReviewStage, int>{
    ReviewStage.selfRating: 10,
    ReviewStage.accountHrRating: 12,
    ReviewStage.financeRating: 12,
    ReviewStage.reportingManagerRating: 13,
    ReviewStage.managementReview: 15,
    ReviewStage.incentivePayout: 20,
  };

  group('the schedule itself', () {
    published.forEach((stage, day) {
      test('${stage.label} is due on the $day', () {
        expect(stage.deadlineDay, day);
      });
    });

    test('only the terminal stage has no deadline', () {
      for (final stage in ReviewStage.values) {
        if (stage == ReviewStage.completed) {
          expect(stage.deadlineDay, isNull);
        } else {
          expect(stage.deadlineDay, isNotNull, reason: '$stage');
        }
      }
      // Every non-terminal stage is covered by the table above, so a stage
      // added later cannot quietly ship without a published date.
      expect(
        published.keys.toSet(),
        ReviewStage.values.toSet()..remove(ReviewStage.completed),
      );
    });

    test('the order is self → account/HR → manager → management → payout', () {
      // The dates encode the hand-off order, so an edit that breaks the
      // ordering breaks the process even if each date looks plausible alone.
      final days = [
        ReviewStage.selfRating,
        ReviewStage.accountHrRating,
        ReviewStage.reportingManagerRating,
        ReviewStage.managementReview,
        ReviewStage.incentivePayout,
      ].map((s) => s.deadlineDay!).toList();
      final sorted = [...days]..sort();
      expect(days, sorted);
      // Account/HR strictly before the reporting manager, who moderates them.
      expect(ReviewStage.accountHrRating.deadlineDay,
          lessThan(ReviewStage.reportingManagerRating.deadlineDay!));
    });
  });

  group('derived surfaces agree with it', () {
    final ref = DateTime(2026, 6, 1);

    published.forEach((stage, day) {
      test('MonthlyDeadlines.forStage resolves ${stage.label} to that day', () {
        expect(MonthlyDeadlines.forStage(stage, ref), DateTime(2026, 6, day));
      });
    });

    test('the legacy self/manager accessors read from the same source', () {
      // The employee self-rate and manager-rate screens call these directly.
      expect(MonthlyDeadlines.selfRatingDay, published[ReviewStage.selfRating]);
      expect(MonthlyDeadlines.managerRatingDay,
          published[ReviewStage.reportingManagerRating]);
      expect(MonthlyDeadlines.selfRating(ref),
          DateTime(2026, 6, published[ReviewStage.selfRating]!));
      expect(MonthlyDeadlines.managerRating(ref),
          DateTime(2026, 6, published[ReviewStage.reportingManagerRating]!));
    });
  });

  group('deadline copy', () {
    test('ordinals are right, including the 11th-13th exceptions', () {
      expect(AppStrings.ordinalDay(1), 'the 1st');
      expect(AppStrings.ordinalDay(2), 'the 2nd');
      expect(AppStrings.ordinalDay(3), 'the 3rd');
      expect(AppStrings.ordinalDay(4), 'the 4th');
      // The ones a naive last-digit rule gets wrong.
      expect(AppStrings.ordinalDay(11), 'the 11th');
      expect(AppStrings.ordinalDay(12), 'the 12th');
      expect(AppStrings.ordinalDay(13), 'the 13th');
      expect(AppStrings.ordinalDay(21), 'the 21st');
      expect(AppStrings.ordinalDay(22), 'the 22nd');
      expect(AppStrings.ordinalDay(23), 'the 23rd');
    });

    test('every published day renders readable copy', () {
      for (final day in published.values) {
        final copy = AppStrings.dueByEachMonth(day);
        expect(copy, contains('$day'));
        expect(copy, contains('each month'));
        // Phrased per month, not as one date: the quarterly sheet shows three
        // months at once, so a single date would be wrong for two of them.
        expect(copy, isNot(contains('2026')));
      }
      expect(AppStrings.dueByEachMonth(12), ' Due by the 12th of each month.');
    });
  });
}
