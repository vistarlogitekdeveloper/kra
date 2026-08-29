import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/features/reviews/data/models/incentive_snapshot.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// The reported sheet, rendered: Q2 on 29 August, July self-rated, August not,
/// September not yet begun. Reviewers were offered a "Rate" button on both
/// August and September.
void main() {
  const months = [
    ReviewPeriod(2026, 7),
    ReviewPeriod(2026, 8),
    ReviewPeriod(2026, 9),
  ];
  final now = DateTime(2026, 8, 29);

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
      'the reporting manager gets no Rate button for an un-self-rated '
      'August or an unstarted September', (tester) async {
    await tester.pumpWidget(host(quarterlyKraSheetBodyForTest(
      now: now,
      months: months,
      reviews: [
        review(months[0], selfValue: 100), // July done
        review(months[1]), // August: nobody has self-rated
        review(months[2]), // September: not started
      ],
      editableManager: true,
    )));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // Exactly ONE Rate affordance: July, the only month with a self score.
    expect(find.text('Rate'), findsOneWidget);
    // August says the SELF rating is what is outstanding, not the manager.
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
    // still closed because the month has not started.
    expect(julyAndAugust, onlyJuly + 1);
  });

  testWidgets('a future month never opens for the employee either',
      (tester) async {
    // September is self-rated in the data but has not begun, so it must add no
    // Self affordance.
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
        reason: 'a month that has not started must stay closed');
  });
}
