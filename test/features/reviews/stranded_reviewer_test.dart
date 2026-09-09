import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/core/enums/review_flow.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_flow.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// Every KRA must have somebody who can rate it, under every flow.
///
/// This started as a warning: administrators-only deleted the
/// reporting-manager stage, so a KRA assigned to that seat had no rater at all,
/// and the client could not honestly offer one. It could not silently re-point
/// the row either — `writeRowScores` enforces the stored assignment in raw SQL
/// and drops a score aimed elsewhere with no error at all (HTTP 200, zero rows
/// written). So those KRAs were named in a warning panel and the fix was manual
/// reassignment.
///
/// The flow now closes the hole properly: the reporting-manager stage is
/// REASSIGNED to management rather than removed, so management rates whatever
/// HR and Accounts were not assigned. Nothing is stranded any more.
///
/// [kraNamesWithoutRaterInFlow] is kept as the guard on that invariant. It
/// should now find nothing — and these tests fail loudly if a future flow
/// reintroduces a seat with no actor, which is the condition that produced
/// unratable KRAs and silently redistributed their weight.
void main() {
  MonthlyKraRow row(String name, {KraReviewer? assigned}) => MonthlyKraRow(
        id: 'k-$name',
        name: name,
        weightagePercent: 100,
        maxScore: 10,
        reviewerGroup: assigned,
      );

  MonthlyReview reviewWith(List<MonthlyKraRow> rows) => MonthlyReview(
        id: 'r1',
        employeeId: 'emp1',
        employeeName: 'Tanamy',
        managerId: 'mgr1',
        period: const ReviewPeriod(2026, 7),
        currentStage: ReviewStage.selfRating,
        rows: rows,
      );

  group('the invariant: every seat has a rater', () {
    test('NO reviewer group is stranded, under either flow', () {
      // The property that actually matters. Previously false for
      // reportingManager under admin-only — which is what left `qwr`-style
      // KRAs unratable on a real employee's sheet.
      for (final flow in ReviewFlow.values) {
        for (final group in KraReviewer.values) {
          expect(
            actorRolesFor(stageForReviewer(group), flow),
            isNotEmpty,
            reason: '${group.name} has no rater under ${flow.name}',
          );
        }
      }
    });

    test('a manager-assigned KRA is rateable under admin-only', () {
      // The exact row from the reported case: assigned to the reporting
      // manager on an organisation that has since moved to administrators-only.
      expect(
        kraNamesWithoutRaterInFlow(
          [
            reviewWith([row('qwr', assigned: KraReviewer.reportingManager)])
          ],
          ReviewFlow.adminOnly,
        ),
        isEmpty,
        reason: 'management now holds this seat, so nothing is stranded',
      );
    });

    test('and management is who holds it', () {
      expect(
        canActOnStage(ReviewStage.reportingManagerRating, ReviewFlow.adminOnly,
            {UserRole.management}),
        isTrue,
      );
      expect(
        canActOnStage(ReviewStage.reportingManagerRating, ReviewFlow.adminOnly,
            {UserRole.employee}),
        isFalse,
        reason: 'reassigned to a role, not thrown open',
      );
    });

    test('a plain reporting manager LOSES the seat under admin-only', () {
      // The whole point of the flow: rating leaves the reporting line. A line
      // manager holding no other role must not rate, even though the stage
      // still exists and still bears their name internally.
      expect(
        canActOnStage(ReviewStage.reportingManagerRating, ReviewFlow.adminOnly,
            {UserRole.manager}),
        isFalse,
      );
      expect(
        canActOnStage(ReviewStage.reportingManagerRating, ReviewFlow.standard,
            {UserRole.manager}),
        isTrue,
        reason: 'unchanged on the standard pipeline',
      );
    });

    test('HR and Accounts keep exactly their own seats', () {
      expect(
        canActOnStage(
            ReviewStage.accountHrRating, ReviewFlow.adminOnly, {UserRole.hr}),
        isTrue,
      );
      expect(
        canActOnStage(ReviewStage.financeRating, ReviewFlow.adminOnly,
            {UserRole.finance}),
        isTrue,
      );
      // Neither takes over the other's rows, or management's.
      expect(
        canActOnStage(
            ReviewStage.financeRating, ReviewFlow.adminOnly, {UserRole.hr}),
        isFalse,
      );
      expect(
        canActOnStage(ReviewStage.reportingManagerRating, ReviewFlow.adminOnly,
            {UserRole.hr}),
        isFalse,
      );
    });

    test('nothing is stranded on the standard flow either', () {
      for (final assigned in [...KraReviewer.values, null]) {
        expect(
          kraNamesWithoutRaterInFlow(
            [
              reviewWith([row('k', assigned: assigned)])
            ],
            ReviewFlow.standard,
          ),
          isEmpty,
          reason: 'assigned=${assigned?.name ?? 'none'}',
        );
      }
    });

    test('an unassigned KRA is not stranded and needs no remap', () {
      expect(
        kraNamesWithoutRaterInFlow(
          [
            reviewWith([row('unassigned')])
          ],
          ReviewFlow.adminOnly,
        ),
        isEmpty,
      );
      // Unassigned falls to the reporting-manager seat, which under admin-only
      // is management's — so "management rates the remainder" covers the
      // never-assigned rows too, not just the manager-assigned ones.
      expect(defaultReviewerFor(ReviewFlow.adminOnly),
          KraReviewer.reportingManager);
    });

    test('a null month is skipped, not crashed on', () {
      expect(
        kraNamesWithoutRaterInFlow(
          [
            null,
            reviewWith([row('qwr', assigned: KraReviewer.hr)])
          ],
          ReviewFlow.adminOnly,
        ),
        isEmpty,
      );
    });
  });

  group('who is asked WHICH question', () {
    test('the manager seat is a RELATIONSHIP on standard, a ROLE on admin-only',
        () {
      // Getting this backwards is what locks out the right person: asking
      // "are you this employee's manager?" of a management user answers no.
      expect(
          stageIsRelationshipGated(
              ReviewStage.reportingManagerRating, ReviewFlow.standard),
          isTrue);
      expect(
          stageIsRelationshipGated(
              ReviewStage.reportingManagerRating, ReviewFlow.adminOnly),
          isFalse);
    });

    test('self-rating is always the owner, in any flow that has it', () {
      for (final flow in ReviewFlow.values) {
        expect(stageIsRelationshipGated(ReviewStage.selfRating, flow), isTrue,
            reason: flow.name);
      }
    });

    test('the role-gated Review seats are never relationship-gated', () {
      for (final flow in ReviewFlow.values) {
        for (final stage in [
          ReviewStage.accountHrRating,
          ReviewStage.financeRating,
          ReviewStage.managementReview,
        ]) {
          expect(stageIsRelationshipGated(stage, flow), isFalse,
              reason: '${stage.name} / ${flow.name}');
        }
      }
    });
  });

  group('the label must name whoever actually holds the seat', () {
    test('the manager seat reads "Management" under admin-only', () {
      // Printing "Manager" there sent people looking for a rating their line
      // manager is not being asked for.
      expect(
        reviewerShortLabelFor(
            KraReviewer.reportingManager, ReviewFlow.adminOnly),
        'Management',
      );
      expect(
        reviewerCellTagFor(KraReviewer.reportingManager, ReviewFlow.adminOnly),
        'Mgmt',
      );
    });

    test('and still reads "Manager" on the standard pipeline', () {
      expect(
        reviewerShortLabelFor(
            KraReviewer.reportingManager, ReviewFlow.standard),
        'Manager',
      );
      expect(
        reviewerCellTagFor(KraReviewer.reportingManager, ReviewFlow.standard),
        'Mgr',
      );
    });

    test('HR and Accounts are named the same in both flows', () {
      for (final flow in ReviewFlow.values) {
        expect(reviewerShortLabelFor(KraReviewer.hr, flow), 'HR');
        expect(reviewerShortLabelFor(KraReviewer.accounts, flow), 'Accounts');
      }
    });
  });

  group('the flow badge exists so this is diagnosable at a glance', () {
    test('every flow has a display name and a description to show', () {
      for (final flow in ReviewFlow.values) {
        expect(flow.displayName.trim(), isNotEmpty, reason: flow.name);
        expect(flow.description.trim(), isNotEmpty, reason: flow.name);
      }
    });
  });
}
