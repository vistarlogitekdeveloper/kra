import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// A self-rating handed back for rework reopens its month.
///
/// Sending a rating back was a dead letter. Nothing but the notice consulted
/// `selfRatingReturned` — no edit gate did — so the employee was shown "your
/// rating was returned, please revise it" over a sheet they could not type
/// into. The month being questioned is, by definition, one they had already
/// submitted, and by the time anyone reads the notice its window has closed.
///
/// A return is an explicit, audited grant of permission from the one person
/// entitled to give it. That is exactly what the blanket window rule cannot
/// express, and why the exception belongs to the returned month alone rather
/// than to July, or to everybody.
void main() {
  const july = ReviewPeriod(2026, 7);
  const august = ReviewPeriod(2026, 8);
  const september = ReviewPeriod(2026, 9);

  // End of September: August is the open month, July closed a month ago.
  final now = DateTime(2026, 9, 30);

  MonthlyKraRow row({double? selfValue = 8}) {
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

  bool open(
    ReviewStage stage,
    ReviewPeriod month, {
    bool returned = false,
    double? selfValue = 8,
  }) =>
      isCellOpenForEntry(
        stage: stage,
        row: row(selfValue: selfValue),
        month: month,
        now: now,
        returnedForRework: returned,
      );

  group('July, whose window closed a month ago', () {
    test('stays shut when nothing was returned', () {
      expect(open(ReviewStage.selfRating, july), isFalse);
    });

    test('opens to the employee once it is handed back', () {
      expect(open(ReviewStage.selfRating, july, returned: true), isTrue);
    });

    test('but a return reopens the SELF stage only', () {
      // The manager asked the employee to revise. It is not licence for the
      // reviewers to re-rate a month whose window has closed.
      for (final stage in [
        ReviewStage.reportingManagerRating,
        ReviewStage.accountHrRating,
        ReviewStage.financeRating,
      ]) {
        expect(open(stage, july, returned: true), isFalse, reason: '$stage');
      }
    });
  });

  group('a month still running is closed whatever happens', () {
    test('September does not open, returned or not', () {
      // The window rule exists partly to stop an unfinished month being
      // submitted and advanced irreversibly. A return must not defeat that.
      expect(open(ReviewStage.selfRating, september), isFalse);
      expect(open(ReviewStage.selfRating, september, returned: true), isFalse);
    });

    test('nor does a month still further ahead', () {
      expect(
        open(ReviewStage.selfRating, const ReviewPeriod(2026, 12),
            returned: true),
        isFalse,
      );
    });
  });

  test('the open month needs no return — nothing changes there', () {
    expect(open(ReviewStage.selfRating, august), isTrue);
    expect(open(ReviewStage.selfRating, august, returned: true), isTrue);
  });

  test('a reopened month is still governed by the per-KRA rules', () {
    // Reopening restores the ability to edit; it does not bypass anything
    // else. Downstream stages still wait on a self score.
    expect(
      open(ReviewStage.reportingManagerRating, august, selfValue: null),
      isFalse,
    );
  });

  group('management sign-off is unaffected by any of this', () {
    test('it reaches closed months on its own terms', () {
      expect(open(ReviewStage.managementReview, july), isTrue);
      expect(open(ReviewStage.managementReview, july, returned: true), isTrue);
    });

    test('and still stops at a month that has not ended', () {
      expect(open(ReviewStage.managementReview, september), isFalse);
    });
  });
}
