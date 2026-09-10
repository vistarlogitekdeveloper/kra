import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/features/reviews/data/models/incentive_snapshot.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// The reported sheet, rendered: Q2 with July self-rated, August not, and
/// September still running. Reviewers were offered a "Rate" button on months
/// nobody could rate yet.
///
/// The clock sits in SEPTEMBER, so August is the month under review and
/// September is the live one. It used to sit on 29 August and treat August as
/// ratable, which assumed a month could be scored before it ended — the defect
/// that let a September self-rating be written on 9 September.
void main() {
  const months = [
    ReviewPeriod(2026, 7),
    ReviewPeriod(2026, 8),
    ReviewPeriod(2026, 9),
  ];
  // August is the month under review; September has not ended, so it stays
  // closed to everyone; July is older and open for a late entry.
  final now = DateTime(2026, 9, 5);

  MonthlyKraRow row({double? selfValue}) {
    var r = const MonthlyKraRow(
      id: 'k1',
      name: 'Safety of the Facility',
      weightagePercent: 100,
      maxScore: 100,
      reviewerGroup: KraReviewer.reportingManager,
      displayOrder: 1,
    );
    if (selfValue != null) {
      r = r.withStageScore(ReviewStage.selfRating, RowScore(value: selfValue));
    }
    return r;
  }

  MonthlyReview review(ReviewPeriod period, {double? selfValue}) =>
      MonthlyReview(
        id: 'r-${period.month}',
        employeeId: 'emp1',
        employeeName: 'Dinesh',
        managerId: 'mgr1',
        period: period,
        currentStage: ReviewStage.selfRating,
        rows: [row(selfValue: selfValue)],
        incentive: const IncentiveSnapshot(),
      );

  Widget host(Widget child) => MediaQuery(
        data: const MediaQueryData(size: Size(1400, 900)),
        child: MaterialApp(home: Scaffold(body: child)),
      );

  testWidgets(
      'the reporting manager gets a Rate button ONLY for the open month',
      (tester) async {
    // 5 September, so August is open. July has ENDED but its window has
    // closed, and it carries a self score — under the old rule that made it
    // the one Rate affordance on the sheet.
    await tester.pumpWidget(host(quarterlyKraSheetBodyForTest(
      now: now,
      months: months,
      reviews: [
        review(months[0], selfValue: 100), // July: self-rated but CLOSED
        review(months[1], selfValue: 100), // August: the open month
        review(months[2]), // September: still running
      ],
      editableManager: true,
    )));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Rate'), findsOneWidget,
        reason: 'August only — July is closed, September has not ended');
  });

  testWidgets(
      'an un-self-rated OPEN month says the SELF rating is what is missing',
      (tester) async {
    await tester.pumpWidget(host(quarterlyKraSheetBodyForTest(
      now: now,
      months: months,
      reviews: [
        review(months[0], selfValue: 100), // July: closed
        review(months[1]), // August: open, nobody has self-rated
        review(months[2]), // September: still running
      ],
      editableManager: true,
    )));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // Nothing to rate anywhere: August needs its self-rating first, and the
    // other two months are out of window in opposite directions.
    expect(find.text('Rate'), findsNothing);
    // And it says WHICH thing is outstanding.
    expect(find.text('Self'), findsOneWidget);
  });

  /// Counts edit pencils. Compared BETWEEN renders rather than asserted
  /// absolutely: the same icon is used by the Reason & proof rows and the
  /// banner, so an absolute count would break on unrelated changes.
  Future<int> pencils(WidgetTester tester, List<MonthlyReview?> reviews,
      {bool management = false, bool self = false}) async {
    await tester.pumpWidget(host(quarterlyKraSheetBodyForTest(
      now: now,
      months: months,
      reviews: reviews,
      editableManagement: management,
      editableSelf: self,
    )));
    await tester.pump();
    expect(tester.takeException(), isNull);
    return tester.widgetList(find.byIcon(Icons.edit_rounded)).length;
  }

  testWidgets('management gains a pencil per month that is actually open',
      (tester) async {
    final onlyJuly = await pencils(
      tester,
      [review(months[0], selfValue: 100), review(months[1]), review(months[2])],
      management: true,
    );
    final julyAndAugust = await pencils(
      tester,
      [
        review(months[0], selfValue: 100),
        review(months[1], selfValue: 70),
        review(months[2]),
      ],
      management: true,
    );
    // Self-rating August opens exactly one more Management cell. September is
    // still closed because the month has not ENDED.
    expect(julyAndAugust, onlyJuly + 1);
  });

  testWidgets('the live month never opens for the employee either',
      (tester) async {
    // September carries a self score in the data but has not ended, so it must
    // add no Self affordance. This is the case that was writable in production.
    final withoutSeptember = await pencils(
      tester,
      [
        review(months[0], selfValue: 100),
        review(months[1], selfValue: 70),
        review(months[2]),
      ],
      self: true,
    );
    final withSeptember = await pencils(
      tester,
      [
        review(months[0], selfValue: 100),
        review(months[1], selfValue: 70),
        review(months[2], selfValue: 50),
      ],
      self: true,
    );
    expect(withSeptember, withoutSeptember,
        reason: 'a month that has not ENDED must stay closed');
  });
}
