import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/core/enums/review_flow.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_flow.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// The COMPOSED gate — the one that was actually broken.
///
/// Rating a cell needs BOTH "are you the right person?" (canRateReviewStage)
/// and "is this cell open yet?" (isCellOpenForEntry). The earlier tests checked
/// each in isolation and both passed, while the composition returned false for
/// everybody under the admin-only flow: `isCellOpenForEntry` required a self
/// score before any other rater could enter one, and that flow deletes the
/// self-rating, so no cell in the sheet was ever open — HR, Accounts and
/// management included.
///
/// A rule that passes alone and fails in composition is the whole reason these
/// exist.
void main() {
  // August, so JULY below is the month whose window is open. It used to be
  // November with the comment "after the quarter, so nothing is future" —
  // true, but no longer sufficient: a month that has ended is now read-only
  // unless it is THE open one, and in November that is October.
  final now = DateTime(2026, 8, 3);
  const month = ReviewPeriod(2026, 7);

  MonthlyKraRow rowFor({
    KraReviewer reviewer = KraReviewer.hr,
    bool selfRated = false,
  }) {
    var r = MonthlyKraRow(
      id: 'k1',
      name: 'Safety of the Facility',
      weightagePercent: 100,
      maxScore: 10,
      reviewerGroup: reviewer,
    );
    if (selfRated) {
      r = r.withStageScore(ReviewStage.selfRating, const RowScore(value: 8));
    }
    return r;
  }

  group('admin-only: cells must be open without a self-rating', () {
    test('the HR seat is open on a row with NO self score', () {
      // The regression. Under standard this is correctly false — the reviewer
      // waits for the employee. Under admin-only there is nobody to wait for.
      expect(
        isCellOpenForEntry(
          stage: ReviewStage.accountHrRating,
          row: rowFor(selfRated: false),
          month: month,
          now: now,
          flow: ReviewFlow.adminOnly,
        ),
        isTrue,
        reason: 'admin-only has no self-rating, so nothing can gate on one',
      );
    });

    test('the Accounts seat is open too', () {
      expect(
        isCellOpenForEntry(
          stage: ReviewStage.financeRating,
          row: rowFor(reviewer: KraReviewer.accounts),
          month: month,
          now: now,
          flow: ReviewFlow.adminOnly,
        ),
        isTrue,
      );
    });

    test('so does the management sign-off', () {
      expect(
        isCellOpenForEntry(
          stage: ReviewStage.managementReview,
          row: rowFor(),
          month: month,
          now: now,
          flow: ReviewFlow.adminOnly,
        ),
        isTrue,
      );
    });

    test('a FUTURE month is still closed — the flow does not override that',
        () {
      expect(
        isCellOpenForEntry(
          stage: ReviewStage.accountHrRating,
          row: rowFor(),
          month: const ReviewPeriod(2027, 6),
          now: now,
          flow: ReviewFlow.adminOnly,
        ),
        isFalse,
      );
    });
  });

  group('standard: the self-first ordering is untouched', () {
    test('a reviewer is CLOSED until the employee has self-rated', () {
      expect(
        isCellOpenForEntry(
          stage: ReviewStage.accountHrRating,
          row: rowFor(selfRated: false),
          month: month,
          now: now,
        ),
        isFalse,
        reason: 'the original rule: reviewers moderate the employee, so they '
            'must not rate first',
      );
    });

    test('and OPEN once they have', () {
      expect(
        isCellOpenForEntry(
          stage: ReviewStage.accountHrRating,
          row: rowFor(selfRated: true),
          month: month,
          now: now,
        ),
        isTrue,
      );
    });

    test('the default flow is standard — an omitted argument changes nothing',
        () {
      // Every pre-existing caller and test omits `flow`; they must keep the
      // original behaviour.
      final closed = isCellOpenForEntry(
        stage: ReviewStage.accountHrRating,
        row: rowFor(selfRated: false),
        month: month,
        now: now,
      );
      final explicit = isCellOpenForEntry(
        stage: ReviewStage.accountHrRating,
        row: rowFor(selfRated: false),
        month: month,
        now: now,
        flow: ReviewFlow.standard,
      );
      expect(closed, explicit);
      expect(closed, isFalse);
    });

    test('self-rating itself is always open in the flow that has it', () {
      expect(
        isCellOpenForEntry(
          stage: ReviewStage.selfRating,
          row: rowFor(selfRated: false),
          month: month,
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('reviewer assignment must land on a stage the flow has', () {
    test('standard falls back to the reporting manager, as it always did', () {
      expect(defaultReviewerFor(ReviewFlow.standard),
          KraReviewer.reportingManager);
    });

    test('admin-only ALSO falls back to the reporting-manager seat', () {
      // It briefly fell back to HR, because the reporting-manager stage had
      // been deleted and an unassigned row would otherwise have had no rater.
      // Now that management holds that seat the historical default is correct
      // again — and it is the better answer: an unassigned KRA belongs to
      // "whatever HR and Accounts were not given", which is precisely
      // management's remainder.
      expect(defaultReviewerFor(ReviewFlow.adminOnly),
          KraReviewer.reportingManager);
      expect(
        actorRolesFor(ReviewStage.reportingManagerRating, ReviewFlow.adminOnly),
        isNotEmpty,
        reason: 'the fallback seat must have a rater',
      );
    });

    test('the fallback is always a stage the flow actually has', () {
      for (final flow in ReviewFlow.values) {
        final reviewer = defaultReviewerFor(flow);
        expect(
          actorRolesFor(stageForReviewer(reviewer), flow),
          isNotEmpty,
          reason: 'the default reviewer for ${flow.name} must be able to rate',
        );
      }
    });

    test('every reviewer group maps to its stage', () {
      expect(stageForReviewer(KraReviewer.reportingManager),
          ReviewStage.reportingManagerRating);
      expect(stageForReviewer(KraReviewer.hr), ReviewStage.accountHrRating);
      expect(stageForReviewer(KraReviewer.accounts), ReviewStage.financeRating);
    });
  });

  group('end-to-end: somebody can rate every row, under both flows', () {
    // The property that actually matters, and the one no earlier test asserted:
    // for each flow, every reviewer group a row can carry must be rateable by
    // SOMEBODY once the fallback has been applied.
    test('no reviewer group is left with an empty actor set', () {
      for (final flow in ReviewFlow.values) {
        for (final group in KraReviewer.values) {
          final stage = stageForReviewer(group);
          final rateable = actorRolesFor(stage, flow).isNotEmpty;
          // A group whose stage the flow removed is remapped by
          // _applyReviewerMap, so what must hold is: either the group's own
          // stage is rateable, or the flow's fallback is.
          final fallbackRateable =
              actorRolesFor(stageForReviewer(defaultReviewerFor(flow)), flow)
                  .isNotEmpty;
          expect(
            rateable || fallbackRateable,
            isTrue,
            reason: '${group.name} under ${flow.name} has no rater at all',
          );
        }
      }
    });
  });
}
