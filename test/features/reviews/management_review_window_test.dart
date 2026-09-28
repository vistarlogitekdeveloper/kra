import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// Management sign-off is not bound to the one-month entry window.
///
/// The window exists so that rating August cannot reopen July — it protects the
/// scores that feed the result. Sign-off enters no such score: it approves what
/// is already there, and it is the last gate before payout. Binding it to the
/// same window meant a review whose window closed unsigned could never be
/// completed by anyone.
///
/// July was in exactly that state. Its window shut on 31 August with management
/// still to act, so every employee's July sat finished-but-unsigned with no
/// route forward — which is what this change unblocks.
void main() {
  const july = ReviewPeriod(2026, 7);
  const august = ReviewPeriod(2026, 8);
  const september = ReviewPeriod(2026, 9);

  // Late September: August is the open month, July closed a month ago, and
  // September has not ended.
  final now = DateTime(2026, 9, 28);

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

  bool open(ReviewStage stage, ReviewPeriod month, {double? selfValue = 8}) =>
      isCellOpenForEntry(
        stage: stage,
        row: row(selfValue: selfValue),
        month: month,
        now: now,
      );

  group('July, whose window has closed', () {
    test('management may sign it off — the case this unblocks', () {
      expect(open(ReviewStage.managementReview, july), isTrue);
    });

    test('but nobody may still RATE it', () {
      // The "do not rewrite July" rule stays exactly where it was.
      for (final stage in [
        ReviewStage.selfRating,
        ReviewStage.reportingManagerRating,
        ReviewStage.accountHrRating,
        ReviewStage.financeRating,
      ]) {
        expect(open(stage, july), isFalse, reason: '$stage');
      }
    });
  });

  group('the open month is unaffected', () {
    test('August stays open to every stage', () {
      for (final stage in [
        ReviewStage.selfRating,
        ReviewStage.reportingManagerRating,
        ReviewStage.accountHrRating,
        ReviewStage.financeRating,
        ReviewStage.managementReview,
      ]) {
        expect(open(stage, august), isTrue, reason: '$stage');
      }
    });
  });

  group('a month that has not ENDED is still closed to everyone', () {
    test('including management — nothing is signed off mid-month', () {
      // The exemption widens the window backwards, never forwards. Signing off
      // a month still running would approve a score that can still change.
      expect(open(ReviewStage.managementReview, september), isFalse);
      expect(open(ReviewStage.selfRating, september), isFalse);
    });

    test('and a month beyond that too', () {
      expect(
        open(ReviewStage.managementReview, const ReviewPeriod(2026, 12)),
        isFalse,
      );
    });
  });

  group('older months, not just July', () {
    test('management can reach any month that has ended', () {
      // A per-month fix would strand August the moment September closes. The
      // rule has to be general or the same dead end returns every month.
      for (final month in [
        const ReviewPeriod(2026, 4),
        const ReviewPeriod(2026, 5),
        const ReviewPeriod(2026, 6),
        july,
        august,
      ]) {
        expect(open(ReviewStage.managementReview, month), isTrue,
            reason: '${month.shortLabel}');
      }
    });
  });

  test('sign-off still needs the KRA to have been self-rated', () {
    // The per-KRA prerequisite is untouched: management approves a score, so
    // there has to be one. An unrated KRA stays closed even in July.
    expect(open(ReviewStage.managementReview, july, selfValue: null), isFalse);
    expect(
        open(ReviewStage.managementReview, august, selfValue: null), isFalse);
  });
}
