import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/review_flow.dart';
import 'package:vistar_app/features/hr/presentation/widgets/rating_access/rating_access_copy.dart';
import 'package:vistar_app/features/reviews/data/models/rating_access.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';

import 'rating_access_fakes.dart';
import 'rating_access_harness.dart';

/// The super admin's writes from the rating-access screen: each control sends
/// exactly the override the contract describes (docs/RATING_ACCESS.md §3.5),
/// then the card shows what the server now resolves.
void main() {
  FakeRatingAccessRepository augustRepo(
          {ReviewFlow flow = ReviewFlow.standard}) =>
      FakeRatingAccessRepository(months: {august.key: mixedAugust(flow: flow)});

  const rm = 'Reporting-manager rating';

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> submitSheet(WidgetTester tester) =>
      tapAndSettle(tester, find.widgetWithText(FilledButton, 'Open'));

  group('one stage', () {
    testWidgets('Close now confirms, sends CLOSED, and shows the result',
        (tester) async {
      final h = await pumpRatingAccess(tester, repo: augustRepo());

      await tapAndSettle(tester, inStageCard(rm, 'Close now'));
      expect(find.text('Close $rm for August 2026?'), findsOneWidget);
      await tapAndSettle(tester, inDialog('Close now'));

      final call = h.repo.sets.single;
      expect(call.organizationId, 'org-1');
      expect(call.period, august);
      expect(call.stage, ReviewStage.reportingManagerRating);
      expect(call.mode, RatingAccessMode.closed);
      expect(call.openUntilDate, isNull);
      expect(inStageCard(rm, 'Closed by super admin'), findsOneWidget);
      expect(find.text('$rm closed.'), findsOneWidget);
      expect(h.repo.monthFetches, hasLength(2), reason: 'refetched');
      expect(h.repo.historyFetches, 2);
    });

    testWidgets('cancelling the confirmation sends nothing', (tester) async {
      final h = await pumpRatingAccess(tester, repo: augustRepo());

      await tapAndSettle(tester, inStageCard(rm, 'Close now'));
      await tapAndSettle(tester, inDialog('Cancel'));

      expect(h.repo.sets, isEmpty);
    });

    testWidgets('Open until… with no end date and a reason', (tester) async {
      final h = await pumpRatingAccess(tester, repo: augustRepo());

      await tapAndSettle(tester, inStageCard(rm, 'Open until…'));
      expect(find.text('Open $rm until…'), findsOneWidget);
      await tapAndSettle(tester, find.byType(SwitchListTile));
      expect(find.textContaining('Open until the end of'), findsNothing);
      await tester.enterText(find.byType(TextField), '  Pending July ratings ');
      await submitSheet(tester);

      final call = h.repo.sets.single;
      expect(call.stage, ReviewStage.reportingManagerRating);
      expect(call.mode, RatingAccessMode.open);
      expect(call.openUntilDate, isNull);
      expect(call.reason, 'Pending July ratings');
      expect(inStageCard(rm, 'Reopened · no end date'), findsOneWidget);
      expect(find.text('$rm reopened with no end date.'), findsOneWidget);
    });

    testWidgets('Open until… starts on the current end when that is ahead',
        (tester) async {
      final h = await pumpRatingAccess(tester, repo: augustRepo());
      final end = istEndOfDay(2026, 10, 31).toLocal();
      final endDay = DateTime(end.year, end.month, end.day);

      await tapAndSettle(tester, inStageCard('Self-rating', 'Open until…'));
      expect(find.text('Open until the end of ${day(endDay)}'), findsOneWidget);
      await submitSheet(tester);

      final call = h.repo.sets.single;
      expect(call.openUntilDate, ratingAccessDateParam(endDay));
      expect(call.reason, isNull, reason: 'a blank reason is not sent');
    });

    testWidgets('Open until… a day picked from the calendar', (tester) async {
      final h = await pumpRatingAccess(tester, repo: augustRepo());

      // The manager stage closed on 13 Sep, so the sheet starts on today.
      await tapAndSettle(tester, inStageCard(rm, 'Open until…'));
      await tapAndSettle(tester, find.textContaining('Open until the end of'));
      await tapAndSettle(tester, find.text('20'));
      await tapAndSettle(tester, find.text('OK'));
      expect(find.text('Open until the end of 20 Oct 2026'), findsOneWidget);
      await submitSheet(tester);

      expect(h.repo.sets.single.openUntilDate, '2026-10-20');
      expect(
          inStageCard(rm, 'Reopened until ${day(istEndOfDay(2026, 10, 20))}'),
          findsOneWidget);
      expect(find.text('$rm reopened until 20 Oct 2026.'), findsOneWidget);
    });

    testWidgets('Use deadline confirms, clears, and shows the deadline again',
        (tester) async {
      final h = await pumpRatingAccess(tester, repo: augustRepo());

      await tapAndSettle(tester, inStageCard('HR rating', 'Use deadline'));
      expect(find.text('Put HR rating back on its deadline?'), findsOneWidget);
      expect(find.textContaining(day(istEndOfDay(2026, 9, 12))), findsOneWidget,
          reason: 'the confirmation names the deadline');
      await tapAndSettle(tester, inDialog('Use deadline'));

      final call = h.repo.clears.single;
      expect(call.organizationId, 'org-1');
      expect(call.period, august);
      expect(call.stage, ReviewStage.accountHrRating);
      expect(
          inStageCard('HR rating',
              'Closed on ${day(istEndOfDay(2026, 9, 12))} · deadline'),
          findsOneWidget);
      expect(inStageCard('HR rating', 'Use deadline'), findsNothing);
      expect(find.text('HR rating is back on its deadline.'), findsOneWidget);
    });

    testWidgets('a refusal says why, changes nothing, and re-enables',
        (tester) async {
      final repo = augustRepo()..failWriteAt = 0;
      await pumpRatingAccess(tester, repo: repo);

      await tapAndSettle(tester, inStageCard(rm, 'Close now'));
      await tapAndSettle(tester, inDialog('Close now'));

      expect(
          find.text(
              'Could not update rating access. That date has already passed.'),
          findsOneWidget);
      expect(
          inStageCard(
              rm, 'Closed on ${day(istEndOfDay(2026, 9, 13))} · deadline'),
          findsOneWidget);
      expect(buttonLabelled(tester, inStageCard(rm, 'Close now')).onPressed,
          isNotNull);
      expect(repo.monthFetches, hasLength(1), reason: 'nothing to refetch');
    });
  });

  group('bulk', () {
    testWidgets('Open all stages until… writes every stage the flow uses',
        (tester) async {
      final h = await pumpRatingAccess(tester, repo: augustRepo());

      await tapAndSettle(tester, find.text('Open all stages until…'));
      expect(find.text('August 2026 · 5 stages'), findsOneWidget);
      await tapAndSettle(tester, find.byType(SwitchListTile));
      await submitSheet(tester);

      expect([for (final s in h.repo.sets) s.stage], ratingStages);
      expect(h.repo.sets.every((s) => s.mode == RatingAccessMode.open), isTrue);
      expect(h.repo.sets.every((s) => s.openUntilDate == null), isTrue);
      expect(
          find.text('All stages reopened with no end date.'), findsOneWidget);
    });

    testWidgets('ADMIN_ONLY: open all leaves the unused self-rating alone',
        (tester) async {
      final h = await pumpRatingAccess(tester,
          repo: augustRepo(flow: ReviewFlow.adminOnly));

      await tapAndSettle(tester, find.text('Open all stages until…'));
      expect(find.text('August 2026 · 4 stages'), findsOneWidget);
      await submitSheet(tester);

      expect([for (final s in h.repo.sets) s.stage],
          ratingStages.where((s) => s != ReviewStage.selfRating));
      expect(h.repo.sets.map((s) => s.openUntilDate).toSet(), hasLength(1));
    });

    testWidgets('Use deadline for all clears exactly the overridden stages',
        (tester) async {
      final h = await pumpRatingAccess(tester, repo: augustRepo());

      await tapAndSettle(tester, find.text('Use deadline for all'));
      expect(find.text('Use the deadline for every stage?'), findsOneWidget);
      await tapAndSettle(tester, inDialog('Use deadline'));

      expect([
        for (final c in h.repo.clears) c.stage
      ], [
        ReviewStage.selfRating,
        ReviewStage.accountHrRating,
        ReviewStage.financeRating,
        ReviewStage.managementReview,
      ]);
      expect(find.text('Every stage is back on its deadline.'), findsOneWidget);
      expect(find.text('Use deadline for all'), findsNothing,
          reason: 'nothing left to reset');
    });
  });
}
