import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/core/enums/review_flow.dart';
import 'package:vistar_app/features/reviews/data/models/incentive_snapshot.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// The Self columns exist only on a flow that HAS a self-rating.
///
/// Reported from the live sheet on an administrators-only organisation: each
/// month carried three columns — Self / Review / Mgmt — and the Self one was a
/// dash in every row with a 0% in the totals, because under that flow the
/// employee never rates. Three dead month columns plus the dead Qtr Self is
/// 266 px of grid, which pushed the two live columns off the right edge and
/// made the sheet read as though the employee had scored zero.
///
/// The gate is `stageIsInFlow(ReviewStage.selfRating, flow)` — the same
/// predicate the legend, the cell-openness rule and the payout card use. It is
/// deliberately NOT `flow == adminOnly`: restating that is how the four
/// builders below would drift, and the last group here is the reason that
/// matters.
void main() {
  // reviewerGroup HR ⇒ reviewStage ACCOUNT_HR_RATING (a derived getter, not a
  // constructor argument). Both a self and a reviewer score are present, so a
  // Self column that is still being drawn has a real number in it to find.
  MonthlyReview reviewWithScores(ReviewPeriod period) {
    final row = const MonthlyKraRow(
      id: 'kra-0',
      name: 'On-Time Dispatch Rate',
      weightagePercent: 100,
      maxScore: 10,
      reviewerGroup: KraReviewer.hr,
      displayOrder: 0,
    )
        .withStageScore(ReviewStage.selfRating, const RowScore(value: 8))
        .withStageScore(ReviewStage.accountHrRating, const RowScore(value: 9));
    return MonthlyReview(
      id: 'r-${period.month}',
      employeeId: 'emp1',
      employeeName: 'Temp',
      period: period,
      currentStage: ReviewStage.accountHrRating,
      stageRecords: const {},
      rows: [row],
      incentive: const IncentiveSnapshot(),
    );
  }

  const months = [
    ReviewPeriod(2026, 7),
    ReviewPeriod(2026, 8),
    ReviewPeriod(2026, 9),
  ];
  // Past the whole quarter, so every month is ratable and every cell renders
  // in its live state rather than the not-yet-open one.
  final now = DateTime(2026, 10, 15);

  Widget host(ReviewFlow flow, {Size size = const Size(1600, 1000)}) =>
      MediaQuery(
        data: MediaQueryData(size: size),
        child: MaterialApp(
          home: Scaffold(
            body: quarterlyKraSheetBodyForTest(
              flow: flow,
              now: now,
              months: months,
              reviews: [for (final m in months) reviewWithScores(m)],
              editableSelf: true,
              editableHr: true,
              editableManagement: true,
            ),
          ),
        ),
      );

  // The grid's fixed column widths, mirrored so the arithmetic below is
  // readable. Kept in sync by the equality assertions, not by hand.
  const wWt = 44.0, wKra = 170.0, wTgt = 112.0, wTrk = 158.0;
  const wMon = 70.0, wQtr = 56.0;
  const fixed = wWt + wKra + wTgt + wTrk;
  const expectedWidth = {
    ReviewFlow.standard: fixed + wMon * 9 + wQtr * 3, // 1282
    ReviewFlow.adminOnly: fixed + wMon * 6 + wQtr * 2, // 1016
  };

  /// The summed cell width of every full-width row the grid emitted.
  ///
  /// `_cell` returns a fixed-width `SizedBox`, so a row's cell count is
  /// exactly what this measures. Rows nested INSIDE a cell (the KRA name
  /// block, a badge) hold only small spacers, so the 500 px floor keeps just
  /// the header, each KRA row and the totals.
  List<double> gridRowWidths(WidgetTester tester) {
    final out = <double>[];
    for (final element in find.byType(Row).evaluate()) {
      var total = 0.0;
      element.visitChildren((child) {
        final w = child.widget;
        if (w is SizedBox && w.width != null) total += w.width!;
      });
      if (total > 500) out.add(total);
    }
    return out;
  }

  group('administrators-only drops the Self columns', () {
    testWidgets('no per-month Self header survives', (tester) async {
      await tester.pumpWidget(host(ReviewFlow.adminOnly));

      for (final m in months) {
        expect(find.text('${m.shortLabel}\nSelf'), findsNothing,
            reason: '${m.shortLabel} Self is a column nobody can fill');
      }
      expect(find.text('Qtr\nSelf'), findsNothing);
    });

    testWidgets('the Review and Mgmt columns are untouched', (tester) async {
      // The point of the change is to make these two easier to reach, so a
      // regression that dropped one of them instead would sail past the test
      // above.
      await tester.pumpWidget(host(ReviewFlow.adminOnly));

      for (final m in months) {
        expect(find.text('${m.shortLabel}\nReview'), findsOneWidget);
        expect(find.text('${m.shortLabel}\nMgmt'), findsOneWidget);
      }
      expect(find.text('Qtr\nReview'), findsOneWidget);
      expect(find.text('Qtr\nFinal'), findsOneWidget);
      // ...and the Review score is still shown: 9/10.
      expect(find.text('90%'), findsWidgets);
    });

    testWidgets('the payout card drops "Quarter self average"', (tester) async {
      await tester.pumpWidget(host(ReviewFlow.adminOnly));

      // It read a flat 0% beside a real final average, which looks like the
      // employee scored nothing rather than like the row does not apply.
      expect(find.text('Quarter self average'), findsNothing);
      expect(find.text('Quarter final average'), findsOneWidget);
    });

    testWidgets('the Reason & proof panel drops the Employee slot',
        (tester) async {
      await tester.pumpWidget(host(ReviewFlow.adminOnly));
      await tester.tap(find.byIcon(Icons.expand_more_rounded));
      await tester.pumpAndSettle();

      // Three months, so three reviewer slots and — before the fix — three
      // employee slots reading "No entry" for the life of the quarter.
      expect(find.text('Employee'), findsNothing);
      expect(find.text('Reviewer · HR'), findsNWidgets(3));
      // ...and the panel no longer promises an entry that cannot exist.
      expect(find.textContaining('employee + reviewer evidence'), findsNothing);
      expect(find.textContaining('reviewer evidence'), findsOneWidget);
    });
  });

  group('the standard flow is UNCHANGED', () {
    testWidgets('all three per-month columns and Qtr Self are drawn',
        (tester) async {
      await tester.pumpWidget(host(ReviewFlow.standard));

      for (final m in months) {
        expect(find.text('${m.shortLabel}\nSelf'), findsOneWidget);
        expect(find.text('${m.shortLabel}\nReview'), findsOneWidget);
        expect(find.text('${m.shortLabel}\nMgmt'), findsOneWidget);
      }
      expect(find.text('Qtr\nSelf'), findsOneWidget);
      // The self score renders: 8/10.
      expect(find.text('80%'), findsWidgets);
    });

    testWidgets('the payout card still prints the self average',
        (tester) async {
      await tester.pumpWidget(host(ReviewFlow.standard));
      expect(find.text('Quarter self average'), findsOneWidget);
    });

    testWidgets('the Reason & proof panel keeps the Employee slot',
        (tester) async {
      await tester.pumpWidget(host(ReviewFlow.standard));
      await tester.tap(find.byIcon(Icons.expand_more_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Employee'), findsNWidgets(3));
      expect(find.text('Reviewer · HR'), findsNWidgets(3));
      expect(
          find.textContaining('employee + reviewer evidence'), findsOneWidget);
    });
  });

  group('every builder agrees on the column count', () {
    // The bug class this change could introduce, and the reason the gate is
    // one getter rather than four conditions. `_totalWidth` sizes the
    // horizontal scroll; the header, each KRA row and the totals row each emit
    // their own cells. Hide a column in one and keep charging for it in
    // another and every value shifts against its column label — silently, with
    // no overflow error to catch it.
    for (final flow in ReviewFlow.values) {
      testWidgets('${flow.name}: header, KRA row and totals are equal width',
          (tester) async {
        await tester.pumpWidget(host(flow));

        final widths = gridRowWidths(tester);
        expect(widths.length, 3,
            reason: 'header + one KRA row + totals, got $widths');
        expect(widths.toSet(), {expectedWidth[flow]},
            reason: 'one builder emitted a different number of cells');
      });

      testWidgets('${flow.name}: the scroll reserves exactly that width',
          (tester) async {
        await tester.pumpWidget(host(flow));

        // `_totalWidth` on the grid's own SizedBox. If it disagrees with the
        // rows the sheet either scrolls past its content or clips the last
        // column.
        expect(
          find.byWidgetPredicate(
              (w) => w is SizedBox && w.width == expectedWidth[flow]),
          findsWidgets,
        );
      });
    }

    testWidgets('adminOnly is narrower than standard by exactly the Self cols',
        (tester) async {
      await tester.pumpWidget(host(ReviewFlow.standard));
      final wide = gridRowWidths(tester).first;

      await tester.pumpWidget(host(ReviewFlow.adminOnly));
      final narrow = gridRowWidths(tester).first;

      expect(wide - narrow, wMon * 3 + wQtr,
          reason: '3 month columns at $wMon + the Qtr Self at $wQtr');
    });
  });

  group('no overflow at either extreme', () {
    for (final flow in ReviewFlow.values) {
      testWidgets('${flow.name}: clean on a 320 px phone', (tester) async {
        await tester.pumpWidget(host(flow, size: const Size(320, 720)));
        await tester.pump();
        // A RenderFlex overflow is reported as a caught exception on the frame.
        expect(tester.takeException(), isNull);
      });

      testWidgets('${flow.name}: clean on a 1920 px desktop', (tester) async {
        await tester.pumpWidget(host(flow, size: const Size(1920, 1080)));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
