import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/rating_reopen.dart';
import 'package:vistar_app/features/reviews/data/models/rating_window.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// The rendered sheet once reviews carry server rating windows
/// (docs/RATING_ACCESS.md §4.2).
///
/// Every pair below renders the SAME scores twice and changes only a window,
/// so whatever differs on screen is the window's doing — the property the
/// pure-gate tests cannot show, because the grid composes the gates itself.
void main() {
  DateTime ist(int y, int m, int d, [int h = 0]) =>
      DateTime.utc(y, m, d, h).subtract(const Duration(hours: 5, minutes: 30));
  // Noon on 2 Oct 2026, IST: September is the open month; July and August are
  // past every deadline.
  final now = ist(2026, 10, 2, 12);

  const july = ReviewPeriod(2026, 7);
  const august = ReviewPeriod(2026, 8);
  const september = ReviewPeriod(2026, 9);
  const months = [july, august, september];

  // On the device's own calendar, so the notice's date reads the same in
  // every timezone the suite runs in.
  final oct31 = DateTime(2026, 10, 31, 23, 59, 59, 999);
  final oct20 = DateTime(2026, 10, 20, 23, 59, 59, 999);

  final rating = ReviewStage.values.where((s) => s.isRatingStage).toList();

  /// [stage]'s ordinary window for [month]: from the 1st to its deadline.
  RatingWindow deadline(ReviewPeriod month, ReviewStage stage) {
    final n = month.next;
    return RatingWindow(
      source: RatingWindowSource.deadline,
      closed: false,
      opensAt: ist(n.year, n.month, 1),
      closesAt: ist(n.year, n.month, stage.publishedDeadlineDay ?? 10, 23),
    );
  }

  RatingWindow reopened(ReviewPeriod month, DateTime until) => RatingWindow(
        source: RatingWindowSource.opened,
        closed: false,
        opensAt: ist(month.next.year, month.next.month, 1),
        closesAt: until,
      );

  RatingWindow forceClosed(ReviewPeriod month) => RatingWindow(
        source: RatingWindowSource.closed,
        closed: true,
        opensAt: ist(month.next.year, month.next.month, 1),
      );

  MonthlyKraRow kra({double? self}) {
    var r = const MonthlyKraRow(
      id: 'k1',
      name: 'Safety of the Facility',
      weightagePercent: 100,
      maxScore: 10,
      reviewerGroup: KraReviewer.reportingManager,
      displayOrder: 1,
    );
    if (self != null) {
      r = r.withStageScore(ReviewStage.selfRating, RowScore(value: self));
    }
    return r;
  }

  /// [month]'s review with every stage on its deadline except [overrides];
  /// [windows] false is an older backend that sends none.
  MonthlyReview review(
    ReviewPeriod month, {
    double? self = 8,
    Map<ReviewStage, RatingWindow> overrides = const {},
    bool windows = true,
    DateTime? lockedAt,
  }) =>
      MonthlyReview(
        id: 'r-${month.key}',
        employeeId: 'emp1',
        employeeName: 'Asha',
        managerId: 'mgr1',
        period: month,
        rows: [kra(self: self)],
        managementLockedAt: lockedAt,
        ratingWindows: windows
            ? {
                for (final s in rating) s: deadline(month, s),
                ...overrides,
              }
            : null,
      );

  Map<ReviewStage, RatingWindow> allReopened(ReviewPeriod m, DateTime until) =>
      {for (final s in rating) s: reopened(m, until)};

  Future<void> pump(
    WidgetTester tester,
    List<MonthlyReview?> reviews, {
    bool manager = false,
    bool self = false,
    Future<void> Function()? onLock,
  }) async {
    // Tall enough that the lazily built list reaches the bars under the grid.
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: quarterlyKraSheetBodyForTest(
          now: now,
          months: months,
          reviews: reviews,
          editableSelf: self,
          editableManager: manager,
          onLockManagement: onLock,
          onReopenManagement: onLock,
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  group('the reporting manager\'s Rate button follows the window', () {
    tearDown(RatingReopen.reset);

    testWidgets('offered on a closed month the super admin reopened',
        (tester) async {
      await pump(
          tester,
          [
            review(july, overrides: {
              ReviewStage.reportingManagerRating: reopened(july, oct31),
            }),
            null,
            null,
          ],
          manager: true);
      expect(find.text('Rate'), findsOneWidget);
    });

    testWidgets('not offered once its deadline has passed', (tester) async {
      await pump(tester, [review(july), null, null], manager: true);
      expect(find.text('Rate'), findsNothing);
    });

    testWidgets('and the client-side reopen cannot override a shut window',
        (tester) async {
      // RatingReopen would open this blank cell on its own. With a window
      // present the server's answer stands, and it would refuse the save.
      RatingReopen.adopt(RatingReopen.granted);
      await pump(tester, [review(july), null, null], manager: true);
      expect(find.text('Rate'), findsNothing);
    });
  });

  group('a cell that is not open says why', () {
    testWidgets('open window, no self score yet: the Self tag', (tester) async {
      await pump(
          tester,
          [
            review(july, self: null, overrides: {
              ReviewStage.reportingManagerRating: reopened(july, oct31),
            }),
            null,
            null,
          ],
          manager: true);
      expect(find.text('Self'), findsOneWidget);
      expect(find.text('Rate'), findsNothing,
          reason: 'the employee still rates first');
    });

    testWidgets('shut window: the bare dash, not a wait for the employee',
        (tester) async {
      await pump(tester, [review(july, self: null), null, null], manager: true);
      expect(find.text('Self'), findsNothing);
    });
  });

  testWidgets('a super-admin CLOSE shuts the open month\'s Self cell',
      (tester) async {
    Future<int> pencils(Map<ReviewStage, RatingWindow> overrides) async {
      await pump(tester, [null, null, review(september, overrides: overrides)],
          self: true);
      return find.byIcon(Icons.edit_rounded).evaluate().length;
    }

    final open = await pencils(const {});
    final closed =
        await pencils({ReviewStage.selfRating: forceClosed(september)});
    expect(closed, open - 1);
  });

  testWidgets('the banner names a month as due only while it can be rated',
      (tester) async {
    // September is the calendar's open month and nothing is self-rated. Once
    // its self window is closed the banner must not send the employee there.
    await pump(tester, [null, null, review(september, self: null)], self: true);
    expect(
        find.textContaining("Rate your Sep '26 Self column"), findsOneWidget);

    await pump(
        tester,
        [
          null,
          null,
          review(september,
              self: null,
              overrides: {ReviewStage.selfRating: forceClosed(september)}),
        ],
        self: true);
    expect(find.textContaining("Rate your Sep '26 Self column"), findsNothing);
  });

  testWidgets('the reviewer\'s Reason & proof needs its stage window too',
      (tester) async {
    Future<int> editableTiles(Map<ReviewStage, RatingWindow> overrides) async {
      await pump(tester, [review(july, overrides: overrides), null, null],
          manager: true);
      await tester.tap(find.byIcon(Icons.expand_more_rounded));
      await tester.pumpAndSettle();
      return find.text('Add reason & proof').evaluate().length;
    }

    expect(
        await editableTiles({
          ReviewStage.reportingManagerRating: reopened(july, oct31),
        }),
        1);
    expect(await editableTiles(const {}), 0,
        reason: 'past the 13 Aug deadline the save would be refused');
  });

  testWidgets('the lock bar\'s state follows the months it can act on',
      (tester) async {
    // August is signed off and its window is open; July's window shut with
    // July unsigned. The bar acts on August alone, so it offers Reopen — not
    // a Save & Lock that would re-lock August and be refused for July.
    await pump(
      tester,
      [
        review(july),
        review(august, lockedAt: ist(2026, 9, 14), overrides: {
          ReviewStage.managementReview: reopened(august, oct31),
        }),
        null,
      ],
      onLock: () async {},
    );
    expect(find.text('Reopen'), findsOneWidget);
    expect(find.text('Save & Lock'), findsNothing);
  });

  group('the reopened notice', () {
    testWidgets('names the July/August rollout seed, above the grid',
        (tester) async {
      const line =
          'July 2026 and August 2026 reopened for rating until 31 Oct 2026.';
      await pump(tester, [
        review(july, overrides: allReopened(july, oct31)),
        review(august, overrides: allReopened(august, oct31)),
        review(september),
      ]);
      expect(find.text(line), findsOneWidget);
      expect(tester.getTopLeft(find.text(line)).dy,
          lessThan(tester.getTopLeft(find.text('KRA')).dy));
    });

    testWidgets('names the one seat a single-stage reopen covers',
        (tester) async {
      await pump(tester, [
        review(july),
        review(august, overrides: {
          ReviewStage.accountHrRating: reopened(august, oct20),
        }),
        review(september),
      ]);
      expect(
          find.text('August 2026 (HR) reopened for rating until 20 Oct 2026.'),
          findsOneWidget);
    });

    testWidgets('is absent without a reopen, and moves nothing',
        (tester) async {
      // Typed as the screen builds it: the sheet's `firstWhere(orElse: () =>
      // null)` needs a list whose element type admits null.
      final quarter = <MonthlyReview?>[
        review(july),
        review(august),
        review(september),
      ];
      await pump(tester, [
        for (final m in months) review(m, windows: false),
      ]);
      expect(find.textContaining('reopened for rating'), findsNothing);
      final legacyTop = tester.getTopLeft(find.text('KRA'));

      await pump(tester, quarter);
      expect(find.textContaining('reopened for rating'), findsNothing);
      expect(tester.getTopLeft(find.text('KRA')), legacyTop,
          reason: 'deadline windows alone must not shift the grid');
    });
  });
}
