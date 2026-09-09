import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/constants/feature_flags.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';

void main() {
  group('ReviewStage pipeline', () {
    test('advances in the fixed order, terminating at completed', () {
      // Self → the three parallel Review raters (RM, HR, Finance) → management
      // → payout → completed. The raters are entered in parallel in practice;
      // this linear `next` only drives the formal cursor.
      expect(ReviewStage.selfRating.next, ReviewStage.reportingManagerRating);
      expect(
          ReviewStage.reportingManagerRating.next, ReviewStage.accountHrRating);
      expect(ReviewStage.accountHrRating.next, ReviewStage.financeRating);
      expect(ReviewStage.financeRating.next, ReviewStage.managementReview);
      expect(ReviewStage.managementReview.next, ReviewStage.incentivePayout);
      expect(ReviewStage.incentivePayout.next, ReviewStage.completed);
      expect(ReviewStage.completed.next, ReviewStage.completed);
      expect(ReviewStage.completed.isTerminal, isTrue);
    });

    test('carries the right deadline day per stage', () {
      expect(ReviewStage.selfRating.deadlineDay, 10);
      // The three Review raters share the same deadline (they run in parallel).
      expect(ReviewStage.reportingManagerRating.deadlineDay, 13);
      expect(ReviewStage.accountHrRating.deadlineDay, 13);
      expect(ReviewStage.financeRating.deadlineDay, 13);
      expect(ReviewStage.managementReview.deadlineDay, 15);
      expect(ReviewStage.incentivePayout.deadlineDay, 20);
      expect(ReviewStage.completed.deadlineDay, isNull);
    });

    test('self, the three Review raters and management are rating stages', () {
      expect(ReviewStage.selfRating.isRatingStage, isTrue);
      expect(ReviewStage.reportingManagerRating.isRatingStage, isTrue);
      expect(ReviewStage.accountHrRating.isRatingStage, isTrue);
      expect(ReviewStage.financeRating.isRatingStage, isTrue);
      // Management's rework override is a per-KRA score too.
      expect(ReviewStage.managementReview.isRatingStage, isTrue);
      expect(ReviewStage.incentivePayout.isRatingStage, isFalse);
      expect(ReviewStage.completed.isRatingStage, isFalse);
    });

    test('the Review cycle is exactly RM + HR + Finance', () {
      expect(ReviewStage.reviewRaters, {
        ReviewStage.reportingManagerRating,
        ReviewStage.accountHrRating,
        ReviewStage.financeRating,
      });
      expect(ReviewStage.reportingManagerRating.isReviewRater, isTrue);
      expect(ReviewStage.accountHrRating.isReviewRater, isTrue);
      expect(ReviewStage.financeRating.isReviewRater, isTrue);
      expect(ReviewStage.selfRating.isReviewRater, isFalse);
      expect(ReviewStage.managementReview.isReviewRater, isFalse);
    });

    test('phaseLabel collapses the three raters into a single "Review"', () {
      // The dashboard badge shows the conceptual phase, not the individual
      // rater who is furthest along.
      expect(ReviewStage.selfRating.phaseLabel, 'Self-Rating');
      expect(ReviewStage.reportingManagerRating.phaseLabel, 'Review');
      expect(ReviewStage.accountHrRating.phaseLabel, 'Review');
      expect(ReviewStage.financeRating.phaseLabel, 'Review');
      expect(ReviewStage.managementReview.phaseLabel, 'Management Review');
      expect(ReviewStage.incentivePayout.phaseLabel, 'Incentive Payout');
      expect(ReviewStage.completed.phaseLabel, 'Completed');
    });

    test('actor roles match the agreed stage→role mapping', () {
      // HR is its own Review rater now (Finance is a SEPARATE rater), so the
      // HR stage is HR / HR_ADMIN only.
      expect(ReviewStage.accountHrRating.actorRoles,
          containsAll([UserRole.hr, UserRole.hrAdmin]));
      expect(ReviewStage.accountHrRating.actorRoles,
          isNot(contains(UserRole.finance)));
      // Finance is the third Review rater — and HR_ADMIN holds that Accounts
      // seat too, since one UserRole can't say "HR Admin AND Accounts".
      expect(ReviewStage.financeRating.actorRoles,
          containsAll([UserRole.finance, UserRole.hrAdmin]));
      expect(ReviewStage.incentivePayout.actorRoles,
          containsAll([UserRole.finance, UserRole.hr, UserRole.hrAdmin]));
      // Any manager-tier role gets a team roster, so all of them can rate.
      expect(
          ReviewStage.reportingManagerRating.actorRoles,
          containsAll([
            UserRole.manager,
            UserRole.bdManager,
            UserRole.warehouseMgr,
          ]));
      // Management sign-off belongs to the management tier. HR_ADMIN shares it
      // ONLY while the backend cannot store MANAGEMENT — gating on a role
      // nobody can hold would leave the stage with no actor at all.
      expect(ReviewStage.managementReview.actorRoles,
          contains(UserRole.management));
      expect(
        ReviewStage.managementReview.actorRoles.contains(UserRole.hrAdmin),
        !FeatureFlags.roleTiers,
        reason: 'HR must lose the sign-off seat once MANAGEMENT is assignable',
      );
      // A reporting manager never gets management review, whatever happens.
      expect(ReviewStage.managementReview.actorRoles,
          isNot(contains(UserRole.manager)));
      // Self-rating is owner-scoped; ops holds its own review too.
      expect(ReviewStage.selfRating.actorRoles,
          containsAll([UserRole.employee, UserRole.ops]));
    });

    test('fromApi tolerates snake/camel/aliases/unknown', () {
      expect(ReviewStage.fromApi('ACCOUNT_HR_RATING'),
          ReviewStage.accountHrRating);
      expect(ReviewStage.fromApi('HR_RATING'), ReviewStage.accountHrRating);
      expect(ReviewStage.fromApi('FINANCE_RATING'), ReviewStage.financeRating);
      expect(ReviewStage.fromApi('ACCOUNTS_RATING'), ReviewStage.financeRating);
      expect(ReviewStage.fromApi('reportingManagerRating'),
          ReviewStage.reportingManagerRating);
      expect(
          ReviewStage.fromApi('INCENTIVE-PAYOUT'), ReviewStage.incentivePayout);
      expect(ReviewStage.fromApi(null), ReviewStage.selfRating);
      expect(ReviewStage.fromApi('garbage'), ReviewStage.selfRating);
    });
  });
}
