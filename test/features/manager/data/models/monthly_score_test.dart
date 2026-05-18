import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/employee/data/models/enums.dart';
import 'package:vistar_app/features/manager/data/models/monthly_score.dart';

void main() {
  group('MonthlyScore.isEditable', () {
    test('true when month is OPEN and not N/A', () {
      final c = _cell(
        status: ReviewMonthStatus.open,
        isNotApplicable: false,
      );
      expect(c.isEditable, isTrue);
    });

    test('false when N/A even with OPEN month', () {
      final c = _cell(
        status: ReviewMonthStatus.open,
        isNotApplicable: true,
      );
      expect(c.isEditable, isFalse);
    });

    test('false when month is CLOSED', () {
      final c = _cell(
        status: ReviewMonthStatus.closed,
        isNotApplicable: false,
      );
      expect(c.isEditable, isFalse);
    });

    test('false when month is LOCKED', () {
      final c = _cell(
        status: ReviewMonthStatus.locked,
        isNotApplicable: false,
      );
      expect(c.isEditable, isFalse);
    });
  });

  group('MonthlyScore.isManagerFilled', () {
    test('true when managerRating is set', () {
      final c = _cell(managerRating: 8.0);
      expect(c.isManagerFilled, isTrue);
    });

    test('true when N/A regardless of rating', () {
      final c = _cell(managerRating: null, isNotApplicable: true);
      expect(c.isManagerFilled, isTrue);
    });

    test('false when no rating and not N/A', () {
      final c = _cell(managerRating: null);
      expect(c.isManagerFilled, isFalse);
    });
  });

  group('MonthlyScore JSON round-trip', () {
    test('parses string decimals correctly', () {
      final json = {
        'monthlyScoreId': 'cell-1',
        'monthId': 'm-1',
        'monthLabel': 'May 2026',
        'monthStatus': 'OPEN',
        'selfRating': '8.5',
        'managerRating': '9.0',
        'weightedScore': '0.85',
        'isNotApplicable': false,
      };
      final c = MonthlyScore.fromJson(json);
      expect(c.selfRating, 8.5);
      expect(c.managerRating, 9.0);
      expect(c.weightedScore, 0.85);
      expect(c.monthStatus, ReviewMonthStatus.open);
    });
  });
}

MonthlyScore _cell({
  ReviewMonthStatus status = ReviewMonthStatus.open,
  bool isNotApplicable = false,
  double? selfRating,
  double? managerRating,
}) {
  return MonthlyScore(
    monthlyScoreId: 'cell-1',
    monthId: 'm-1',
    monthLabel: 'May',
    monthStatus: status,
    selfRating: selfRating,
    managerRating: managerRating,
    isNotApplicable: isNotApplicable,
  );
}
