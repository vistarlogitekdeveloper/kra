import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// Guards WHEN a cell may be filled in, as distinct from WHO may fill it.
///
/// Reported from the live sheet: reviewers were being offered a "Rate" button
/// for a month no employee had self-rated yet, and for a month that had not
/// finished. Both invert the pipeline — a reviewer's score is meant to
/// moderate the employee's, and the reporting manager is explicitly capped by
/// it, so rating first sets the ceiling for a number the employee has not
/// chosen.
///
/// The clock sits in SEPTEMBER, so August is the month under review. It used to
/// sit inside August and expect August to be ratable, which assumed a month
/// could be scored while it was still running — the defect that let a September
/// self-rating be written and persisted on 9 September.
void main() {
  const july = ReviewPeriod(2026, 7);
  const august = ReviewPeriod(2026, 8);
  const september = ReviewPeriod(2026, 9);

  // August is the month under review; September is the live month and so is
  // not ratable; July has ended and stays open for a late entry.
  final now = DateTime(2026, 9, 5);

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

  group('a month that has not ENDED — including the live one', () {
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

    test('the LIVE month is not yet ratable — the reported defect', () {
      // The predecessor, isFutureMonth, asked "has this month started" and so
      // answered false for September on 9 September, leaving its Self cell
      // open and writable.
      expect(isNotYetRatableMonth(september, now), isTrue,
          reason: 'September is still running on 5 September');
      expect(isNotYetRatableMonth(august, now), isFalse,
          reason: 'August has ended, so it is the month under review');
      expect(isNotYetRatableMonth(july, now), isFalse,
          reason: 'an older month stays open for a late entry');
      // Across a year boundary.
      expect(isNotYetRatableMonth(const ReviewPeriod(2027, 1), now), isTrue);
      expect(isNotYetRatableMonth(const ReviewPeriod(2025, 12), now), isFalse);
    });

    test('the employee cannot self-rate the live month either', () {
      // Self-rating is otherwise unconditional once a month is open, so this
      // is the single assertion that stops a score being persisted against a
      // month that has not finished.
      expect(open(ReviewStage.selfRating, row(), september), isFalse);
      expect(
          open(ReviewStage.selfRating, row(selfValue: 90), september), isFalse);
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
