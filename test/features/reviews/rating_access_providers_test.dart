import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/api/api_error.dart';
import 'package:vistar_app/core/api/dio_client.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';
import 'package:vistar_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review_summary.dart';
import 'package:vistar_app/features/reviews/data/models/rating_access.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/presentation/providers/monthly_review_providers.dart';
import 'package:vistar_app/features/reviews/presentation/providers/rating_access_providers.dart';

import '../hr/rating_access_fakes.dart';

/// The rating-access providers: tenancy-scoped like every repository, keyed
/// by value, and — the part a super admin feels — every write refreshes the
/// month, the history, and the review surfaces that embed rating windows.
void main() {
  const key = (organizationId: 'org-1', period: august);

  group('the repository provider', () {
    User superAdminIn(String orgId) => User(
          id: 'sa-1',
          email: 'sa@vistar.test',
          fullName: 'Super Admin',
          role: UserRole.superAdmin,
          organizationId: orgId,
        );

    test('is rebuilt when the organisation changes, and only then', () {
      final c = ProviderContainer(overrides: [
        dioProvider.overrideWithValue(Dio()),
      ]);
      addTearDown(c.dispose);
      final auth = c.read(authStateProvider.notifier);

      auth.hydrate(superAdminIn('org_a'));
      final first = c.read(ratingAccessRepositoryProvider);
      auth.hydrate(superAdminIn('org_a'));
      expect(identical(c.read(ratingAccessRepositoryProvider), first), isTrue,
          reason: 'a republish of the same organisation must not churn');

      auth.hydrate(superAdminIn('org_b'));
      expect(identical(c.read(ratingAccessRepositoryProvider), first), isFalse,
          reason: 'a switch must drop every cached month view');
    });
  });

  group('keys', () {
    // Built at run time, so every key is a distinct instance and equality has
    // to come from the values rather than from const canonicalisation.
    RatingAccessKey keyOf(String org, int year, int month) =>
        (organizationId: org, period: ReviewPeriod(year, month));

    test('a month view is keyed by organisation and month, by value', () {
      expect(
          identical(keyOf('org-1', 2026, 8), keyOf('org-1', 2026, 8)), isFalse);
      expect(ratingAccessMonthProvider(keyOf('org-1', 2026, 8)),
          ratingAccessMonthProvider(keyOf('org-1', 2026, 8)));
      expect(ratingAccessMonthProvider(keyOf('org-1', 2026, 8)),
          isNot(ratingAccessMonthProvider(keyOf('org-1', 2026, 7))));
      expect(ratingAccessMonthProvider(keyOf('org-1', 2026, 8)),
          isNot(ratingAccessMonthProvider(keyOf('org-2', 2026, 8))));
    });
  });

  group('RatingAccessActions', () {
    late FakeRatingAccessRepository fake;
    late ProviderContainer c;

    setUp(() {
      fake = FakeRatingAccessRepository(
        months: {august.key: mixedAugust()},
        overrides: [
          overrideOf(august, ReviewStage.selfRating, RatingAccessMode.open),
        ],
      );
      c = ProviderContainer(overrides: [
        ratingAccessRepositoryProvider.overrideWithValue(fake),
      ]);
      addTearDown(c.dispose);
      // Keep both alive, as the screen does.
      c.listen(ratingAccessMonthProvider(key), (_, __) {});
      c.listen(ratingAccessOverridesProvider('org-1'), (_, __) {});
    });

    Future<void> settle() async {
      await c.read(ratingAccessMonthProvider(key).future);
      await c.read(ratingAccessOverridesProvider('org-1').future);
    }

    test('a write refetches the month view and the history', () async {
      await settle();
      expect(fake.monthFetches, hasLength(1));
      expect(fake.historyFetches, 1);

      final answer = await c.read(ratingAccessActionsProvider).set(
            'org-1',
            august,
            ReviewStage.reportingManagerRating,
            mode: RatingAccessMode.closed,
          );
      expect(answer.stageFor(ReviewStage.reportingManagerRating)?.window.closed,
          isTrue,
          reason: 'set returns the server month view');

      await settle();
      expect(fake.monthFetches, hasLength(2));
      expect(fake.historyFetches, 2);
      final month = await c.read(ratingAccessMonthProvider(key).future);
      expect(
          month
              .stageFor(ReviewStage.reportingManagerRating)
              ?.adminOverride
              ?.mode,
          RatingAccessMode.closed);
    });

    test('a write drops the quarterly sheet and the monthly lists', () async {
      var sheetBuilds = 0;
      var listBuilds = 0;
      final sheet = ProviderContainer(overrides: [
        ratingAccessRepositoryProvider.overrideWithValue(fake),
        quarterlySheetProvider.overrideWith((ref, args) async {
          sheetBuilds++;
          return (
            months: const <ReviewPeriod>[],
            reviews: const <MonthlyReview?>[],
          );
        }),
        monthlyReviewListProvider.overrideWith((ref, period) async {
          listBuilds++;
          return const <MonthlyReviewSummary>[];
        }),
      ]);
      addTearDown(sheet.dispose);
      const args = (employeeId: 'emp1', anchor: august);
      sheet.listen(quarterlySheetProvider(args), (_, __) {});
      sheet.listen(monthlyReviewListProvider(august), (_, __) {});
      await sheet.read(quarterlySheetProvider(args).future);
      await sheet.read(monthlyReviewListProvider(august).future);
      expect((sheetBuilds, listBuilds), (1, 1));

      await sheet
          .read(ratingAccessActionsProvider)
          .clear('org-1', august, ReviewStage.selfRating);

      await sheet.read(quarterlySheetProvider(args).future);
      await sheet.read(monthlyReviewListProvider(august).future);
      expect((sheetBuilds, listBuilds), (2, 2),
          reason: 'a super admin acting in this organisation must see the '
              'sheet change at once');
    });

    test('openAll writes each stage in order with the same end and reason',
        () async {
      final last = await c.read(ratingAccessActionsProvider).openAll(
            'org-1',
            august,
            ratingStages,
            openUntilDate: '2026-10-31',
            reason: 'Pending July ratings',
          );

      expect([for (final s in fake.sets) s.stage], ratingStages);
      expect(fake.sets.every((s) => s.mode == RatingAccessMode.open), isTrue);
      expect(fake.sets.map((s) => s.openUntilDate).toSet(), {'2026-10-31'});
      expect(fake.sets.map((s) => s.reason).toSet(), {'Pending July ratings'});
      expect(last?.stageFor(ReviewStage.managementReview)?.window.closesAt,
          istEndOfDay(2026, 10, 31));
    });

    test('a refusal stops the bulk write but still refreshes', () async {
      await settle();
      fake.failWriteAt = 2;

      await expectLater(
        c
            .read(ratingAccessActionsProvider)
            .openAll('org-1', august, ratingStages),
        throwsA(isA<ApiError>()),
      );
      expect(fake.sets, hasLength(3), reason: 'stops at the third stage');

      await settle();
      expect(fake.monthFetches, hasLength(2),
          reason: 'the two stages before the refusal did change');
    });

    test('resetAll clears exactly the stages it is given', () async {
      final stages = [ReviewStage.selfRating, ReviewStage.accountHrRating];
      await c
          .read(ratingAccessActionsProvider)
          .resetAll('org-1', august, stages);

      expect([for (final s in fake.clears) s.stage], stages);
      expect(fake.sets, isEmpty);
    });

    test('an empty bulk write sends nothing', () async {
      expect(
        await c
            .read(ratingAccessActionsProvider)
            .openAll('org-1', august, const []),
        isNull,
      );
      expect(fake.sets, isEmpty);
    });
  });
}
