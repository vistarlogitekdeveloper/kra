import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/utils/monthly_deadlines.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';

void main() {
  group('MonthlyDeadlines.forStage', () {
    final ref = DateTime(2026, 6, 22);

    test('resolves every non-terminal stage to its fixed day of month', () {
      expect(
          MonthlyDeadlines.forStage(ReviewStage.selfRating, ref),
          DateTime(2026, 6, 10));
      expect(
          MonthlyDeadlines.forStage(ReviewStage.accountHrRating, ref),
          DateTime(2026, 6, 12));
      expect(
        MonthlyDeadlines.forStage(ReviewStage.reportingManagerRating, ref),
        DateTime(2026, 6, 13),
      );
      expect(
          MonthlyDeadlines.forStage(ReviewStage.managementReview, ref),
          DateTime(2026, 6, 15));
      expect(
          MonthlyDeadlines.forStage(ReviewStage.incentivePayout, ref),
          DateTime(2026, 6, 20));
    });

    test('returns null for the terminal completed stage', () {
      expect(MonthlyDeadlines.forStage(ReviewStage.completed, ref), isNull);
    });

    test('anchors to the reference month, not a fixed month', () {
      expect(
        MonthlyDeadlines.forStage(
            ReviewStage.selfRating, DateTime(2027, 1, 30)),
        DateTime(2027, 1, 10),
      );
      expect(
        MonthlyDeadlines.forStage(
            ReviewStage.reportingManagerRating, DateTime(2027, 12, 1)),
        DateTime(2027, 12, 13),
      );
    });
  });

  group('MonthlyDeadlines legacy accessors', () {
    // The pre-pipeline callers still route through these. Values follow
    // the new stage schedule so those screens count down to the right
    // dates without editing each call site.
    test('selfRatingDay is the 10th; managerRatingDay is the 13th', () {
      expect(MonthlyDeadlines.selfRatingDay, 10);
      expect(MonthlyDeadlines.managerRatingDay, 13);
    });

    test('selfRating() + managerRating() resolve to the new dates', () {
      final ref = DateTime(2026, 6, 22);
      // ignore: deprecated_member_use_from_same_package
      expect(MonthlyDeadlines.selfRating(ref), DateTime(2026, 6, 10));
      // ignore: deprecated_member_use_from_same_package
      expect(MonthlyDeadlines.managerRating(ref), DateTime(2026, 6, 13));
    });
  });

  group('MonthlyDeadlines.daysRemaining', () {
    test('is positive before, 0 on the day, negative after', () {
      final deadline = DateTime(2026, 6, 10);
      expect(
          MonthlyDeadlines.daysRemaining(deadline, DateTime(2026, 6, 7)), 3);
      expect(
          MonthlyDeadlines.daysRemaining(deadline, DateTime(2026, 6, 10)), 0);
      expect(
          MonthlyDeadlines.daysRemaining(deadline, DateTime(2026, 6, 13)), -3);
    });

    test('ignores the time of day (date-only compare)', () {
      final deadline = DateTime(2026, 6, 10);
      expect(
        MonthlyDeadlines.daysRemaining(
            deadline, DateTime(2026, 6, 9, 23, 59)),
        1,
      );
    });
  });

  group('MonthlyDeadlines.isOverdue', () {
    test('flips strictly after the deadline day', () {
      final deadline = DateTime(2026, 6, 13);
      expect(
          MonthlyDeadlines.isOverdue(deadline, DateTime(2026, 6, 13)), false);
      expect(
          MonthlyDeadlines.isOverdue(deadline, DateTime(2026, 6, 14)), true);
    });
  });
}
