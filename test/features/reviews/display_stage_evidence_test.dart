import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/reviews/data/models/incentive_snapshot.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review_summary.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/stage_status.dart';

/// A stage may be SHOWN as reached only when the evidence reaches it.
///
/// Reported as: "it is showing the wrong stage — even the second stage review
/// is pending and it is showing completed."
///
/// The cursor cannot be trusted on its own. It advances off whatever is scored
/// and is also set outright by mark-paid, so reviews sit at COMPLETED carrying
/// nothing but a self-rating. The old test was "past Self-Rating AND something
/// is scored" — one self score satisfied it, and every later claim rode through
/// unchecked.
///
/// The cursor may sit exactly ONE stage beyond the evidence, because a stage is
/// "current" while it AWAITS action: its own scores do not exist yet, and that
/// is the normal state for the stage in hand.
void main() {
  MonthlyReviewSummary summary({
    required ReviewStage stage,
    StageStatus status = StageStatus.inProgress,
    double? selfScorePct,
    double? managementReviewPct,
    double finalScorePct = 0,
    PayoutStatus payoutStatus = PayoutStatus.pending,
  }) =>
      MonthlyReviewSummary(
        id: 'r1',
        employeeId: 'emp1',
        employeeName: 'Dinesh',
        employeeCode: 'VLPL0156',
        year: 2026,
        month: 8,
        monthLabel: 'August 2026',
        currentStage: stage,
        currentStageStatus: status,
        finalScorePct: finalScorePct,
        payoutStatus: payoutStatus,
        selfScorePct: selfScorePct,
        managementReviewPct: managementReviewPct,
      );

  group('a cursor past the evidence is capped', () {
    test('COMPLETED on a self-rating alone shows the REVIEW stage pending', () {
      // The reported case. Stage 2 has not happened, so Completed is a claim
      // nothing supports — and the honest answer names who is holding it.
      final s = summary(
        stage: ReviewStage.completed,
        status: StageStatus.submitted,
        selfScorePct: 80,
      );

      expect(s.displayStage, ReviewStage.reportingManagerRating);
      expect(s.displayStatus, StageStatus.inProgress,
          reason: 'the shown stage is the one still awaiting work');
    });

    test('MANAGEMENT_REVIEW on a self-rating alone is capped the same way', () {
      // Same corruption, one stage earlier — the cursor auto-advances off
      // whatever is scored, so this is the commoner shape.
      final s = summary(
        stage: ReviewStage.managementReview,
        selfScorePct: 80,
      );

      expect(s.displayStage, ReviewStage.reportingManagerRating);
    });

    test('INCENTIVE_PAYOUT on a self-rating alone is capped too', () {
      expect(
        summary(stage: ReviewStage.incentivePayout, selfScorePct: 80)
            .displayStage,
        ReviewStage.reportingManagerRating,
      );
    });

    test('nothing scored at all falls all the way back to Self-Rating', () {
      expect(
        summary(stage: ReviewStage.completed, status: StageStatus.submitted)
            .displayStage,
        ReviewStage.selfRating,
      );
    });
  });

  group('the cursor is allowed ONE stage beyond the evidence', () {
    test('awaiting the manager, with only a self score, is a real state', () {
      // The stage in hand has no scores yet BY DEFINITION. Capping to the
      // evidence itself would park every review one stage behind the truth.
      final s = summary(
        stage: ReviewStage.reportingManagerRating,
        selfScorePct: 80,
      );

      expect(s.displayStage, ReviewStage.reportingManagerRating);
    });

    test('awaiting payout, with the Review phase scored, is a real state', () {
      final s = summary(
        stage: ReviewStage.incentivePayout,
        selfScorePct: 80,
        managementReviewPct: 88,
      );

      expect(s.displayStage, ReviewStage.incentivePayout);
    });
  });

  group('what the cap must NOT break', () {
    test('a partial Review average never promotes the cursor', () {
      // managementReviewPct carries the Review AVERAGE when management has not
      // overridden, so it cannot prove sign-off. Reading it as proof would bump
      // a review still mid-stage-2 to Management Review.
      final s = summary(
        stage: ReviewStage.reportingManagerRating,
        selfScorePct: 80,
        managementReviewPct: 88,
      );

      expect(s.displayStage, ReviewStage.reportingManagerRating);
      expect(s.displayStatus, StageStatus.inProgress);
    });

    test('a frozen Self-Rating cursor is still repaired upward', () {
      // An in-place save-scores does not advance the cursor, so a review that
      // HAS been reviewed can still read Self-Rating. That repair predates the
      // cap and must survive it.
      final s = summary(
        stage: ReviewStage.selfRating,
        selfScorePct: 80,
        managementReviewPct: 88,
      );

      expect(s.displayStage, ReviewStage.managementReview);
    });

    test('a paid review with a score still reads Completed', () {
      final s = summary(
        stage: ReviewStage.selfRating,
        payoutStatus: PayoutStatus.paid,
        selfScorePct: 80,
        finalScorePct: 76,
      );

      expect(s.displayStage, ReviewStage.completed);
      expect(s.displayStatus, StageStatus.submitted);
    });

    test('a genuine zero is evidence, not absence', () {
      // 0 is a real assessment. Treating it as unrated would cap a finished
      // review back to the start.
      final s = summary(
        stage: ReviewStage.managementReview,
        selfScorePct: 0,
        managementReviewPct: 0,
      );

      expect(s.displayStage, ReviewStage.managementReview);
    });
  });
}
