import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/review_flow.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/presentation/providers/monthly_review_providers.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// The quarterly sheet's rating gate, under both pipelines.
///
/// `review_flow_test.dart` pins the RULES; this pins that the sheet actually
/// consults them — and, more importantly, that a scope on the standard flow
/// behaves exactly as it did before flows existed.
void main() {
  ReviewScope scopeFor(
    UserRole role, {
    ReviewFlow flow = ReviewFlow.standard,
    String userId = 'u1',
  }) =>
      ReviewScope(
        userId: userId,
        userName: 'A',
        role: role,
        roles: {role},
        reviewFlow: flow,
      );

  MonthlyReview reviewFor({
    ReviewStage stage = ReviewStage.selfRating,
    String employeeId = 'emp1',
    String? managerId = 'mgr1',
  }) =>
      MonthlyReview(
        id: 'r1',
        employeeId: employeeId,
        employeeName: 'Asha',
        managerId: managerId,
        period: const ReviewPeriod(2026, 7),
        currentStage: stage,
      );

  group('a scope with no flow behaves as before', () {
    test('ReviewScope defaults to the standard flow', () {
      // Any scope built without the field — including in older tests — must
      // land on the original pipeline.
      const s = ReviewScope(userId: 'u', userName: 'n', role: UserRole.hr);
      expect(s.reviewFlow, ReviewFlow.standard);
    });
  });

  group('standard flow — unchanged behaviour', () {
    test('HR can rate the HR seat', () {
      expect(
        canRateReviewStage(
            ReviewStage.accountHrRating, scopeFor(UserRole.hr), reviewFor()),
        isTrue,
      );
    });

    test('Accounts can rate the Finance seat', () {
      expect(
        canRateReviewStage(
            ReviewStage.financeRating, scopeFor(UserRole.finance), reviewFor()),
        isTrue,
      );
    });

    test('an employee cannot rate the HR seat', () {
      expect(
        canRateReviewStage(ReviewStage.accountHrRating,
            scopeFor(UserRole.employee), reviewFor()),
        isFalse,
      );
    });

    test('a completed month is refused regardless of flow or role', () {
      // The lock check still comes first — this is the RES_002 guard.
      for (final flow in ReviewFlow.values) {
        expect(
          canRateReviewStage(
            ReviewStage.accountHrRating,
            scopeFor(UserRole.hr, flow: flow),
            reviewFor(stage: ReviewStage.completed),
          ),
          isFalse,
          reason: flow.name,
        );
      }
    });

    test('a null scope is refused', () {
      expect(
        canRateReviewStage(ReviewStage.accountHrRating, null, reviewFor()),
        isFalse,
      );
    });
  });

  group('admin-only flow — the stages it removes', () {
    test('Accounts KEEPS its seat', () {
      // It was briefly removed, which stranded every Accounts-assigned KRA
      // with no eligible rater.
      expect(
        canRateReviewStage(
          ReviewStage.financeRating,
          scopeFor(UserRole.finance, flow: ReviewFlow.adminOnly),
          reviewFor(),
        ),
        isTrue,
      );
    });

    test('HR keeps its seat', () {
      expect(
        canRateReviewStage(
          ReviewStage.accountHrRating,
          scopeFor(UserRole.hr, flow: ReviewFlow.adminOnly),
          reviewFor(),
        ),
        isTrue,
      );
    });

    test('management keeps the sign-off; an employee never gets it', () {
      expect(
        canRateReviewStage(
          ReviewStage.managementReview,
          scopeFor(UserRole.management, flow: ReviewFlow.adminOnly),
          reviewFor(),
        ),
        isTrue,
      );
      expect(
        canRateReviewStage(
          ReviewStage.managementReview,
          scopeFor(UserRole.employee, flow: ReviewFlow.adminOnly),
          reviewFor(),
        ),
        isFalse,
      );
    });

    test('a super admin can act on both remaining seats', () {
      for (final stage in [
        ReviewStage.accountHrRating,
        ReviewStage.managementReview,
      ]) {
        expect(
          canRateReviewStage(
            stage,
            scopeFor(UserRole.superAdmin, flow: ReviewFlow.adminOnly),
            reviewFor(),
          ),
          isTrue,
          reason: stage.name,
        );
      }
    });

    test('the self-rating admits nobody at all', () {
      for (final role in UserRole.values) {
        expect(
          canRateReviewStage(
            ReviewStage.selfRating,
            scopeFor(role, flow: ReviewFlow.adminOnly),
            reviewFor(),
          ),
          isFalse,
          reason: role.name,
        );
      }
    });

    test('the manager stage admits MANAGEMENT — it is the remainder seat', () {
      // Removing it stranded every manager-assigned and unassigned KRA. It is
      // reassigned instead: management rates whatever HR and Accounts were not
      // given.
      expect(
        canRateReviewStage(
          ReviewStage.reportingManagerRating,
          scopeFor(UserRole.management, flow: ReviewFlow.adminOnly),
          reviewFor(),
        ),
        isTrue,
      );
    });

    test('and admits nobody outside the management tier', () {
      for (final role in [
        UserRole.employee,
        UserRole.manager,
        UserRole.hr,
        UserRole.finance,
        UserRole.ops,
      ]) {
        expect(
          canRateReviewStage(
            ReviewStage.reportingManagerRating,
            scopeFor(role, flow: ReviewFlow.adminOnly),
            reviewFor(),
          ),
          isFalse,
          reason: role.name,
        );
      }
    });

    test('the manager seat does NOT depend on being that manager', () {
      // On the standard pipeline this stage is relationship-gated, so the
      // sheet asks "are you this review's manager?". Under admin-only it is
      // role-gated, so a management user with no relationship to this employee
      // must still be allowed — asking the relationship there was what locked
      // out the only people the flow grants it to.
      expect(
        canRateReviewStage(
          ReviewStage.reportingManagerRating,
          scopeFor(UserRole.management, flow: ReviewFlow.adminOnly),
          reviewFor(managerId: 'someone-else'),
        ),
        isTrue,
      );
    });
  });
}
