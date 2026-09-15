import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/data/models/stage_record.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// The reporting manager's own "Submit my review", mirroring the employee's
/// "Submit self-rating".
///
/// The manager's per-KRA scores already persist the moment the rating sheet
/// closes, so before this there was no explicit "I'm done" for them at all —
/// their only pipeline action on the sheet was "Send back for rework".
///
/// The rule that matters most here is SCOPE: each KRA is assigned to exactly
/// one Review-cycle reviewer, so the manager's submit must cover only the KRAs
/// assigned to them and never HR's or Accounts'.
void main() {
  MonthlyKraRow row(
    String id,
    KraReviewer? reviewer, {
    ReviewStage? ratedBy,
    double value = 8,
  }) {
    var r = MonthlyKraRow(
      id: id,
      name: 'KRA $id',
      weightagePercent: 25,
      maxScore: 10,
      reviewerGroup: reviewer,
    );
    if (ratedBy != null) {
      r = r.withStageScore(ratedBy, RowScore(value: value));
    }
    return r;
  }

  MonthlyReview review(
    List<MonthlyKraRow> rows, {
    String? managerId = 'mgr1',
    ReviewStage currentStage = ReviewStage.reportingManagerRating,
    Map<ReviewStage, StageRecord> stageRecords = const {},
    ReviewPeriod period = const ReviewPeriod(2026, 7),
  }) =>
      MonthlyReview(
        id: 'r1',
        employeeId: 'emp1',
        employeeName: 'Asha',
        managerId: managerId,
        period: period,
        currentStage: currentStage,
        stageRecords: stageRecords,
        rows: rows,
      );

  group('managerAssignedKras — scope', () {
    test('keeps only reporting-manager rows, dropping HR and Accounts', () {
      final r = review([
        row('a', KraReviewer.reportingManager),
        row('b', KraReviewer.hr),
        row('c', KraReviewer.accounts),
        row('d', KraReviewer.reportingManager),
      ]);
      expect(managerAssignedKras(r).map((x) => x.id), ['a', 'd']);
    });

    test('treats a legacy row with no assigned reviewer as the manager\'s', () {
      final r = review([row('legacy', null)]);
      expect(managerAssignedKras(r).map((x) => x.id), ['legacy']);
    });
  });

  group('managerRatedKraCount', () {
    test('counts only the manager\'s own rows that carry a manager score', () {
      final r = review([
        row('a', KraReviewer.reportingManager,
            ratedBy: ReviewStage.reportingManagerRating),
        row('b', KraReviewer.reportingManager), // assigned, unrated
        row('c', KraReviewer.hr, ratedBy: ReviewStage.accountHrRating),
      ]);
      expect(managerRatedKraCount(r), 1);
    });

    test('ignores a self score sitting on the manager\'s own row', () {
      final r = review([
        row('a', KraReviewer.reportingManager, ratedBy: ReviewStage.selfRating),
      ]);
      expect(managerRatedKraCount(r), 0);
    });

    test('counts an honest zero as rated', () {
      final r = review([
        row('a', KraReviewer.reportingManager,
            ratedBy: ReviewStage.reportingManagerRating, value: 0),
      ]);
      expect(managerRatedKraCount(r), 1);
    });
  });

  group('managerCanSubmitReview', () {
    // A month must have ENDED before it can be submitted, so the clock has to
    // be later than the reviews under test (all July). September also makes
    // August the live month, which the last test in this group relies on.
    final now = DateTime(2026, 9, 5);

    final rated = row('a', KraReviewer.reportingManager,
        ratedBy: ReviewStage.reportingManagerRating);

    test('yes once the manager has rated one of their own KRAs', () {
      expect(managerCanSubmitReview(review([rated]), 'mgr1', now: now), isTrue);
    });

    test('no for anyone who is not this review\'s reporting manager', () {
      expect(managerCanSubmitReview(review([rated]), 'someone-else', now: now),
          isFalse);
      // The employee themselves must not get the manager's submit.
      expect(
          managerCanSubmitReview(review([rated]), 'emp1', now: now), isFalse);
    });

    test('no when the review has no manager mapped — fails closed', () {
      expect(
          managerCanSubmitReview(review([rated], managerId: null), 'mgr1',
              now: now),
          isFalse);
    });

    test('no when both ids are blank — a blank must not match a blank', () {
      // Fails open otherwise: '' == '' would authorise an unidentified viewer.
      expect(
          managerCanSubmitReview(review([rated], managerId: ''), '', now: now),
          isFalse);
    });

    test('no when nothing of theirs is rated', () {
      final r = review([row('a', KraReviewer.reportingManager)]);
      expect(managerCanSubmitReview(r, 'mgr1', now: now), isFalse);
    });

    test('no when ONLY an HR-assigned KRA is rated — this is the scope rule',
        () {
      final r = review([
        row('hrOnly', KraReviewer.hr, ratedBy: ReviewStage.accountHrRating),
        row('mine', KraReviewer.reportingManager), // theirs, still unrated
      ]);
      expect(managerCanSubmitReview(r, 'mgr1', now: now), isFalse);
    });

    test('no once already submitted — the stage record proves it', () {
      final r = review([
        rated
      ], stageRecords: {
        ReviewStage.reportingManagerRating: StageRecord(
          actorId: 'mgr1',
          actorName: 'Manager',
          submittedAt: DateTime(2026, 8, 2),
        ),
      });
      expect(managerCanSubmitReview(r, 'mgr1', now: now), isFalse);
    });

    test('no on a completed month — scores are locked server-side', () {
      final r = review([rated], currentStage: ReviewStage.completed);
      expect(managerCanSubmitReview(r, 'mgr1', now: now), isFalse);
    });

    test('yes even when the cursor has moved past the manager stage', () {
      // A backend that auto-advances on save would otherwise make the button
      // unreachable; a server that really disagrees answers 409 instead.
      final r = review([rated], currentStage: ReviewStage.accountHrRating);
      expect(managerCanSubmitReview(r, 'mgr1', now: now), isTrue);
    });

    test('NO on a month that has not ended yet', () {
      // Submitting freezes a partial rating: it advances the review and
      // snapshots the weighted manager percentage into the computed score for
      // a month still in progress, and the bar then disappears because the
      // stage record exists. On 5 September, August is the live month.
      final live = review([rated], period: const ReviewPeriod(2026, 9));
      expect(managerCanSubmitReview(live, 'mgr1', now: now), isFalse,
          reason: 'September has not finished on 5 September');
    });

    test('and NO on a future month, however well rated', () {
      final ahead = review([rated], period: const ReviewPeriod(2026, 12));
      expect(managerCanSubmitReview(ahead, 'mgr1', now: now), isFalse);
    });

    test('yes on an older month — a late submission is still allowed', () {
      // The rule closes the FUTURE direction only. A manager catching up on a
      // month they missed must not be blocked.
      final old = review([rated], period: const ReviewPeriod(2026, 5));
      expect(managerCanSubmitReview(old, 'mgr1', now: now), isTrue);
    });
  });

  group('the bar itself', () {
    Widget host(Widget child) => MediaQuery(
          data: const MediaQueryData(size: Size(1280, 900)),
          child: MaterialApp(home: Scaffold(body: child)),
        );

    const months = [
      ReviewPeriod(2026, 7),
      ReviewPeriod(2026, 8),
      ReviewPeriod(2026, 9),
    ];
    final afterTheQuarter = DateTime(2026, 11, 3);

    testWidgets('renders with its label and hint, and fires on tap',
        (tester) async {
      var fired = 0;
      await tester.pumpWidget(host(quarterlyKraSheetBodyForTest(
        now: afterTheQuarter,
        months: months,
        reviews: [
          review([
            row('a', KraReviewer.reportingManager,
                ratedBy: ReviewStage.reportingManagerRating)
          ]),
          null,
          null,
        ],
        editableManager: true,
        onSubmitManagerReview: () async => fired++,
      )));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Submit my review'), findsOneWidget);
      expect(
          find.text(
              'Rated the KRAs assigned to you? Submit to finalise your review.'),
          findsOneWidget);

      await tester.tap(find.text('Submit my review'));
      await tester.pump();
      expect(fired, 1);
    });

    testWidgets('is absent when no manager-submit action is supplied',
        (tester) async {
      await tester.pumpWidget(host(quarterlyKraSheetBodyForTest(
        now: afterTheQuarter,
        months: months,
        reviews: [
          review([row('a', KraReviewer.reportingManager)]),
          null,
          null,
        ],
        editableManager: true,
      )));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Submit my review'), findsNothing);
    });

    testWidgets('does not displace the employee\'s own submit bar',
        (tester) async {
      await tester.pumpWidget(host(quarterlyKraSheetBodyForTest(
        now: afterTheQuarter,
        months: months,
        reviews: [
          review([
            row('a', KraReviewer.reportingManager,
                ratedBy: ReviewStage.selfRating)
          ]),
          null,
          null,
        ],
        editableSelf: true,
        onSubmitSelfRating: () async {},
      )));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Submit self-rating'), findsOneWidget);
      expect(find.text('Submit my review'), findsNothing);
    });
  });
}
