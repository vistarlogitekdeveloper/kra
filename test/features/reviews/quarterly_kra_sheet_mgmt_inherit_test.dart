import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/features/reviews/data/models/incentive_snapshot.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// When the Review cycle (stage 2) has scored a KRA and management hasn't
/// overridden it yet, the Management column should pre-fill with that Review
/// score for the management reviewer — so they start from it and only change it
/// if needed, rather than re-keying from a blank cell.
void main() {
  MonthlyKraRow rmRow({double? reviewerScore, double? mgmtScore}) {
    var row = const MonthlyKraRow(
      id: 'k1',
      name: 'On-time dispatch',
      weightagePercent: 100,
      maxScore: 10,
      reviewerGroup: KraReviewer.reportingManager,
      displayOrder: 0,
    );
    if (reviewerScore != null) {
      row = row.withStageScore(
          ReviewStage.reportingManagerRating, RowScore(value: reviewerScore));
    }
    if (mgmtScore != null) {
      row = row.withStageScore(
          ReviewStage.managementReview, RowScore(value: mgmtScore));
    }
    return row;
  }

  MonthlyReview reviewWith(MonthlyKraRow row, {DateTime? managementLockedAt}) =>
      MonthlyReview(
        id: 'r',
        employeeId: 'emp1',
        employeeName: 'Asha',
        period: const ReviewPeriod(2026, 7),
        currentStage: ReviewStage.selfRating,
        rows: [row],
        incentive: const IncentiveSnapshot(),
        managementLockedAt: managementLockedAt,
      );

  Widget host(Widget child) => MediaQuery(
        data: const MediaQueryData(size: Size(1280, 900)),
        child: MaterialApp(home: Scaffold(body: child)),
      );

  const months = [
    ReviewPeriod(2026, 7),
    ReviewPeriod(2026, 8),
    ReviewPeriod(2026, 9),
  ];

  // The inherited (not-yet-confirmed) management value renders italic; a value
  // management has actually set is upright. Match on that so the totals row's
  // echo of the same percent never confuses the assertion.
  Finder inheritedMgmtCell(String pct) => find.byWidgetPredicate((w) =>
      w is Text && w.data == pct && w.style?.fontStyle == FontStyle.italic);
  final anyInherited = find.byWidgetPredicate(
      (w) => w is Text && w.style?.fontStyle == FontStyle.italic);

  testWidgets(
      'management sees the Review score pre-filled in the Mgmt column '
      '(Review 90% → Mgmt 90%)', (tester) async {
    // Review cycle rated this KRA 9/10 (90%); no management override yet.
    final review = reviewWith(rmRow(reviewerScore: 9));
    await tester.pumpWidget(host(
      quarterlyKraSheetBodyForTest(
        months: months,
        reviews: [review, null, null],
        editableManagement: true, // signed in as management (HR_ADMIN / ADMIN)
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // The July Mgmt cell inherits the 90% Review score (shown as a pre-fill).
    expect(inheritedMgmtCell('90%'), findsOneWidget);
  });

  testWidgets('without management rights the Mgmt cell stays blank until acted '
      'on (no inherited pre-fill)', (tester) async {
    final review = reviewWith(rmRow(reviewerScore: 9));
    await tester.pumpWidget(host(
      quarterlyKraSheetBodyForTest(
        months: months,
        reviews: [review, null, null],
        // editableManagement defaults to false — a non-management viewer.
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // The Review score still renders, but nothing is inherited into Mgmt.
    expect(find.text('90%'), findsWidgets);
    expect(anyInherited, findsNothing);
  });

  testWidgets('a real management override wins over the inherited value',
      (tester) async {
    // Review said 90%, management overrode to 7/10 (70%).
    final review = reviewWith(rmRow(reviewerScore: 9, mgmtScore: 7));
    await tester.pumpWidget(host(
      quarterlyKraSheetBodyForTest(
        months: months,
        reviews: [review, null, null],
        editableManagement: true,
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // The Mgmt cell shows the override (70%) as a set value — not inherited.
    expect(find.text('70%'), findsWidgets);
    expect(anyInherited, findsNothing);
  });

  testWidgets('management gets a Save & Lock action that fires the callback',
      (tester) async {
    var locked = false;
    final review = reviewWith(rmRow(reviewerScore: 9));
    await tester.pumpWidget(host(
      quarterlyKraSheetBodyForTest(
        months: months,
        reviews: [review, null, null],
        editableManagement: true,
        onLockManagement: () async => locked = true,
      ),
    ));
    await tester.pump();

    expect(find.text('Save & Lock'), findsOneWidget);
    await tester.tap(find.text('Save & Lock'));
    await tester.pump();
    expect(locked, isTrue);
  });

  testWidgets('non-management viewers never see the Save & Lock action',
      (tester) async {
    final review = reviewWith(rmRow(reviewerScore: 9));
    await tester.pumpWidget(host(
      quarterlyKraSheetBodyForTest(
        months: months,
        reviews: [review, null, null],
        // No management rights and no lock callback wired.
      ),
    ));
    await tester.pump();

    expect(find.text('Save & Lock'), findsNothing);
  });

  testWidgets('once locked, the bar reads locked with a Reopen action and the '
      'Mgmt cell is read-only', (tester) async {
    var reopened = false;
    // Locked review: management already committed a 90% management score.
    final review = reviewWith(
      rmRow(reviewerScore: 9, mgmtScore: 9),
      managementLockedAt: DateTime(2026, 8, 1),
    );
    await tester.pumpWidget(host(
      quarterlyKraSheetBodyForTest(
        months: months,
        reviews: [review, null, null],
        editableManagement: true,
        onLockManagement: () async {},
        onReopenManagement: () async => reopened = true,
      ),
    ));
    await tester.pump();

    // Locked state: Reopen shown, Save & Lock gone.
    expect(find.text('Management review locked'), findsOneWidget);
    expect(find.text('Reopen'), findsOneWidget);
    expect(find.text('Save & Lock'), findsNothing);

    // The locked Mgmt cell is not an editable pre-fill (no inherited italic).
    expect(anyInherited, findsNothing);

    await tester.tap(find.text('Reopen'));
    await tester.pump();
    expect(reopened, isTrue);
  });
}
