import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/rating_window.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// Management's Save & Lock / Reopen bar across a PART-LOCKED quarter.
///
/// Reported as "I reopened the August rating from the super-admin login and it
/// still is not reflecting". Two different locks were being conflated, and the
/// bar made that unrecoverable:
///
///   * the rating WINDOW — the super admin's Organizations → Rating access —
///     decides when management may write at all;
///   * the review's own `managementLockedAt` — Save & Lock — decides whether
///     the incentive is settled. The Management cells stay read-only while it
///     is set, whatever the window says.
///
/// The bar took one `locked` flag meaning "EVERY month is locked" and showed
/// Reopen only then. Opening August's window brought a locked August back into
/// the bar's scope beside an unlocked July and September, which flipped that
/// flag false and REMOVED the Reopen button — so the act of reopening the month
/// is what took away the only control that could unlock it.
void main() {
  // 13 Oct 2026 IST, the date it was reported. July and August run on the
  // seeded reopen to 31 Oct; September is inside its own deadline.
  DateTime ist(int y, int m, int d, [int h = 0]) =>
      DateTime.utc(y, m, d, h).subtract(const Duration(hours: 5, minutes: 30));
  final now = ist(2026, 10, 13, 12);
  final openUntil = ist(2026, 10, 31, 23);

  const july = ReviewPeriod(2026, 7);
  const august = ReviewPeriod(2026, 8);
  const september = ReviewPeriod(2026, 9);
  const months = [july, august, september];

  RatingWindow open(ReviewPeriod m) => RatingWindow(
        source: RatingWindowSource.opened,
        closed: false,
        opensAt: ist(m.next.year, m.next.month, 1),
        closesAt: openUntil,
      );

  Map<ReviewStage, RatingWindow> allOpen(ReviewPeriod m) => {
        for (final s in ReviewStage.values)
          if (s.isRatingStage) s: open(m),
      };

  MonthlyReview month(ReviewPeriod period, {required bool locked}) =>
      MonthlyReview(
        id: 'r-${period.key}',
        employeeId: 'emp1',
        employeeName: 'Amol Laxman Veer',
        period: period,
        currentStage: ReviewStage.managementReview,
        rows: [
          const MonthlyKraRow(
            id: 'kra-0',
            name: 'Quarterly review with customer',
            weightagePercent: 100,
            maxScore: 10,
            displayOrder: 0,
          ).withStageScore(ReviewStage.selfRating, const RowScore(value: 10)),
        ],
        ratingWindows: allOpen(period),
        managementLockedAt: locked ? ist(2026, 10, 1) : null,
      );

  Future<void> pump(WidgetTester tester, List<MonthlyReview?> reviews) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: quarterlyKraSheetBodyForTest(
          months: months,
          reviews: reviews,
          now: now,
          editableManagement: true,
          onLockManagement: () async {},
          onReopenManagement: () async {},
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  testWidgets('a part-locked quarter offers BOTH actions', (tester) async {
    // The reported state: August locked, July and September not.
    await pump(tester, [
      month(july, locked: false),
      month(august, locked: true),
      month(september, locked: false),
    ]);

    // The whole bug: this used to be absent, because not every month was
    // locked, leaving August unreachable from anywhere in the app.
    expect(find.text('Reopen'), findsOneWidget);
    // And the unlocked months must still be lockable in the same breath.
    expect(find.text('Save & Lock'), findsOneWidget);
  });

  testWidgets('and says how much of the quarter is locked', (tester) async {
    // "Management review" alone gave no hint that one month was settled, so
    // nothing on screen explained why one Mgmt column would not open.
    await pump(tester, [
      month(july, locked: false),
      month(august, locked: true),
      month(september, locked: false),
    ]);

    expect(find.textContaining('1 of 3 months locked'), findsOneWidget);
    // The sentence that resolves the reported confusion directly.
    expect(
      find.textContaining('reopening a month for rating does not unlock it'),
      findsOneWidget,
    );
  });

  testWidgets('a fully locked quarter is unchanged — Reopen only',
      (tester) async {
    await pump(tester, [
      month(july, locked: true),
      month(august, locked: true),
      month(september, locked: true),
    ]);

    expect(find.text('Reopen'), findsOneWidget);
    expect(find.text('Save & Lock'), findsNothing);
    expect(find.text('Management review locked'), findsOneWidget);
  });

  testWidgets('a quarter with nothing locked is unchanged — Save & Lock only',
      (tester) async {
    await pump(tester, [
      month(july, locked: false),
      month(august, locked: false),
      month(september, locked: false),
    ]);

    expect(find.text('Save & Lock'), findsOneWidget);
    expect(find.text('Reopen'), findsNothing);
    expect(find.text('Management review'), findsOneWidget);
  });

  testWidgets('a missing month is not counted as locked or as open',
      (tester) async {
    // 1 of 2, not 1 of 3: a month with no review is not a month anybody can
    // lock, and counting it would misstate the quarter.
    await pump(tester, [
      month(july, locked: true),
      null,
      month(september, locked: false),
    ]);

    expect(find.textContaining('1 of 2 months locked'), findsOneWidget);
  });

  testWidgets('both buttons stay on screen at 360 px', (tester) async {
    // Stacked rather than side by side: side by side, the two buttons and the
    // explanation compete for one phone-width Row, and the Expanded text is
    // what gives — squeezed towards nothing while the buttons keep their
    // intrinsic width. Stacking costs height, which this bar has.
    tester.view.physicalSize = const Size(360, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: quarterlyKraSheetBodyForTest(
          months: months,
          reviews: [
            month(july, locked: false),
            month(august, locked: true),
            month(september, locked: false),
          ],
          now: now,
          editableManagement: true,
          onLockManagement: () async {},
          onReopenManagement: () async {},
        ),
      ),
    ));
    await tester.pump();

    // The sheet ALREADY overflows at a true 360 px surface, in two places that
    // predate this bar: the header card's month-nav Row (22 px) and the payout
    // card's label/value rows (14 and 27 px). Both were confirmed against the
    // unmodified file. Draining them is what lets this test fail only for the
    // bar — and the assertion below is on the buttons' own rects, which is how
    // a bar that did not fit would actually show up.
    tester.takeException();

    for (final label in ['Save & Lock', 'Reopen']) {
      final rect = tester.getRect(find.text(label));
      expect(rect.right, lessThanOrEqualTo(360.0), reason: '$label runs off');
      expect(rect.left, greaterThanOrEqualTo(0.0), reason: '$label runs off');
    }
  });
}
