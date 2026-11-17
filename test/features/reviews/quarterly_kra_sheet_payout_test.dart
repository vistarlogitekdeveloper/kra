import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/constants/app_strings.dart';
import 'package:vistar_app/features/reviews/data/models/incentive_snapshot.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// The payout card is where a quarter gets settled.
///
/// It was reported as "the incentive payout option is not coming" on a sheet
/// whose KRAs were all rated — because the sheet had no payout control at all,
/// and the only one that existed (a per-month icon on another screen) rendered
/// nothing when a gate was unmet. Both halves are asserted here: the action is
/// ON the card, and a quarter that is not payable says why instead of hiding.
void main() {
  MonthlyReview month(
    int m, {
    double eligible = 40000,
    double finalPct = 50,
    bool locked = true,
    PayoutStatus payout = PayoutStatus.pending,
  }) {
    const row = MonthlyKraRow(
      id: 'k1',
      name: 'Business development',
      weightagePercent: 100,
      maxScore: 100,
    );
    return MonthlyReview(
      id: 'r-$m',
      employeeId: 'emp1',
      employeeName: 'Dattatraya',
      period: ReviewPeriod(2026, m),
      currentStage: ReviewStage.managementReview,
      stageRecords: const {},
      rows: [
        row.withStageScore(
          ReviewStage.managementReview,
          RowScore(value: finalPct),
        ),
      ],
      incentive: IncentiveSnapshot(
        eligibleAmount: eligible,
        payoutStatus: payout,
      ),
      managementLockedAt: locked ? DateTime.utc(2026, 10, 5) : null,
    );
  }

  const months = [
    ReviewPeriod(2026, 7),
    ReviewPeriod(2026, 8),
    ReviewPeriod(2026, 9),
  ];

  Widget host(Widget child) => MediaQuery(
        data: const MediaQueryData(size: Size(1400, 1400)),
        child: MaterialApp(home: Scaffold(body: child)),
      );

  Future<void> pumpSheet(
    WidgetTester tester, {
    required List<MonthlyReview?> reviews,
    Future<void> Function()? onMarkQuarterPaid,
    DateTime? now,
  }) async {
    await tester.pumpWidget(host(quarterlyKraSheetBodyForTest(
      months: months,
      reviews: reviews,
      now: now ?? DateTime.utc(2026, 10, 20),
      onMarkQuarterPaid: onMarkQuarterPaid,
    )));
    await tester.pump();
    // The card sits below the grid.
    await tester.dragUntilVisible(
      find.text(AppStrings.quarterlyPayoutTitle),
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.pump();
  }

  testWidgets('a payable quarter offers one button for the whole quarter',
      (tester) async {
    var taps = 0;
    await pumpSheet(
      tester,
      reviews: [month(7), month(8), month(9)],
      onMarkQuarterPaid: () async => taps++,
    );

    expect(find.text(AppStrings.quarterPayoutMarkPaid), findsOneWidget);

    await tester.tap(find.text(AppStrings.quarterPayoutMarkPaid));
    await tester.pump();
    expect(taps, 1, reason: 'one tap settles the quarter, not three');
  });

  testWidgets('an unfinished month replaces the button with the reason',
      (tester) async {
    await pumpSheet(
      tester,
      // September is over but was never signed off.
      reviews: [month(7), month(8), month(9, locked: false)],
      onMarkQuarterPaid: () async {},
    );

    expect(find.text(AppStrings.quarterPayoutMarkPaid), findsNothing);
    // Names the month AND what clears it — the thing a vanished button could
    // never say.
    expect(
      find.textContaining('September 2026'),
      findsWidgets,
    );
    expect(find.textContaining('Save & Lock'), findsWidgets);
  });

  testWidgets('a settled quarter reads as paid and offers nothing',
      (tester) async {
    await pumpSheet(
      tester,
      reviews: [
        for (final m in [7, 8, 9]) month(m, payout: PayoutStatus.paid),
      ],
      onMarkQuarterPaid: () async {},
    );

    expect(find.text(AppStrings.quarterPayoutPaidBadge), findsOneWidget);
    expect(find.text(AppStrings.quarterPayoutMarkPaid), findsNothing);
  });

  testWidgets('a viewer with no payout seat sees no control at all',
      (tester) async {
    // Null callback = cannot pay any quarter. Nothing about this quarter
    // would change that, so there is nothing to explain.
    await pumpSheet(tester, reviews: [month(7), month(8), month(9)]);

    expect(find.text(AppStrings.quarterPayoutMarkPaid), findsNothing);
    expect(find.text(AppStrings.quarterPayoutPaidBadge), findsNothing);
  });

  testWidgets('the card shows the per-month working behind the total',
      (tester) async {
    await pumpSheet(
      tester,
      reviews: [
        month(7, eligible: 40000, finalPct: 50),
        month(8, eligible: 60000, finalPct: 100),
        month(9, eligible: 60000, finalPct: 100),
      ],
      onMarkQuarterPaid: () async {},
    );

    // ₹20,000 + ₹60,000 + ₹60,000. The old rule (highest month × 3 × average
    // final) would have shown ₹1,50,000 for the same quarter.
    expect(find.textContaining('₹1,40,000'), findsWidgets);
    expect(find.textContaining('July 2026'), findsWidgets);
  });
}
