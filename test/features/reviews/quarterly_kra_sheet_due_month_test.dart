import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/features/reviews/data/models/incentive_snapshot.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// Guards the sheet's answer to "which month am I supposed to rate?".
///
/// Reported as "self rating is done, still it says self rating is overdue".
/// The overdue warning was right: the employee had rated the quarter's FIRST
/// month, which is the leftmost Self column, and left the current month empty.
/// Nothing on the sheet said which of the three months was due, and the hint
/// read "You can edit the Self ratings on this sheet" — true of all three.
///
/// So the sheet must name the outstanding month, and must stop saying it once
/// there is nothing outstanding. The clock is injected: the copy turns on which
/// month is current, so a test reading the real clock would assert something
/// different every month.
void main() {
  const august = ReviewPeriod(2026, 8);
  final inAugust = DateTime(2026, 8, 25);

  const months = [
    ReviewPeriod(2026, 7),
    august,
    ReviewPeriod(2026, 9),
  ];

  MonthlyKraRow row({double? selfScore}) {
    var r = const MonthlyKraRow(
      id: 'k1',
      name: 'Safety of the Facility',
      weightagePercent: 100,
      maxScore: 10,
      reviewerGroup: KraReviewer.reportingManager,
      displayOrder: 0,
    );
    if (selfScore != null) {
      r = r.withStageScore(ReviewStage.selfRating, RowScore(value: selfScore));
    }
    return r;
  }

  MonthlyReview reviewFor(ReviewPeriod period, {double? selfScore}) =>
      MonthlyReview(
        id: 'r-${period.month}',
        employeeId: 'emp1',
        employeeName: 'Asha',
        managerId: 'mgr1',
        period: period,
        currentStage: ReviewStage.selfRating,
        rows: [row(selfScore: selfScore)],
        incentive: const IncentiveSnapshot(),
      );

  Widget host(Widget child) => MediaQuery(
        data: const MediaQueryData(size: Size(1280, 900)),
        child: MaterialApp(home: Scaffold(body: child)),
      );

  const genericHint = 'You can edit the Self ratings on this sheet.';
  const augustHint = "Rate your Aug '26 Self column — that is the current "
      'month, and it is still empty.';

  testWidgets(
      'an earlier month rated but the current one empty → the hint '
      'names the current month', (tester) async {
    await tester.pumpWidget(host(quarterlyKraSheetBodyForTest(
      now: inAugust,
      months: months,
      reviews: [
        reviewFor(months[0], selfScore: 9), // July done — the reported case
        reviewFor(august), // August empty
        null,
      ],
      editableSelf: true,
    )));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text(augustHint), findsOneWidget);
    // The generic wording must be replaced, not merely joined.
    expect(find.text(genericHint), findsNothing);
  });

  testWidgets('the current month has no review row yet → still named as due',
      (tester) async {
    // HR generates months lazily, so "not generated" and "generated but empty"
    // are both outstanding to the employee and must read the same.
    await tester.pumpWidget(host(quarterlyKraSheetBodyForTest(
      now: inAugust,
      months: months,
      reviews: [reviewFor(months[0], selfScore: 9), null, null],
      editableSelf: true,
    )));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text(augustHint), findsOneWidget);
  });

  testWidgets('the current month is rated → no nagging, generic hint returns',
      (tester) async {
    await tester.pumpWidget(host(quarterlyKraSheetBodyForTest(
      now: inAugust,
      months: months,
      reviews: [null, reviewFor(august, selfScore: 8), null],
      editableSelf: true,
    )));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('is still empty'), findsNothing);
    expect(find.text(genericHint), findsOneWidget);
  });

  testWidgets('an unrated month that is NOT the current month is left alone',
      (tester) async {
    // A quarter the employee is only visiting: nagging about a past month they
    // can no longer be marked overdue for would bury the one that matters.
    await tester.pumpWidget(host(quarterlyKraSheetBodyForTest(
      now: DateTime(2026, 11, 3), // after the whole quarter
      months: months,
      reviews: [reviewFor(months[0]), null, null],
      editableSelf: true,
    )));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('is still empty'), findsNothing);
    expect(find.text(genericHint), findsOneWidget);
  });

  testWidgets('a viewer who cannot self-rate never sees the due-month hint',
      (tester) async {
    await tester.pumpWidget(host(quarterlyKraSheetBodyForTest(
      now: inAugust,
      months: months,
      reviews: [null, reviewFor(august), null],
      editableSelf: false,
      editableManager: true,
    )));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('is still empty'), findsNothing);
  });
}
