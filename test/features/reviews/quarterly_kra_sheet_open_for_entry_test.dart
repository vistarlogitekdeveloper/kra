import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// Guards WHEN a cell may be filled in, as distinct from WHO may fill it.
///
/// Reported from the live sheet on 29 August: reviewers were being offered a
/// "Rate" button for August, which no employee had self-rated yet, and for
/// September, which had not started. Both invert the pipeline — a reviewer's
/// score is meant to moderate the employee's, and the reporting manager is
/// explicitly capped by it, so rating first sets the ceiling for a number the
/// employee has not chosen.
void main() {
  const july = ReviewPeriod(2026, 7);
  const august = ReviewPeriod(2026, 8);
  const september = ReviewPeriod(2026, 9);

  // The reported day: August is the current month, September has not begun.
  final now = DateTime(2026, 8, 29);

  MonthlyKraRow row({double? selfValue, KraReviewer? reviewer}) {
    var r = MonthlyKraRow(
      id: 'k1',
      name: 'Safety of the Facility',
      weightagePercent: 5,
      maxScore: 100,
      reviewerGroup: reviewer ?? KraReviewer.reportingManager,
      displayOrder: 1,
    );
    if (selfValue != null) {
      r = r.withStageScore(ReviewStage.selfRating, RowScore(value: selfValue));
    }
    return r;
  }

  bool open(ReviewStage stage, MonthlyKraRow r, ReviewPeriod month) =>
      isCellOpenForEntry(stage: stage, row: r, month: month, now: now);

  group('a month that has not started', () {
    test('is closed to every stage, including the employee', () {
      final rated = row(selfValue: 90);
      for (final stage in [
        ReviewStage.selfRating,
        ReviewStage.reportingManagerRating,
        ReviewStage.accountHrRating,
        ReviewStage.financeRating,
        ReviewStage.managementReview,
      ]) {
        expect(open(stage, rated, september), isFalse, reason: '$stage');
      }
    });

    test('isFutureMonth is strict — the current month is not future', () {
      expect(isFutureMonth(september, now), isTrue);
      expect(isFutureMonth(august, now), isFalse);
      expect(isFutureMonth(july, now), isFalse);
      // Across a year boundary.
      expect(isFutureMonth(const ReviewPeriod(2027, 1), now), isTrue);
      expect(isFutureMonth(const ReviewPeriod(2025, 12), now), isFalse);
    });
  });

  group('a started month with no self-rating', () {
    test('the employee may still rate it — that is the unblocking action', () {
      expect(open(ReviewStage.selfRating, row(), august), isTrue);
    });

    test('but no reviewer may, which is the reported bug', () {
      for (final stage in [
        ReviewStage.reportingManagerRating,
        ReviewStage.accountHrRating,
        ReviewStage.financeRating,
      ]) {
        expect(open(stage, row(), august), isFalse, reason: '$stage');
      }
    });

    test('and management cannot sign off on an unrated KRA', () {
      expect(open(ReviewStage.managementReview, row(), august), isFalse);
    });
  });

  group('once the self-rating is in', () {
    test('every downstream stage opens', () {
      final rated = row(selfValue: 80);
      for (final stage in [
        ReviewStage.reportingManagerRating,
        ReviewStage.accountHrRating,
        ReviewStage.financeRating,
        ReviewStage.managementReview,
      ]) {
        expect(open(stage, rated, august), isTrue, reason: '$stage');
      }
    });

    test('a zero self-rating counts — rating 0 is rating', () {
      expect(
        open(ReviewStage.reportingManagerRating, row(selfValue: 0), august),
        isTrue,
      );
    });
  });

  test('the gate is PER KRA, not per month', () {
    // One unrated KRA must not close the ones the employee has done, and a
    // rated one must not open the rest.
    expect(
      open(ReviewStage.reportingManagerRating, row(selfValue: 70), august),
      isTrue,
    );
    expect(
      open(ReviewStage.reportingManagerRating, row(), august),
      isFalse,
    );
  });

  test('a past month with no self-rating stays closed to reviewers', () {
    // The rule is about order, not about the calendar: rating a KRA the
    // employee never rated inverts the pipeline whenever it happens. The
    // employee can still go back and rate it, which reopens the cell.
    expect(open(ReviewStage.reportingManagerRating, row(), july), isFalse);
    expect(open(ReviewStage.selfRating, row(), july), isTrue);
    expect(
      open(ReviewStage.reportingManagerRating, row(selfValue: 60), july),
      isTrue,
    );
  });
}
