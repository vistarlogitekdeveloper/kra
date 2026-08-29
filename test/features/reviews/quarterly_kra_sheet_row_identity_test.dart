import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/features/reviews/data/models/incentive_snapshot.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// The quarterly sheet must find the same KRA across all three months.
///
/// It could not. The backend inserts monthly review rows with `randomUUID()`
/// per row PER REVIEW, so one KRA has a different id every month, while the
/// sheet takes its canonical row list from the FIRST month present and looked
/// every cell up by that id. Months two and three therefore matched nothing and
/// rendered blank — for every employee, whatever had been entered.
///
/// It reads exactly like "that month's review has not started", which is how it
/// was reported. Only the monthly TOTALS row looked right, because that is
/// computed from the review rather than row by row — so the sheet contradicted
/// itself: a 60% August total above a column of dashes.
void main() {
  const months = [
    ReviewPeriod(2026, 7),
    ReviewPeriod(2026, 8),
    ReviewPeriod(2026, 9),
  ];
  final now = DateTime(2026, 9, 15); // all three months have started

  MonthlyKraRow row(
    String id, {
    required String name,
    required int order,
    double? selfValue,
    double? managerValue,
  }) {
    var r = MonthlyKraRow(
      id: id,
      name: name,
      weightagePercent: 50,
      maxScore: 100,
      reviewerGroup: KraReviewer.reportingManager,
      displayOrder: order,
    );
    if (selfValue != null) {
      r = r.withStageScore(ReviewStage.selfRating, RowScore(value: selfValue));
    }
    if (managerValue != null) {
      r = r.withStageScore(
        ReviewStage.reportingManagerRating,
        RowScore(value: managerValue),
      );
    }
    return r;
  }

  /// Row ids are unique per review, exactly as the backend mints them.
  MonthlyReview review(
    ReviewPeriod period,
    String idPrefix, {
    double? selfA,
    double? selfB,
    double? managerA,
  }) =>
      MonthlyReview(
        id: 'r-${period.month}',
        employeeId: 'emp1',
        employeeName: 'Dinesh',
        managerId: 'mgr1',
        period: period,
        currentStage: ReviewStage.selfRating,
        rows: [
          row('$idPrefix-a',
              name: 'Safety of the Facility',
              order: 1,
              selfValue: selfA,
              managerValue: managerA),
          row('$idPrefix-b',
              name: 'Inventory accuracy', order: 2, selfValue: selfB),
        ],
        incentive: const IncentiveSnapshot(),
      );

  Widget host(Widget child) => MediaQuery(
        data: const MediaQueryData(size: Size(1500, 900)),
        child: MaterialApp(home: Scaffold(body: child)),
      );

  /// Every percentage the sheet renders, in order.
  List<String> percents(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data)
      .whereType<String>()
      .where((d) => d.endsWith('%'))
      .toList();

  testWidgets('a later month\'s self scores render in their own cells',
      (tester) async {
    await tester.pumpWidget(host(quarterlyKraSheetBodyForTest(
      now: now,
      months: months,
      reviews: [
        review(months[0], 'jul', selfA: 100, selfB: 100),
        // Distinct values, and deliberately not equal to the month total (60%),
        // so a passing assertion cannot be the totals row in disguise.
        review(months[1], 'aug', selfA: 40, selfB: 80),
        review(months[2], 'sep'),
      ],
    )));
    await tester.pump();

    expect(tester.takeException(), isNull);
    final shown = percents(tester);
    expect(shown, contains('40%'),
        reason: "August's first KRA cell — its own row id, not July's");
    expect(shown, contains('80%'), reason: "August's second KRA cell");
  });

  testWidgets('a later month\'s Review scores render too', (tester) async {
    await tester.pumpWidget(host(quarterlyKraSheetBodyForTest(
      now: now,
      months: months,
      reviews: [
        review(months[0], 'jul', selfA: 100, selfB: 100),
        review(months[1], 'aug', selfA: 90, selfB: 90, managerA: 30),
        review(months[2], 'sep'),
      ],
    )));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(percents(tester), contains('30%'),
        reason: "August's manager rating for the first KRA");
  });

  testWidgets('the quarter average counts every month, not just the first',
      (tester) async {
    await tester.pumpWidget(host(quarterlyKraSheetBodyForTest(
      now: now,
      months: months,
      reviews: [
        review(months[0], 'jul', selfA: 60, selfB: 0),
        review(months[1], 'aug', selfA: 60, selfB: 0),
        review(months[2], 'sep', selfA: 60, selfB: 0),
      ],
    )));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // Row 1 averages 60 across three months. Matching only July would have
    // given 20% — a real under-count of everyone's quarter.
    expect(percents(tester), contains('60%'));
    expect(percents(tester), isNot(contains('20%')));
  });

  testWidgets('an edit targets the month\'s OWN row id, not the first month\'s',
      (tester) async {
    // A save aimed at a row id that month does not contain would hit the wrong
    // row or fail outright, so the id handed to the editor matters as much as
    // the one used for display.
    String? editedRowId;
    await tester.pumpWidget(host(quarterlyKraSheetBodyForTest(
      now: now,
      months: months,
      reviews: [
        review(months[0], 'jul', selfA: 100, selfB: 100),
        review(months[1], 'aug', selfA: 50, selfB: 50),
        review(months[2], 'sep'),
      ],
      editableManager: true,
      onEdit: ({required review, required rowId, required stage}) {
        editedRowId = rowId;
      },
    )));
    await tester.pump();

    // The Rate affordances are July's and August's, in column order.
    final rateButtons = find.text('Rate');
    expect(rateButtons, findsWidgets);
    await tester.ensureVisible(rateButtons.at(1));
    await tester.pumpAndSettle();
    await tester.tap(rateButtons.at(1), warnIfMissed: false); // August, 1st KRA
    await tester.pump();

    expect(editedRowId, 'aug-a',
        reason: 'the editor must be given August\'s row, not July\'s');
  });
}
