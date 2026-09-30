import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// An unfinished self-rating stays open to its owner after the window closes.
///
/// The window rule was written to stop September's rater going back and
/// REWRITING July. Filling a blank is not rewriting — so a KRA with no self
/// score reopens, and a KRA that already carries one does not. That distinction
/// is the whole design: a closed month can be completed, never revised.
///
/// It matters at scale. Across the roster, July and August self-ratings were
/// left part-finished when their windows shut, and nothing in the app could
/// reopen them — while the scores never entered count as zero against the
/// incentive. Keyed on the ACTUAL score, never on the stage cursor, which on
/// this data runs to MANAGEMENT_REVIEW and beyond with an empty self column
/// behind it.
void main() {
  const july = ReviewPeriod(2026, 7);
  const august = ReviewPeriod(2026, 8);
  const september = ReviewPeriod(2026, 9);

  // End of September: August is the open month, July closed a month ago.
  final now = DateTime(2026, 9, 30);

  MonthlyKraRow row({double? selfValue}) {
    var r = const MonthlyKraRow(
      id: 'k1',
      name: 'Safety of the Facility',
      weightagePercent: 100,
      maxScore: 10,
      reviewerGroup: KraReviewer.reportingManager,
      displayOrder: 1,
    );
    if (selfValue != null) {
      r = r.withStageScore(ReviewStage.selfRating, RowScore(value: selfValue));
    }
    return r;
  }

  bool open(ReviewStage stage, ReviewPeriod month, {double? selfValue}) =>
      isCellOpenForEntry(
        stage: stage,
        row: row(selfValue: selfValue),
        month: month,
        now: now,
      );

  group('July, whose window closed a month ago', () {
    test('an UNRATED KRA reopens to its owner', () {
      expect(open(ReviewStage.selfRating, july, selfValue: null), isTrue);
    });

    test('a KRA already rated stays shut — no revising', () {
      // "Whichever employees are done, leave them as is", per KRA.
      expect(open(ReviewStage.selfRating, july, selfValue: 8), isFalse);
    });

    test('a zero counts as rated, not as missing', () {
      // 0 is a real rating. Treating it as absent would reopen a finished KRA
      // and let it be quietly changed.
      expect(open(ReviewStage.selfRating, july, selfValue: 0), isFalse);
    });

    test('and this opens the SELF stage only', () {
      // The employee gets to finish their own column. It is not licence for
      // reviewers to rate a closed month.
      for (final stage in [
        ReviewStage.reportingManagerRating,
        ReviewStage.accountHrRating,
        ReviewStage.financeRating,
      ]) {
        expect(open(stage, july, selfValue: null), isFalse, reason: '$stage');
      }
    });
  });

  group('August, the open month', () {
    test('behaves as before — rated or not, the owner may edit', () {
      expect(open(ReviewStage.selfRating, august, selfValue: null), isTrue);
      expect(open(ReviewStage.selfRating, august, selfValue: 8), isTrue);
    });
  });

  group('a month that has not ENDED is still shut', () {
    test('September does not open, however empty', () {
      // Half of why the window exists: a score for an unfinished month can be
      // submitted and advance the review irreversibly.
      expect(open(ReviewStage.selfRating, september, selfValue: null), isFalse);
    });

    test('nor anything further ahead', () {
      expect(
        open(ReviewStage.selfRating, const ReviewPeriod(2026, 12),
            selfValue: null),
        isFalse,
      );
    });
  });

  group('older months than July', () {
    test('an unfinished June reopens too', () {
      // The rule is about the score, not the calendar. A fix naming July and
      // August would strand September the moment its own window shuts.
      expect(
        open(ReviewStage.selfRating, const ReviewPeriod(2026, 6),
            selfValue: null),
        isTrue,
      );
      expect(
        open(ReviewStage.selfRating, const ReviewPeriod(2026, 6), selfValue: 7),
        isFalse,
      );
    });
  });

  group('a partly-rated month opens exactly its gaps', () {
    test('the rated KRA is shut and the unrated one is open, same month', () {
      // Dinesh's July was 1 of 12. This is the shape that matters: eleven
      // cells open, the finished one protected.
      final rated = isCellOpenForEntry(
        stage: ReviewStage.selfRating,
        row: row(selfValue: 100),
        month: july,
        now: now,
      );
      final unrated = isCellOpenForEntry(
        stage: ReviewStage.selfRating,
        row: row(selfValue: null),
        month: july,
        now: now,
      );
      expect(rated, isFalse);
      expect(unrated, isTrue);
    });
  });

  test('management sign-off is unchanged by any of this', () {
    expect(open(ReviewStage.managementReview, july, selfValue: 8), isTrue);
    expect(
        open(ReviewStage.managementReview, september, selfValue: 8), isFalse);
  });
}
