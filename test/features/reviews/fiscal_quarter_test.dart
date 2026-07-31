import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';

/// India's fiscal year runs April → March, so the quarter shown on the KRA
/// sheet is derived, not stored: Q1 Apr–Jun, Q2 Jul–Sep, Q3 Oct–Dec,
/// Q4 Jan–Mar — with Jan–Mar rolling back to the PREVIOUS April's fiscal year.
void main() {
  group('ReviewPeriod.fiscalQuarter', () {
    test('Q1 = Apr–Jun', () {
      for (final m in [4, 5, 6]) {
        expect(ReviewPeriod(2026, m).fiscalQuarter, 1, reason: 'month $m');
      }
    });
    test('Q2 = Jul–Sep', () {
      for (final m in [7, 8, 9]) {
        expect(ReviewPeriod(2026, m).fiscalQuarter, 2, reason: 'month $m');
      }
    });
    test('Q3 = Oct–Dec', () {
      for (final m in [10, 11, 12]) {
        expect(ReviewPeriod(2026, m).fiscalQuarter, 3, reason: 'month $m');
      }
    });
    test('Q4 = Jan–Mar', () {
      for (final m in [1, 2, 3]) {
        expect(ReviewPeriod(2027, m).fiscalQuarter, 4, reason: 'month $m');
      }
    });
  });

  group('ReviewPeriod fiscal year', () {
    test('Apr–Dec belong to the fiscal year starting that calendar year', () {
      expect(const ReviewPeriod(2026, 7).fiscalYearStartYear, 2026);
      expect(const ReviewPeriod(2026, 7).fiscalYearLabel, 'FY 2026–27');
    });

    test('Jan–Mar roll back to the previous April fiscal year', () {
      expect(const ReviewPeriod(2027, 2).fiscalYearStartYear, 2026);
      expect(const ReviewPeriod(2027, 2).fiscalYearLabel, 'FY 2026–27');
    });

    test('quarter label combines quarter and fiscal year', () {
      expect(const ReviewPeriod(2026, 8).fiscalQuarterLabel, 'Q2 · FY 2026–27');
      expect(const ReviewPeriod(2027, 3).fiscalQuarterLabel, 'Q4 · FY 2026–27');
      expect(const ReviewPeriod(2026, 4).fiscalQuarterLabel, 'Q1 · FY 2026–27');
    });
  });
}
