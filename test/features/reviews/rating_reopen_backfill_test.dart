import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/core/enums/review_flow.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';
import 'package:vistar_app/features/reviews/data/models/incentive_snapshot.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/rating_reopen.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/presentation/providers/monthly_review_providers.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// July and August 2026, reopened for RATING AND EDITING at every stage, on a
/// backend that sends no rating windows (with one that does, the server's own
/// seed decides the same thing — docs/RATING_ACCESS.md).
///
/// The first version (2 Oct 2026, morning) opened only BLANK cells: anyone who
/// had already rated could not correct their rating, and an employee who had
/// rated every KRA could not change a reason or replace an attachment. The
/// product owner then asked for full access — "update the rating and remarks
/// and attachments also" — which is the "rate and edit until 31 Oct" already
/// agreed for these months. A reopened month now behaves exactly like the open
/// review month.
void main() {
  const july = ReviewPeriod(2026, 7);
  const august = ReviewPeriod(2026, 8);
  const september = ReviewPeriod(2026, 9);
  const october = ReviewPeriod(2026, 10);

  // The day it was asked for: September is the open month, July and August
  // have closed, October is still running.
  final now = DateTime(2026, 10, 2);

  const reviewers = [
    ReviewStage.reportingManagerRating,
    ReviewStage.accountHrRating,
    ReviewStage.financeRating,
  ];

  MonthlyKraRow row({double? self, ReviewStage? ratedBy, double value = 6}) {
    var r = const MonthlyKraRow(
      id: 'k1',
      name: 'Safety of the Facility',
      weightagePercent: 100,
      maxScore: 10,
      reviewerGroup: KraReviewer.reportingManager,
      displayOrder: 1,
    );
    if (self != null) {
      r = r.withStageScore(ReviewStage.selfRating, RowScore(value: self));
    }
    if (ratedBy != null) {
      r = r.withStageScore(ratedBy, RowScore(value: value));
    }
    return r;
  }

  bool open(
    ReviewStage stage,
    MonthlyKraRow r,
    ReviewPeriod month, {
    bool reopened = true,
    ReviewFlow flow = ReviewFlow.standard,
  }) =>
      isCellOpenForEntry(
        stage: stage,
        row: r,
        month: month,
        now: now,
        flow: flow,
        reopened: reopened,
      );

  group('in a reopened month: rate AND edit, every stage', () {
    test('a pending reviewer rating opens once the employee has self-rated',
        () {
      for (final month in [july, august]) {
        for (final stage in reviewers) {
          expect(open(stage, row(self: 8), month), isTrue,
              reason: '$stage in ${month.key}');
        }
      }
    });

    test('a rating already given can be corrected', () {
      for (final stage in reviewers) {
        expect(open(stage, row(self: 8, ratedBy: stage), july), isTrue,
            reason: '$stage');
      }
      // 0 is a real rating, and is as editable as any other.
      expect(
        open(
          ReviewStage.reportingManagerRating,
          row(self: 8, ratedBy: ReviewStage.reportingManagerRating, value: 0),
          july,
        ),
        isTrue,
      );
    });

    test("the employee's own ratings can be corrected too, not only blanks",
        () {
      expect(open(ReviewStage.selfRating, row(), july), isTrue);
      expect(open(ReviewStage.selfRating, row(self: 8), july), isTrue);
      expect(open(ReviewStage.selfRating, row(self: 8), august), isTrue);
    });

    test('management can rate and edit as before', () {
      expect(open(ReviewStage.managementReview, row(self: 8), july), isTrue);
      expect(
        open(ReviewStage.managementReview,
            row(self: 8, ratedBy: ReviewStage.managementReview), july),
        isTrue,
      );
    });

    test('the employee still rates first', () {
      // The reporting manager is capped by the self score, and the server
      // rejects a manager score with no self score behind it.
      for (final stage in reviewers) {
        expect(open(stage, row(), july), isFalse, reason: '$stage');
      }
      expect(open(ReviewStage.managementReview, row(), july), isFalse);
    });

    test('a flow with no self-rating has nothing to wait for', () {
      for (final stage in reviewers) {
        expect(open(stage, row(), july, flow: ReviewFlow.adminOnly), isTrue,
            reason: '$stage');
      }
    });
  });

  group('everywhere else the window holds', () {
    test('July without the reopen: only the old reach-backs', () {
      for (final stage in reviewers) {
        expect(open(stage, row(self: 8), july, reopened: false), isFalse,
            reason: '$stage');
      }
      expect(open(ReviewStage.selfRating, row(self: 8), july, reopened: false),
          isFalse,
          reason: 'a closed month can be finished, never revised');
      expect(open(ReviewStage.selfRating, row(), july, reopened: false), isTrue,
          reason: 'blanks stay fillable, as before');
    });

    test('a month that has not ended stays shut even when flagged', () {
      for (final stage in [ReviewStage.selfRating, ...reviewers]) {
        expect(open(stage, row(self: 8), october), isFalse, reason: '$stage');
      }
    });

    test('the open month still allows a rating to be revised', () {
      expect(
        open(
          ReviewStage.reportingManagerRating,
          row(self: 8, ratedBy: ReviewStage.reportingManagerRating),
          september,
          reopened: false,
        ),
        isTrue,
      );
    });
  });

  group("the employee's sheet in a reopened month (ratings, reasons, proof)",
      () {
    tearDown(RatingReopen.reset);

    const owner =
        ReviewScope(userId: 'emp1', userName: 'Asha', role: UserRole.employee);
    const manager =
        ReviewScope(userId: 'mgr1', userName: 'Manish', role: UserRole.manager);

    MonthlyReview fullyRated(ReviewPeriod period,
            {ReviewStage stage = ReviewStage.reportingManagerRating}) =>
        MonthlyReview(
          id: 'r-${period.key}',
          employeeId: 'emp1',
          employeeName: 'Asha',
          managerId: 'mgr1',
          period: period,
          currentStage: stage,
          rows: [row(self: 8, ratedBy: ReviewStage.reportingManagerRating)],
        );

    test(
        'every KRA already self-rated: the owner can still edit it (and so its '
        'reason and attachment, which ride on the same gate)', () {
      expect(canEditSelfRating(fullyRated(july), owner, now), isFalse,
          reason: 'before the reopen a finished month is read-only');
      RatingReopen.adopt(RatingReopen.granted);
      expect(canEditSelfRating(fullyRated(july), owner, now), isTrue);
      expect(canEditSelfRating(fullyRated(august), owner, now), isTrue);
    });

    test('nobody else edits the self-rating, reopen or not', () {
      RatingReopen.adopt(RatingReopen.granted);
      expect(canEditSelfRating(fullyRated(july), manager, now), isFalse);
    });

    test('a paid (completed) month stays locked', () {
      RatingReopen.adopt(RatingReopen.granted);
      expect(
          canEditSelfRating(
              fullyRated(july, stage: ReviewStage.completed), owner, now),
          isFalse);
    });

    test('the reopen ends at 31 Oct 2026, end of day IST', () {
      RatingReopen.adopt(RatingReopen.granted);
      expect(
          canEditSelfRating(
              fullyRated(july), owner, DateTime.utc(2026, 10, 31, 18, 29)),
          isTrue);
      expect(
          canEditSelfRating(
              fullyRated(july), owner, DateTime.utc(2026, 10, 31, 18, 30)),
          isFalse);
    });
  });

  group('RatingReopen', () {
    tearDown(RatingReopen.reset);

    test('reopens nothing until it is adopted', () {
      expect(RatingReopen.isReopened(july, now), isFalse);
      expect(RatingReopen.isReopened(august, now), isFalse);
    });

    test('reopens exactly the granted months', () {
      RatingReopen.adopt(RatingReopen.granted);
      expect(RatingReopen.isReopened(july, now), isTrue);
      expect(RatingReopen.isReopened(august, now), isTrue);
      expect(
          RatingReopen.isReopened(const ReviewPeriod(2026, 6), now), isFalse);
      expect(RatingReopen.isReopened(september, now), isFalse);
    });

    test('never reopens a month that is still running, whatever is listed', () {
      RatingReopen.adopt({october.key});
      expect(RatingReopen.isReopened(october, now), isFalse);
    });

    test('reset closes everything again', () {
      RatingReopen.adopt(RatingReopen.granted);
      RatingReopen.reset();
      expect(RatingReopen.isReopened(july, now), isFalse);
    });

    test('every granted key is a real month key', () {
      // '2026-7' would match no month and reopen nothing, with no error.
      for (final key in RatingReopen.granted) {
        final parts = key.split('-');
        expect(parts, hasLength(2), reason: key);
        final period = ReviewPeriod(int.parse(parts[0]), int.parse(parts[1]));
        expect(period.month, inInclusiveRange(1, 12), reason: key);
        expect(period.key, key);
      }
    });
  });

  group('on the sheet', () {
    tearDown(RatingReopen.reset);

    MonthlyReview julyReview(MonthlyKraRow r) => MonthlyReview(
          id: 'r-jul',
          employeeId: 'emp1',
          employeeName: 'Asha',
          managerId: 'mgr1',
          period: july,
          currentStage: ReviewStage.selfRating,
          rows: [r],
          incentive: const IncentiveSnapshot(),
        );

    /// The sheet as the reporting manager sees it, or — with [asEmployee] —
    /// as the employee does.
    Future<void> pumpSheet(WidgetTester tester, MonthlyKraRow r,
        {bool asEmployee = false}) async {
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(1280, 900)),
        child: MaterialApp(
          home: Scaffold(
            body: quarterlyKraSheetBodyForTest(
              now: now,
              months: const [july, august, september],
              reviews: [julyReview(r), null, null],
              editableSelf: asEmployee,
              editableManager: !asEmployee,
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets('the reporting manager is offered Rate on a pending July KRA',
        (tester) async {
      RatingReopen.adopt(RatingReopen.granted);
      await pumpSheet(tester, row(self: 8));
      expect(find.text('Rate'), findsWidgets);
    });

    testWidgets('and is not, before the month was reopened', (tester) async {
      await pumpSheet(tester, row(self: 8));
      expect(find.text('Rate'), findsNothing);
    });

    testWidgets("a July KRA the manager already rated gains its edit pencil",
        (tester) async {
      // A rated cell never says "Rate" — an editable one shows its score with
      // a pencil — so count the pencils with and without the reopen.
      final rated = row(self: 8, ratedBy: ReviewStage.reportingManagerRating);
      await pumpSheet(tester, rated);
      final closed = find.byIcon(Icons.edit_rounded).evaluate().length;

      RatingReopen.adopt(RatingReopen.granted);
      await pumpSheet(tester, rated);
      expect(find.byIcon(Icons.edit_rounded).evaluate().length, closed + 1);
    });

    testWidgets("the employee's own rated July KRA gains its edit pencil",
        (tester) async {
      final rated = row(self: 8, ratedBy: ReviewStage.reportingManagerRating);
      await pumpSheet(tester, rated, asEmployee: true);
      final closed = find.byIcon(Icons.edit_rounded).evaluate().length;

      RatingReopen.adopt(RatingReopen.granted);
      await pumpSheet(tester, rated, asEmployee: true);
      expect(find.byIcon(Icons.edit_rounded).evaluate().length, closed + 1);
    });

    testWidgets('a reopened KRA still waiting on the employee says so',
        (tester) async {
      // Without the reopen the cell is a bare dash; with it the manager must be
      // told the KRA is waiting on the self-rating, or the reopen looks broken.
      await pumpSheet(tester, row());
      final closed = find.text('Self').evaluate().length;

      RatingReopen.adopt(RatingReopen.granted);
      await pumpSheet(tester, row());
      expect(find.text('Self').evaluate().length, closed + 1);
    });
  });
}
