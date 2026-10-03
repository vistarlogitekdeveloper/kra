import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/api/api_error.dart';
import 'package:vistar_app/core/constants/app_strings.dart';
import 'package:vistar_app/core/enums/review_flow.dart';
import 'package:vistar_app/features/hr/presentation/widgets/rating_access/rating_access_stage_card.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/rating_access.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';

import 'rating_access_fakes.dart';
import 'rating_access_harness.dart';

/// What a super admin reads on the rating-access screen (docs/RATING_ACCESS.md
/// §4.3): every status line is the server's resolution, the cards follow the
/// organisation's flow, and the loading, error and empty states are designed.
void main() {
  group('content', () {
    testWidgets('one card per stage, each with the status the server resolved',
        (tester) async {
      await pumpRatingAccess(tester,
          repo:
              FakeRatingAccessRepository(months: {august.key: mixedAugust()}));

      expect(find.text('Vistar Logitek'), findsOneWidget);
      expect(find.text('Review flow: Standard'), findsOneWidget);
      expect(find.text('Rated during September 2026'), findsOneWidget);
      expect(find.byType(RatingAccessStageCard), findsNWidgets(5));

      expect(
          inStageCard('Self-rating',
              'Reopened until ${day(istEndOfDay(2026, 10, 31))}'),
          findsOneWidget);
      expect(
          inStageCard('Reporting-manager rating',
              'Closed on ${day(istEndOfDay(2026, 9, 13))} · deadline'),
          findsOneWidget);
      expect(inStageCard('HR rating', 'Closed by super admin'), findsOneWidget);
      expect(inStageCard('Accounts rating', 'Reopened · no end date'),
          findsOneWidget);
      expect(
          inStageCard('Management review',
              'Closed on ${day(istEndOfDay(2026, 9, 15))} · deadline'),
          findsOneWidget);
    });

    testWidgets('the override behind a status: reason, who, when, and no-ops',
        (tester) async {
      await pumpRatingAccess(tester,
          repo:
              FakeRatingAccessRepository(months: {august.key: mixedAugust()}));

      expect(
          inStageCard('Self-rating',
              'Reason: Pre-opened at rollout: pending July/August ratings'),
          findsOneWidget);
      expect(
          inStageCard('Self-rating',
              'by Super Admin · ${day(DateTime.utc(2026, 10, 1, 4, 30))}'),
          findsOneWidget);
      // An OPEN override ending before the deadline changes nothing; say so.
      expect(
          inStageCard(
              'Management review', AppStrings.ratingAccessOverrideInert),
          findsOneWidget);
      expect(inStageCard('Self-rating', AppStrings.ratingAccessOverrideInert),
          findsNothing);
    });

    testWidgets('actions offered match what each stage can change',
        (tester) async {
      await pumpRatingAccess(tester,
          repo:
              FakeRatingAccessRepository(months: {august.key: mixedAugust()}));

      // Use deadline only where an override exists.
      expect(inStageCard('Reporting-manager rating', 'Use deadline'),
          findsNothing);
      expect(inStageCard('Self-rating', 'Use deadline'), findsOneWidget);
      // Close now is pointless on a stage the admin already closed.
      expect(inStageCard('HR rating', 'Close now'), findsNothing);
      expect(
          inStageCard('Reporting-manager rating', 'Close now'), findsOneWidget);
      for (final label in [
        'Self-rating',
        'Reporting-manager rating',
        'HR rating',
        'Accounts rating',
        'Management review',
      ]) {
        expect(inStageCard(label, 'Open until…'), findsOneWidget,
            reason: label);
      }
      expect(find.text('Use deadline for all'), findsOneWidget);
    });

    testWidgets('a month on its deadline: open until it, nothing to reset',
        (tester) async {
      await pumpRatingAccess(
        tester,
        period: september,
        repo: FakeRatingAccessRepository(
            months: {september.key: deadlineMonth(september)}),
      );

      expect(
          inStageCard('Self-rating',
              'Open until ${day(istEndOfDay(2026, 10, 10))} · deadline'),
          findsOneWidget);
      expect(find.text('Use deadline'), findsNothing);
      expect(find.text('Use deadline for all'), findsNothing);
    });

    testWidgets('a month still running is not open yet, and gets its own chip',
        (tester) async {
      const october = ReviewPeriod(2026, 10);
      await pumpRatingAccess(
        tester,
        period: october,
        repo: FakeRatingAccessRepository(
            months: {october.key: deadlineMonth(october)}),
      );

      expect(
          find.text('Opens ${day(istMonthStart(2026, 11))}'), findsNWidgets(5));
      expect(find.widgetWithText(ChoiceChip, 'October 2026'), findsOneWidget);
    });

    testWidgets(
        'ADMIN_ONLY: no self-rating card, the manager seat is management',
        (tester) async {
      await pumpRatingAccess(
        tester,
        repo: FakeRatingAccessRepository(
          months: {august.key: mixedAugust(flow: ReviewFlow.adminOnly)},
          overrides: [
            overrideOf(august, ReviewStage.selfRating, RatingAccessMode.open),
          ],
        ),
      );

      expect(find.text('Review flow: Administrators only'), findsOneWidget);
      expect(find.byType(RatingAccessStageCard), findsNWidgets(4));
      expect(stageCard('Self-rating'), findsNothing);
      expect(stageCard('Reporting-manager rating'), findsNothing);
      expect(
          inStageCard('Management rating',
              'Closed on ${day(istEndOfDay(2026, 9, 13))} · deadline'),
          findsOneWidget);
      expect(
          inStageCard(
              'Management rating', AppStrings.ratingAccessSeatManagementRating),
          findsOneWidget);
      // The rollout seeds a self-rating override everywhere; the history says
      // why no card shows it.
      expect(find.text('Self-rating · August 2026'), findsOneWidget);
      expect(find.text(AppStrings.ratingAccessNotInFlow), findsOneWidget);
    });
  });

  group('history', () {
    testWidgets('newest first; tapping a row opens its month', (tester) async {
      final h = await pumpRatingAccess(
        tester,
        repo: FakeRatingAccessRepository(
          months: {
            august.key: mixedAugust(),
            july.key: deadlineMonth(july),
          },
          overrides: [
            overrideOf(july, ReviewStage.selfRating, RatingAccessMode.open,
                openUntil: istEndOfDay(2026, 10, 31),
                updatedAt: DateTime.utc(2026, 10, 1, 5)),
            overrideOf(
                august, ReviewStage.accountHrRating, RatingAccessMode.closed,
                updatedAt: DateTime.utc(2026, 9, 20)),
          ],
        ),
      );

      final july1 = tester.getTopLeft(find.text('Self-rating · July 2026'));
      final aug1 = tester.getTopLeft(find.text('HR rating · August 2026'));
      expect(july1.dy, lessThan(aug1.dy), reason: 'in the order served');
      expect(find.text('Open until ${day(istEndOfDay(2026, 10, 31))}'),
          findsOneWidget);

      await tester.tap(find.text('Self-rating · July 2026'));
      await tester.pumpAndSettle();

      expect(
          h.location, '/hr/organizations/org-1/rating-access?period=2026-07');
      expect(h.repo.monthFetches.last, 'org-1 2026-07');
      expect(find.text('Rated during August 2026'), findsOneWidget);
    });

    testWidgets('an organisation with no overrides says so', (tester) async {
      await pumpRatingAccess(tester,
          repo:
              FakeRatingAccessRepository(months: {august.key: mixedAugust()}));

      expect(
          find.text(AppStrings.ratingAccessHistoryEmptyTitle), findsOneWidget);
      expect(
          find.text(AppStrings.ratingAccessHistoryEmptyBody), findsOneWidget);
    });
  });

  group('navigation', () {
    FakeRatingAccessRepository twoMonths() =>
        FakeRatingAccessRepository(months: {
          august.key: mixedAugust(),
          september.key: deadlineMonth(september),
        });
    const septemberUrl = '/hr/organizations/org-1/rating-access?period=2026-09';

    testWidgets('reached by URL, a month chip moves the address bar with it',
        (tester) async {
      final h = await pumpRatingAccess(tester, repo: twoMonths());

      await tester.tap(find.widgetWithText(ChoiceChip, 'September 2026'));
      await tester.pumpAndSettle();

      expect(h.location, septemberUrl);
      // A plain replace here would have left '/hr/organizations?period=2026-08'
      // in the address bar, and a refresh would open the list.
      expect(h.addressBar, septemberUrl);
      expect(h.repo.monthFetches, ['org-1 2026-08', 'org-1 2026-09']);
      expect(find.text('Rated during October 2026'), findsOneWidget);
    });

    testWidgets('pushed, a month chip replaces in place and keeps the stack',
        (tester) async {
      final h = await pumpRatingAccess(tester, repo: twoMonths(), pushed: true);
      expect(h.topWasPushed, isTrue);

      await tester.tap(find.widgetWithText(ChoiceChip, 'September 2026'));
      await tester.pumpAndSettle();

      expect(h.topWasPushed, isTrue, reason: 'still the pushed page');
      expect(h.location, septemberUrl);
      expect(find.text('Rated during October 2026'), findsOneWidget);

      await tester.tap(find.byTooltip(AppStrings.commonBack));
      await tester.pumpAndSettle();
      expect(find.text('organizations list'), findsOneWidget,
          reason: 'no history entry per chip: one back returns');
    });

    testWidgets('no period opens the month being rated', (tester) async {
      final h = await pumpRatingAccess(
        tester,
        period: null,
        repo: FakeRatingAccessRepository(
            months: {september.key: deadlineMonth(september)}),
      );
      expect(h.repo.monthFetches, ['org-1 2026-09']);
    });

    testWidgets('back returns to the organisations list', (tester) async {
      await pumpRatingAccess(tester,
          repo:
              FakeRatingAccessRepository(months: {august.key: mixedAugust()}));

      await tester.tap(find.byTooltip(AppStrings.commonBack));
      await tester.pumpAndSettle();
      expect(find.text('organizations list'), findsOneWidget);
    });
  });

  group('states', () {
    testWidgets('a failed load explains itself and Retry recovers',
        (tester) async {
      final repo =
          FakeRatingAccessRepository(months: {august.key: mixedAugust()})
            ..monthFailures.add(const ApiError(
              type: ApiErrorType.server,
              code: 'SERVER_ERROR',
              message: 'Our servers are having trouble. Please try again in '
                  'a moment.',
              statusCode: 500,
            ));
      await pumpRatingAccess(tester, repo: repo);

      expect(find.text(AppStrings.ratingAccessLoadFailed), findsOneWidget);
      expect(
          find.text('Our servers are having trouble. Please try again in '
              'a moment.'),
          findsOneWidget);
      expect(find.byType(RatingAccessStageCard), findsNothing);

      await tester.tap(find.text(AppStrings.commonRetry));
      await tester.pumpAndSettle();

      expect(find.byType(RatingAccessStageCard), findsNWidgets(5));
      expect(repo.monthFetches, hasLength(2));
    });

    testWidgets('a backend without the endpoints says so, not "not found"',
        (tester) async {
      final repo = FakeRatingAccessRepository()
        ..historyFailure = const ApiError(
          type: ApiErrorType.notFound,
          code: 'RES_001',
          message: 'Route not found',
          statusCode: 404,
        );
      await pumpRatingAccess(tester, repo: repo);

      expect(find.text(AppStrings.ratingAccessApiMissing), findsNWidgets(2),
          reason: 'the month and the history both');
      expect(find.text('Route not found'), findsNothing);
    });

    testWidgets(
        'anyone but a super admin gets the lock, and nothing is fetched',
        (tester) async {
      final repo =
          FakeRatingAccessRepository(months: {august.key: mixedAugust()});
      await pumpRatingAccess(tester, repo: repo, superAdmin: false);

      expect(find.text(AppStrings.ratingAccessLocked), findsOneWidget);
      expect(find.byType(RatingAccessStageCard), findsNothing);
      expect(find.byTooltip(AppStrings.commonRefresh), findsNothing);
      expect(repo.monthFetches, isEmpty);
      expect(repo.historyFetches, 0);
    });

    testWidgets('Refresh refetches the month and the history', (tester) async {
      final repo =
          FakeRatingAccessRepository(months: {august.key: mixedAugust()});
      await pumpRatingAccess(tester, repo: repo);

      await tester.tap(find.byTooltip(AppStrings.commonRefresh));
      await tester.pumpAndSettle();

      expect(repo.monthFetches, hasLength(2));
      expect(repo.historyFetches, 2);
    });
  });
}
