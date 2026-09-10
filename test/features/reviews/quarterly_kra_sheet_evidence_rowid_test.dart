import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/features/reviews/data/models/incentive_snapshot.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// Reason & Proof must be keyed by THE MONTH'S OWN row id.
///
/// Reported from the live sheet: an employee typed a reason into the Aug '26
/// Employee slot, tapped Save, got no error — and the card still read "Add
/// reason & proof". Jul '26 worked. Sep '26 did not.
///
/// The backend mints `monthly_review_rows.id` with `randomUUID()` PER REVIEW,
/// so one KRA has a DIFFERENT id in each of the quarter's three months, while
/// the sheet takes its canonical row list from the first month present. The
/// evidence path passed that canonical id straight through to the save, and
/// the server's write is
///
///   INSERT ... SELECT ... WHERE EXISTS (mrr.id = $2 AND mrr.review_id = $6)
///
/// so July's id against the August review matched nothing: zero rows inserted,
/// HTTP 200, no error. `_scoreCell` had already been fixed to resolve
/// `_monthRowId`; the evidence path had not.
///
/// These fixtures give the SAME KRA a different id in every month — the shape
/// the real backend produces. A test whose three months share an id cannot
/// fail on this bug, which is why every case below asserts against ids that
/// differ.
void main() {
  // Same KRA, three months, three different row ids — as the server mints them.
  const idJul = 'row-uuid-jul', idAug = 'row-uuid-aug', idSep = 'row-uuid-sep';

  MonthlyKraRow kra(String id, {RowScore? self}) => MonthlyKraRow(
        id: id,
        name: 'Billing data verification',
        weightagePercent: 100,
        maxScore: 10,
        reviewerGroup: KraReviewer.accounts,
        displayOrder: 0,
        stageScores: {if (self != null) ReviewStage.selfRating: self},
      );

  MonthlyReview review(String id, ReviewPeriod p, MonthlyKraRow row) =>
      MonthlyReview(
        id: id,
        employeeId: 'emp1',
        employeeName: 'Temp',
        period: p,
        currentStage: ReviewStage.selfRating,
        stageRecords: const {},
        rows: [row],
        incentive: const IncentiveSnapshot(),
      );

  const months = [
    ReviewPeriod(2026, 7),
    ReviewPeriod(2026, 8),
    ReviewPeriod(2026, 9),
  ];
  // Past the quarter, so all three months are ratable and editable.
  final now = DateTime(2026, 10, 15);

  /// Every (reviewId, rowId) pair the sheet asked `fileNameFor` about.
  ///
  /// The PAIRING is the invariant, not the ids on their own: the screen-side
  /// lookup resolves by exact id, and so does the server. Asking review
  /// `r-aug` for `row-uuid-jul` is precisely the defect — a row id from
  /// another month.
  late List<({String reviewId, String rowId})> asked;

  /// Which row ids each review actually contains.
  const owned = {
    'r-jul': idJul,
    'r-aug': idAug,
    'r-sep': idSep,
  };

  Widget host({
    RowScore? julSelf,
    RowScore? augSelf,
    RowScore? sepSelf,
    void Function({
      required MonthlyReview review,
      required String rowId,
      required ReviewStage stage,
    })? onJustify,
  }) {
    asked = [];
    return MediaQuery(
      data: const MediaQueryData(size: Size(1600, 1000)),
      child: MaterialApp(
        home: Scaffold(
          body: quarterlyKraSheetBodyForTest(
            now: now,
            months: months,
            reviews: [
              review('r-jul', months[0], kra(idJul, self: julSelf)),
              review('r-aug', months[1], kra(idAug, self: augSelf)),
              review('r-sep', months[2], kra(idSep, self: sepSelf)),
            ],
            editableSelf: true,
            // The Accounts reviewer slot stays READ-ONLY on purpose. An
            // editable one also renders "Add reason & proof", which would
            // double the matches and make the .at(n) indices below land on the
            // wrong card. With only the employee slot editable, index == month.
            editableFinance: false,
            onFileNameFor: (reviewId, rowId) =>
                asked.add((reviewId: reviewId, rowId: rowId)),
            onJustify: onJustify,
          ),
        ),
      ),
    );
  }

  Future<void> expand(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.expand_more_rounded));
    await tester.pumpAndSettle();
  }

  /// Tap the Nth "Add reason & proof" — index N is month N, because only the
  /// employee slot is editable here.
  ///
  /// `ensureVisible` first: the quarter's third card sits outside the viewport
  /// at these dimensions, and `tap` on an off-screen widget silently misses
  /// (it only warns), which reads as "the callback was never invoked" rather
  /// than as a scrolling problem.
  Future<void> tapEvidence(WidgetTester tester, int month) async {
    final target = find.text('Add reason & proof').at(month);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  group('the evidence panel reads each month by ITS OWN row id', () {
    testWidgets('never asks for a row id that month does not contain',
        (tester) async {
      await tester.pumpWidget(host());
      await expand(tester);

      expect(asked, isNotEmpty,
          reason: 'the panel must actually perform lookups');

      // THE INVARIANT, stated generally: no review is ever asked about a row
      // id it does not contain. Asserting only that all three ids appear
      // SOMEWHERE is too weak — `_anyJustified` alone satisfies that while the
      // tiles are still asking every month for July's id.
      final foreign = asked
          .where((a) => owned[a.reviewId] != a.rowId)
          .map((a) => '${a.reviewId} asked for ${a.rowId}')
          .toSet();
      expect(foreign, isEmpty,
          reason: 'a row id from another month reaches the server verbatim, '
              'where WHERE EXISTS matches nothing and the write is dropped');

      // And every month really was consulted, so the check above cannot pass
      // by doing no work.
      expect(asked.map((a) => a.reviewId).toSet(), owned.keys.toSet());
    });

    testWidgets('a reason stored on the AUGUST row is displayed',
        (tester) async {
      // The exact reported case: only August carries a remark.
      await tester.pumpWidget(host(
        augSelf: const RowScore(value: 10, remark: 'Billing submitted on time'),
      ));
      await expand(tester);

      expect(find.text('Billing submitted on time'), findsOneWidget,
          reason: 'August evidence must render in the August card');
    });

    testWidgets('a reason stored on the SEPTEMBER row is displayed',
        (tester) async {
      await tester.pumpWidget(host(
        sepSelf: const RowScore(value: 9, remark: 'Sep evidence filed'),
      ));
      await expand(tester);

      expect(find.text('Sep evidence filed'), findsOneWidget);
    });

    testWidgets('all three months render their own distinct reasons',
        (tester) async {
      await tester.pumpWidget(host(
        julSelf: const RowScore(value: 8, remark: 'July reason'),
        augSelf: const RowScore(value: 9, remark: 'August reason'),
        sepSelf: const RowScore(value: 10, remark: 'September reason'),
      ));
      await expand(tester);

      // Before the fix July's would have rendered three times.
      expect(find.text('July reason'), findsOneWidget);
      expect(find.text('August reason'), findsOneWidget);
      expect(find.text('September reason'), findsOneWidget);
    });
  });

  group('the SAVE is aimed at the month the user is editing', () {
    // The write defect. A canonical id sent for August matches no row in the
    // August review, so the server inserts nothing and returns 200 — the
    // employee's typing is discarded with no error.
    testWidgets('editing August targets the August row id', (tester) async {
      String? sentRowId;
      String? sentReviewId;
      await tester.pumpWidget(host(
        onJustify: ({required review, required rowId, required stage}) {
          sentRowId = rowId;
          sentReviewId = review.id;
        },
      ));
      await expand(tester);

      // Employee slot of the middle (August) card.
      await tapEvidence(tester, 1);

      expect(sentReviewId, 'r-aug');
      expect(sentRowId, idAug,
          reason: 'sending the canonical July id here is the reported bug: '
              'the server matches nothing and silently saves nothing');
    });

    testWidgets('editing September targets the September row id',
        (tester) async {
      String? sentRowId;
      String? sentReviewId;
      await tester.pumpWidget(host(
        onJustify: ({required review, required rowId, required stage}) {
          sentRowId = rowId;
          sentReviewId = review.id;
        },
      ));
      await expand(tester);

      await tapEvidence(tester, 2);

      expect(sentReviewId, 'r-sep');
      expect(sentRowId, idSep);
    });

    testWidgets('editing July still targets July — the case that worked',
        (tester) async {
      String? sentRowId;
      await tester.pumpWidget(host(
        onJustify: ({required review, required rowId, required stage}) =>
            sentRowId = rowId,
      ));
      await expand(tester);

      await tapEvidence(tester, 0);

      expect(sentRowId, idJul,
          reason: 'the fix must not break the one month that was correct');
    });
  });
}
