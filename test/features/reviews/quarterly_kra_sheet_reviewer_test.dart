import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/features/reviews/data/models/incentive_snapshot.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// Guards the single-reviewer redesign of the quarterly KRA sheet Review
/// column: each KRA is owned by exactly ONE reviewer (never an average of
/// three), and an unrated KRA shows an explicit "<reviewer> pending" status.
void main() {
  /// Rows carry a SELF score by default.
  ///
  /// A Review cell only opens once the employee has rated that KRA — rating
  /// first inverts the pipeline and would let the reporting manager set the
  /// ceiling for a number the employee has not chosen. These tests are about
  /// WHICH reviewer owns a KRA, so they start from a self-rated sheet; pass
  /// `selfScore: null` for the un-self-rated case.
  MonthlyKraRow rowFor(String id, String name, KraReviewer reviewer,
      {double? reviewerScore, double? selfScore = 7}) {
    var row = MonthlyKraRow(
      id: id,
      name: name,
      weightagePercent: 100 / 3,
      maxScore: 10,
      reviewerGroup: reviewer,
      displayOrder: id.hashCode & 0x7,
    );
    if (selfScore != null) {
      row = row.withStageScore(
          ReviewStage.selfRating, RowScore(value: selfScore));
    }
    if (reviewerScore != null) {
      row =
          row.withStageScore(row.reviewStage!, RowScore(value: reviewerScore));
    }
    return row;
  }

  MonthlyReview reviewWith(List<MonthlyKraRow> rows) => MonthlyReview(
        id: 'r',
        employeeId: 'emp1',
        employeeName: 'Asha',
        period: const ReviewPeriod(2026, 7),
        currentStage: ReviewStage.selfRating,
        rows: rows,
        incentive: const IncentiveSnapshot(),
      );

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
      'each KRA shows its single assigned reviewer, not a three-rater average',
      (tester) async {
    final review = reviewWith([
      rowFor('k1', 'On-time dispatch', KraReviewer.reportingManager),
      rowFor('k2', 'HR compliances', KraReviewer.hr),
      rowFor('k3', 'Debits by customer', KraReviewer.accounts),
    ]);
    await tester.pumpWidget(host(
      const Size(1280, 900),
      quarterlyKraSheetBodyForTest(
        months: months,
        reviews: [review, null, null],
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // Per-KRA reviewer badge — one owner each, not a shared panel.
    expect(find.text('Reviewed by Manager'), findsOneWidget);
    expect(find.text('Reviewed by HR'), findsOneWidget);
    expect(find.text('Reviewed by Accounts'), findsOneWidget);
    // The old averaging model is gone entirely.
    expect(find.textContaining('average is the Review score'), findsNothing);
  });

  testWidgets('an unrated, view-only KRA shows a pending status (no Rate)',
      (tester) async {
    final review = reviewWith([
      rowFor('k2', 'HR compliances', KraReviewer.hr),
    ]);
    await tester.pumpWidget(host(
      const Size(1280, 900),
      quarterlyKraSheetBodyForTest(
        months: months,
        reviews: [review, null, null],
        // Not the employee, not the manager, not HR/Finance/management.
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // Pending clock renders (in the cell) — the KRA is waiting on its reviewer.
    expect(find.byIcon(Icons.schedule_rounded), findsWidgets);
    // A non-owner never sees a Rate affordance.
    expect(find.text('Rate'), findsNothing);
  });

  testWidgets('the assigned reviewer sees a Rate affordance while unrated',
      (tester) async {
    final review = reviewWith([
      rowFor('k1', 'On-time dispatch', KraReviewer.reportingManager),
    ]);
    await tester.pumpWidget(host(
      const Size(1280, 900),
      quarterlyKraSheetBodyForTest(
        months: months,
        reviews: [review, null, null],
        // The reporting manager owns the Review cell for a RM-assigned KRA.
        editableManager: true,
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Rate'), findsWidgets);
  });

  testWidgets('a rated KRA shows the single reviewer score', (tester) async {
    final review = reviewWith([
      rowFor('k1', 'On-time dispatch', KraReviewer.reportingManager,
          reviewerScore: 9),
    ]);
    await tester.pumpWidget(host(
      const Size(1280, 900),
      quarterlyKraSheetBodyForTest(
        months: months,
        reviews: [review, null, null],
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // 9/10 → 90% in the Review cell (and echoed in the Qtr Review column).
    expect(find.text('90%'), findsWidgets);
  });

  testWidgets('HR can act on an HR-assigned KRA (Rate affordance)',
      (tester) async {
    final review = reviewWith([
      rowFor('k2', 'HR compliances', KraReviewer.hr),
    ]);
    await tester.pumpWidget(host(
      const Size(1280, 900),
      quarterlyKraSheetBodyForTest(
        months: months,
        reviews: [review, null, null],
        editableHr: true, // signed in as HR
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // HR owns the Review cell for an HR-assigned KRA, so it's editable.
    expect(find.text('Rate'), findsWidgets);
  });

  testWidgets('Accounts can act on an Accounts-assigned KRA (Rate affordance)',
      (tester) async {
    final review = reviewWith([
      rowFor('k3', 'Debits/Deductions', KraReviewer.accounts),
    ]);
    await tester.pumpWidget(host(
      const Size(1280, 900),
      quarterlyKraSheetBodyForTest(
        months: months,
        reviews: [review, null, null],
        editableFinance: true, // signed in as Accounts / Finance
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Rate'), findsWidgets);
  });

  testWidgets('HR can add Reason & proof for an HR-assigned KRA',
      (tester) async {
    // Expanding the panel reveals the reviewer evidence tile; for an HR user on
    // an HR-assigned KRA it must be editable (an "edit" affordance, not a
    // view-only eye), so HR can attach proof + reason.
    final review = reviewWith([
      rowFor('k2', 'HR compliances', KraReviewer.hr),
    ]);
    await tester.pumpWidget(host(
      const Size(1280, 900),
      quarterlyKraSheetBodyForTest(
        months: months,
        reviews: [review, null, null],
        editableHr: true,
      ),
    ));
    await tester.pump();

    // Open the per-KRA Reason & proof panel.
    await tester.tap(find.text('Reason & proof').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The reviewer evidence tile is labelled for HR and offers an edit action.
    expect(find.textContaining('Reviewer · HR'), findsWidgets);
    expect(find.byIcon(Icons.edit_rounded), findsWidgets);
  });
}
