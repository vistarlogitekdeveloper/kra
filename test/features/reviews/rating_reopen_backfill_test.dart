import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/core/enums/review_flow.dart';
import 'package:vistar_app/features/reviews/data/models/incentive_snapshot.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/rating_reopen.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// July and August 2026, reopened so ratings still PENDING when their window
/// closed can be entered — by the reporting manager, HR and Accounts as well
/// as the employee.
///
/// Asked for on 2 Oct 2026: employees who never self-rated and managers who
/// never rated had no way back into either month, because only the employee's
/// own blanks and management sign-off reached past the window. The decision
/// was "only pending": a blank cell opens to its rater, a rating already given
/// stays locked.
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
        reopenedForBackfill: reopened,
      );

  group('in a reopened month', () {
    test('a pending reviewer rating opens once the employee has self-rated',
        () {
      for (final month in [july, august]) {
        for (final stage in reviewers) {
          expect(open(stage, row(self: 8), month), isTrue,
              reason: '$stage in ${month.key}');
        }
      }
    });

    test('a rating already given stays locked — only pending ones open', () {
      for (final stage in reviewers) {
        expect(open(stage, row(self: 8, ratedBy: stage), july), isFalse,
            reason: '$stage');
      }
    });

    test('a zero counts as given, not as pending', () {
      // 0 is a real rating. Reading it as blank would reopen a finished KRA
      // and let it be quietly changed.
      expect(
        open(
          ReviewStage.reportingManagerRating,
          row(self: 8, ratedBy: ReviewStage.reportingManagerRating, value: 0),
          july,
        ),
        isFalse,
      );
    });

    test('the employee still rates first', () {
      // The reporting manager is capped by the self score, and the server
      // rejects a manager score with no self score behind it.
      for (final stage in reviewers) {
        expect(open(stage, row(), july), isFalse, reason: '$stage');
      }
    });

    test('a flow with no self-rating has nothing to wait for', () {
      for (final stage in reviewers) {
        expect(open(stage, row(), july, flow: ReviewFlow.adminOnly), isTrue,
            reason: '$stage');
      }
    });

    test("the employee's own column is unchanged: blanks open, ratings stay",
        () {
      expect(open(ReviewStage.selfRating, row(), july), isTrue);
      expect(open(ReviewStage.selfRating, row(self: 8), july), isFalse);
    });

    test('management sign-off reaches back exactly as before', () {
      expect(open(ReviewStage.managementReview, row(self: 8), july), isTrue);
      expect(open(ReviewStage.managementReview, row(), july), isFalse);
    });
  });

  group('everywhere else the window holds', () {
    test('July without the reopen stays shut to reviewers', () {
      for (final stage in reviewers) {
        expect(open(stage, row(self: 8), july, reopened: false), isFalse,
            reason: '$stage');
      }
    });

    test('a month that has not ended stays shut even when flagged', () {
      for (final stage in reviewers) {
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

  group('RatingReopen', () {
    tearDown(RatingReopen.reset);

    test('reopens nothing until it is adopted', () {
      expect(RatingReopen.allowsBackfill(july, now), isFalse);
      expect(RatingReopen.allowsBackfill(august, now), isFalse);
    });

    test('reopens exactly the granted months', () {
      RatingReopen.adopt(RatingReopen.granted);
      expect(RatingReopen.allowsBackfill(july, now), isTrue);
      expect(RatingReopen.allowsBackfill(august, now), isTrue);
      expect(RatingReopen.allowsBackfill(const ReviewPeriod(2026, 6), now),
          isFalse);
      expect(RatingReopen.allowsBackfill(september, now), isFalse);
    });

    test('never reopens a month that is still running, whatever is listed', () {
      RatingReopen.adopt({october.key});
      expect(RatingReopen.allowsBackfill(october, now), isFalse);
    });

    test('reset closes everything again', () {
      RatingReopen.adopt(RatingReopen.granted);
      RatingReopen.reset();
      expect(RatingReopen.allowsBackfill(july, now), isFalse);
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

    Future<void> pumpSheet(WidgetTester tester, MonthlyKraRow r) async {
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(1280, 900)),
        child: MaterialApp(
          home: Scaffold(
            body: quarterlyKraSheetBodyForTest(
              now: now,
              months: const [july, august, september],
              reviews: [julyReview(r), null, null],
              editableManager: true,
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

    testWidgets('a July KRA the manager already rated stays read-only',
        (tester) async {
      // A rated cell never says "Rate" — an editable one shows its score with
      // a pencil instead — so compare the pencils with and without the reopen.
      final rated = row(self: 8, ratedBy: ReviewStage.reportingManagerRating);
      await pumpSheet(tester, rated);
      final closed = find.byIcon(Icons.edit_rounded).evaluate().length;

      RatingReopen.adopt(RatingReopen.granted);
      await pumpSheet(tester, rated);
      expect(find.byIcon(Icons.edit_rounded).evaluate().length, closed);
      expect(find.text('Rate'), findsNothing);
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
