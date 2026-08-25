import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';
import 'package:vistar_app/features/reviews/data/models/incentive_snapshot.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/presentation/providers/monthly_review_providers.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// Guards the ROLE-gated Review cells (the HR rater and the Accounts rater)
/// against disagreeing with the badges.
///
/// Found while moving one employee's "Cost optimization" KRA from the reporting
/// manager to Accounts. The dashboards resolve "who must act" through
/// [ReviewStage.actorRoles], where FINANCE_RATING is `{finance, hrAdmin}` —
/// deliberately, because the commercial/HR-admin post covers the Accounts seat
/// and a single role can't say "HR Admin AND Accounts". The sheet's edit gate
/// instead tested `scope.role == UserRole.finance`. So reassigning a KRA to
/// Accounts would have told that HR-admin the KRA needed their action and then
/// handed them a read-only cell — the KRA ratable by nobody.
void main() {
  MonthlyReview reviewWith({
    ReviewStage currentStage = ReviewStage.selfRating,
    KraReviewer reviewer = KraReviewer.accounts,
  }) =>
      MonthlyReview(
        id: 'r1',
        employeeId: 'emp1',
        employeeName: 'Dattatray',
        managerId: 'mgr1',
        period: const ReviewPeriod(2026, 9),
        currentStage: currentStage,
        rows: [
          MonthlyKraRow(
            id: 'k5',
            name: 'Cost optimization',
            weightagePercent: 5,
            maxScore: 100,
            reviewerGroup: reviewer,
            displayOrder: 5,
          ),
        ],
        incentive: const IncentiveSnapshot(),
      );

  ReviewScope scopeOf(UserRole primary, {Set<UserRole> roles = const {}}) =>
      ReviewScope(
        userId: 'u1',
        userName: 'Sagar Sasane',
        role: primary,
        roles: roles,
      );

  group('the Accounts rater', () {
    test('an HR-admin holds the Accounts seat, so the cell is editable', () {
      // The case that would otherwise strand the KRA: Sagar is HR_ADMIN on the
      // server (there is no "HR Admin AND Accounts" role), and FINANCE_RATING
      // names hrAdmin as an actor.
      expect(
        canRateReviewStage(
            ReviewStage.financeRating, scopeOf(UserRole.hrAdmin), reviewWith()),
        isTrue,
      );
    });

    test('a literal FINANCE role can rate it too', () {
      expect(
        canRateReviewStage(
            ReviewStage.financeRating, scopeOf(UserRole.finance), reviewWith()),
        isTrue,
      );
    });

    test('a plain manager or employee cannot', () {
      for (final role in [
        UserRole.manager,
        UserRole.employee,
        UserRole.ops,
        UserRole.warehouseMgr,
      ]) {
        expect(
          canRateReviewStage(
              ReviewStage.financeRating, scopeOf(role), reviewWith()),
          isFalse,
          reason: '$role',
        );
      }
    });
  });

  group('the whole role set is honoured, not just the primary', () {
    test('a secondary Accounts seat is enough', () {
      // Primary role drives roster scoping; AUTHORITY comes from the full set.
      final scope = scopeOf(UserRole.manager, roles: {
        UserRole.manager,
        UserRole.finance,
      });
      expect(
        canRateReviewStage(ReviewStage.financeRating, scope, reviewWith()),
        isTrue,
      );
    });

    test('a secondary HR seat is enough for the HR rater', () {
      final scope = scopeOf(UserRole.manager, roles: {
        UserRole.manager,
        UserRole.hr,
      });
      expect(
        canRateReviewStage(ReviewStage.accountHrRating, scope, reviewWith()),
        isTrue,
      );
    });

    test('a role set without either seat still cannot rate', () {
      final scope = scopeOf(UserRole.manager, roles: {
        UserRole.manager,
        UserRole.employee,
      });
      expect(
        canRateReviewStage(ReviewStage.financeRating, scope, reviewWith()),
        isFalse,
      );
    });
  });

  group('gate and badge can no longer disagree', () {
    // Whatever actorRoles says about a stage, the edit gate must agree — that
    // equivalence is the whole point of routing both through actorRoles.
    for (final stage in [
      ReviewStage.accountHrRating,
      ReviewStage.financeRating,
    ]) {
      test('${stage.label} matches actorRoles for every role', () {
        for (final role in UserRole.values) {
          expect(
            canRateReviewStage(stage, scopeOf(role), reviewWith()),
            stage.isActionableByAny({role}),
            reason: '${stage.label} / $role',
          );
        }
      });
    }
  });

  test('a completed month is nobody\'s to edit, whatever the role', () {
    expect(
      canRateReviewStage(
        ReviewStage.financeRating,
        scopeOf(UserRole.finance),
        reviewWith(currentStage: ReviewStage.completed),
      ),
      isFalse,
    );
  });

  test('no signed-in scope means no edit', () {
    expect(
      canRateReviewStage(ReviewStage.financeRating, null, reviewWith()),
      isFalse,
    );
  });
}
