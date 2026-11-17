import 'package:flutter_test/flutter_test.dart';
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
      // Payout is Accounts + HR admin (+ super admin), matching the server's
      // ACTOR_ROLES.INCENTIVE_PAYOUT. Plain HR is review-only and is refused
      // there, so listing it here only bought a button that 403s.
      expect(ReviewStage.incentivePayout.actorRoles,
          containsAll([UserRole.finance, UserRole.hrAdmin]));
      expect(
          ReviewStage.incentivePayout.actorRoles, isNot(contains(UserRole.hr)));
      // Any manager-tier role gets a team roster, so all of them can rate.
      expect(
          ReviewStage.reportingManagerRating.actorRoles,
          containsAll([
            UserRole.manager,
            UserRole.bdManager,
            UserRole.warehouseMgr,
          ]));
      // Management sign-off belongs to MANAGEMENT alone (and SUPER_ADMIN).
      // HR_ADMIN lost it in November 2026: the server refuses a plain HR
      // admin, and the people who sign off hold Management as an extra role.
      expect(ReviewStage.managementReview.actorRoles,
          {UserRole.management, UserRole.superAdmin});
      expect(
        ReviewStage.managementReview.actorRoles.contains(UserRole.hrAdmin),
        isFalse,
        reason: 'HR must not sign off the incentive it feeds',
      );
      // The real holders: HR admins with Management as an EXTRA role. The
      // multi-role check counts it; an HR admin without it is refused.
      expect(
        ReviewStage.managementReview
            .isActionableByAny({UserRole.hrAdmin, UserRole.management}),
        isTrue,
      );
      expect(ReviewStage.managementReview.isActionableByAny({UserRole.hrAdmin}),
          isFalse);
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
