import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/reviews/data/models/incentive_snapshot.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// Layout regression guard for the quarterly KRA sheet grid.
///
/// The month/quarter columns are fixed-width. A full "100%" achievement in an
/// *editable* cell renders the percent text PLUS an edit icon inside a bordered
/// box — the widest thing a cell ever holds. If a column is sized too tight the
/// inner Row overflows and Flutter reports a RenderFlex overflow. These tests
/// render that exact worst case and assert the frame is clean.
void main() {
  MonthlyReview reviewWith100() {
    final row = const MonthlyKraRow(
      id: 'kra-0',
      name: 'On-Time Dispatch Rate',
      category: 'Operational Excellence',
      weightagePercent: 100,
      maxScore: 10,
      target: 'zero incident',
      displayOrder: 0,
    )
        .withStageScore(ReviewStage.selfRating, const RowScore(value: 10))
        .withStageScore(
            ReviewStage.reportingManagerRating, const RowScore(value: 10));
    return MonthlyReview(
      id: 'r1',
      employeeId: 'emp1',
      employeeName: 'Asha',
      period: const ReviewPeriod(2026, 7),
      currentStage: ReviewStage.selfRating,
      stageRecords: const {},
      rows: [row],
      incentive: const IncentiveSnapshot(),
    );
  }

  Widget host(Size size, Widget child) => MediaQuery(
        data: MediaQueryData(size: size),
        child: MaterialApp(home: Scaffold(body: child)),
      );

  const months = [
    ReviewPeriod(2026, 7),
    ReviewPeriod(2026, 8),
    ReviewPeriod(2026, 9),
  ];

  testWidgets(
      'renders a 100% editable Self & Manager cell without RenderFlex overflow',
      (tester) async {
    await tester.pumpWidget(host(
      const Size(390, 844),
      quarterlyKraSheetBodyForTest(
        months: months,
        reviews: [reviewWith100(), null, null],
        editableSelf: true,
        editableManager: true,
      ),
    ));
    await tester.pump();

    // A RenderFlex overflow is reported as a caught exception on the frame.
    expect(tester.takeException(), isNull);
    // Sanity: the worst-case value actually rendered (so the guard is real).
    expect(find.text('100%'), findsWidgets);
  });

  testWidgets('stays clean on a very narrow phone width', (tester) async {
    await tester.pumpWidget(host(
      const Size(320, 720),
      quarterlyKraSheetBodyForTest(
        months: months,
        reviews: [reviewWith100(), null, null],
        editableSelf: true,
        editableManager: true,
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
