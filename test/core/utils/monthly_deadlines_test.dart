import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/utils/monthly_deadlines.dart';

void main() {
  group('MonthlyDeadlines', () {
    test('self-rating is the 7th, manager rating the 10th of the month', () {
      final ref = DateTime(2026, 6, 22);
      expect(MonthlyDeadlines.selfRating(ref), DateTime(2026, 6, 7));
      expect(MonthlyDeadlines.managerRating(ref), DateTime(2026, 6, 10));
      expect(MonthlyDeadlines.selfRatingDay, 7);
      expect(MonthlyDeadlines.managerRatingDay, 10);
    });

    test('anchors to the reference month, not a fixed month', () {
      expect(
        MonthlyDeadlines.selfRating(DateTime(2027, 1, 30)),
        DateTime(2027, 1, 7),
      );
      expect(
        MonthlyDeadlines.managerRating(DateTime(2027, 12, 1)),
        DateTime(2027, 12, 10),
      );
    });

    test('daysRemaining is positive before, 0 on the day, negative after', () {
      final deadline = DateTime(2026, 6, 7);
      expect(MonthlyDeadlines.daysRemaining(deadline, DateTime(2026, 6, 4)), 3);
      expect(MonthlyDeadlines.daysRemaining(deadline, DateTime(2026, 6, 7)), 0);
      expect(
          MonthlyDeadlines.daysRemaining(deadline, DateTime(2026, 6, 10)), -3);
    });

    test('daysRemaining ignores the time of day (date-only compare)', () {
      final deadline = DateTime(2026, 6, 7);
      expect(
        MonthlyDeadlines.daysRemaining(deadline, DateTime(2026, 6, 6, 23, 59)),
        1,
      );
    });

    test('isOverdue flips strictly after the deadline day', () {
      final deadline = DateTime(2026, 6, 10);
      expect(
          MonthlyDeadlines.isOverdue(deadline, DateTime(2026, 6, 10)), false);
      expect(MonthlyDeadlines.isOverdue(deadline, DateTime(2026, 6, 11)), true);
    });
  });
}
