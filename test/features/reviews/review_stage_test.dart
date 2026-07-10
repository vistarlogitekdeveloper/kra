import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';

void main() {
  group('ReviewStage pipeline', () {
    test('advances in the fixed order, terminating at completed', () {
      expect(ReviewStage.selfRating.next, ReviewStage.accountHrRating);
      expect(
          ReviewStage.accountHrRating.next, ReviewStage.reportingManagerRating);
      expect(ReviewStage.reportingManagerRating.next,
          ReviewStage.managementReview);
      expect(ReviewStage.managementReview.next, ReviewStage.incentivePayout);
      expect(ReviewStage.incentivePayout.next, ReviewStage.completed);
      expect(ReviewStage.completed.next, ReviewStage.completed);
      expect(ReviewStage.completed.isTerminal, isTrue);
    });

    test('carries the right deadline day per stage', () {
      expect(ReviewStage.selfRating.deadlineDay, 10);
      expect(ReviewStage.accountHrRating.deadlineDay, 12);
      expect(ReviewStage.reportingManagerRating.deadlineDay, 13);
      expect(ReviewStage.managementReview.deadlineDay, 15);
      expect(ReviewStage.incentivePayout.deadlineDay, 20);
      expect(ReviewStage.completed.deadlineDay, isNull);
    });

    test('only self/account-HR/manager are rating stages', () {
      expect(ReviewStage.selfRating.isRatingStage, isTrue);
      expect(ReviewStage.accountHrRating.isRatingStage, isTrue);
      expect(ReviewStage.reportingManagerRating.isRatingStage, isTrue);
      expect(ReviewStage.managementReview.isRatingStage, isFalse);
      expect(ReviewStage.incentivePayout.isRatingStage, isFalse);
    });

    test('actor roles match the agreed stage→role mapping', () {
      // HR_ADMIN is the live HR persona (fromApi maps HR_ADMIN → hrAdmin),
      // so it must be able to act on the account/HR and payout stages or the
      // pipeline stalls there — see docs/BACKEND_HANDOFF.md.
      expect(ReviewStage.accountHrRating.actorRoles,
          containsAll([UserRole.hr, UserRole.hrAdmin, UserRole.finance]));
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
      expect(ReviewStage.managementReview.actorRoles,
          containsAll([UserRole.admin, UserRole.hrAdmin]));
      expect(ReviewStage.managementReview.actorRoles,
          isNot(contains(UserRole.manager)));
      // Self-rating is owner-scoped; ops holds its own review too.
      expect(ReviewStage.selfRating.actorRoles,
          containsAll([UserRole.employee, UserRole.ops]));
    });

    test('fromApi tolerates snake/camel/unknown', () {
      expect(ReviewStage.fromApi('ACCOUNT_HR_RATING'),
          ReviewStage.accountHrRating);
      expect(ReviewStage.fromApi('reportingManagerRating'),
          ReviewStage.reportingManagerRating);
      expect(
          ReviewStage.fromApi('INCENTIVE-PAYOUT'), ReviewStage.incentivePayout);
      expect(ReviewStage.fromApi(null), ReviewStage.selfRating);
      expect(ReviewStage.fromApi('garbage'), ReviewStage.selfRating);
    });
  });
}
