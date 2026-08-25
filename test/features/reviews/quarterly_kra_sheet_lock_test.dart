import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/features/reviews/data/models/incentive_snapshot.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// Guards the lock half of the quarterly sheet's edit gates.
///
/// The gates used to ask only "who are you?" — identity for Self, the reporting
/// relationship for the manager, a bare role for HR / Accounts / management —
/// and never "is this month still open?". So a finished month rendered a pencil,
/// opened the rating sheet, and failed only on save, when the backend answered
/// 409 RES_002 "Review is completed; scores are locked."
///
/// Each month of a quarter locks independently, so these assertions are
/// per-month: a locked July must refuse the edit while an open August still
/// offers it.
void main() {
  MonthlyKraRow rowFor(String id, String name, KraReviewer reviewer) =>
      MonthlyKraRow(
        id: id,
        name: name,
        weightagePercent: 100,
        maxScore: 10,
        reviewerGroup: reviewer,
        displayOrder: 0,
      );

  MonthlyReview reviewWith(
    List<MonthlyKraRow> rows, {
    required ReviewStage currentStage,
    ReviewPeriod period = const ReviewPeriod(2026, 7),
  }) =>
      MonthlyReview(
        id: 'r-${period.month}',
        employeeId: 'emp1',
        employeeName: 'Asha',
        managerId: 'mgr1',
        period: period,
        currentStage: currentStage,
        rows: rows,
        incentive: const IncentiveSnapshot(),
      );

  Widget host(Widget child) => MediaQuery(
        data: const MediaQueryData(size: Size(1280, 900)),
        child: MaterialApp(home: Scaffold(body: child)),
      );

  // Pinned "today", deliberately AFTER the quarter. The sheet re-words its
  // hint when one of these months is the current calendar month, so a test
  // reading the real clock would assert different copy from September onwards.
  final afterTheQuarter = DateTime(2026, 11, 3);

  const months = [
    ReviewPeriod(2026, 7),
    ReviewPeriod(2026, 8),
    ReviewPeriod(2026, 9),
  ];

  List<MonthlyKraRow> oneRow() =>
      [rowFor('k1', 'Safety of the Facility', KraReviewer.reportingManager)];

  testWidgets('a completed month offers the employee no Self edit affordance',
      (tester) async {
    final completed = reviewWith(oneRow(), currentStage: ReviewStage.completed);
    await tester.pumpWidget(host(quarterlyKraSheetBodyForTest(
      now: afterTheQuarter,
      months: months,
      reviews: [completed, null, null],
      // Signed in as the employee whose sheet this is — identity says yes,
      // the lock must still say no.
      editableSelf: true,
    )));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // No pencil anywhere: not on the cell, and not in the banner either.
    expect(find.byIcon(Icons.edit_rounded), findsNothing);
    expect(find.byIcon(Icons.visibility_rounded), findsWidgets);
    expect(find.text('This quarter is completed — scores are locked.'),
        findsOneWidget);
    expect(find.text('You can edit the Self ratings on this sheet.'),
        findsNothing);
  });

  testWidgets(
      'an open month still offers the employee the Self edit affordance',
      (tester) async {
    final open = reviewWith(oneRow(), currentStage: ReviewStage.selfRating);
    await tester.pumpWidget(host(quarterlyKraSheetBodyForTest(
      now: afterTheQuarter,
      months: months,
      reviews: [open, null, null],
      editableSelf: true,
    )));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.edit_rounded), findsWidgets);
    expect(find.text('You can edit the Self ratings on this sheet.'),
        findsOneWidget);
  });

  testWidgets('a completed month offers the assigned reviewer no Rate button',
      (tester) async {
    final completed = reviewWith(oneRow(), currentStage: ReviewStage.completed);
    await tester.pumpWidget(host(quarterlyKraSheetBodyForTest(
      now: afterTheQuarter,
      months: months,
      reviews: [completed, null, null],
      // The reporting manager owns this KRA's Review cell by relationship.
      editableManager: true,
    )));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Rate'), findsNothing);
  });

  testWidgets('a completed month offers HR no Rate button', (tester) async {
    final completed = reviewWith(
      [rowFor('k2', 'HR compliances', KraReviewer.hr)],
      currentStage: ReviewStage.completed,
    );
    await tester.pumpWidget(host(quarterlyKraSheetBodyForTest(
      now: afterTheQuarter,
      months: months,
      reviews: [completed, null, null],
      editableHr: true,
    )));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Rate'), findsNothing);
  });

  testWidgets(
      'a locked month and an open month in one quarter are gated separately',
      (tester) async {
    // July finished; August is still on self-rating. The old sheet-wide banner
    // derived one verdict from the FIRST non-null review and applied it to all
    // three columns — so July would have kept its pencil.
    final july = reviewWith(oneRow(),
        currentStage: ReviewStage.completed,
        period: const ReviewPeriod(2026, 7));
    final august = reviewWith(oneRow(),
        currentStage: ReviewStage.selfRating,
        period: const ReviewPeriod(2026, 8));

    await tester.pumpWidget(host(quarterlyKraSheetBodyForTest(
      now: afterTheQuarter,
      months: months,
      reviews: [july, august, null],
      editableSelf: true,
    )));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // One month is open, so the sheet still advertises Self editing.
    expect(find.text('You can edit the Self ratings on this sheet.'),
        findsOneWidget);
    // Exactly two pencils: the banner's, plus August's Self cell. July's
    // locked cell and September's absent review contribute none.
    expect(find.byIcon(Icons.edit_rounded), findsNWidgets(2));
  });
}
