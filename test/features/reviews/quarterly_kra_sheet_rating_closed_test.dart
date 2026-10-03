import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vistar_app/core/api/api_error.dart';
import 'package:vistar_app/core/constants/app_strings.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';
import 'package:vistar_app/features/auth/data/repositories/auth_repository.dart';
import 'package:vistar_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/rating_window.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/data/repositories/mock_monthly_review_repository.dart';
import 'package:vistar_app/features/reviews/presentation/providers/kra_reviewer_map_provider.dart';
import 'package:vistar_app/features/reviews/presentation/providers/monthly_review_providers.dart';
import 'package:vistar_app/features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';

/// The real screen meeting a server that refuses a write because the stage's
/// window has shut — `403 AUTHZ_RATING_CLOSED` (docs/RATING_ACCESS.md §3.3).
///
/// That refusal means the sheet's copy of the windows is stale: a super admin
/// closed the stage, or its deadline passed, while it was open. So the sheet
/// must re-read itself (or the affordance that invited the write stays up and
/// invites it again) and show the server's sentence, which names the stage,
/// the month and the date — never "already moved on", which is the 409's.
void main() {
  DateTime ist(int y, int m, int d, [int h = 0]) =>
      DateTime.utc(y, m, d, h).subtract(const Duration(hours: 5, minutes: 30));
  final now = ist(2026, 10, 2, 12);

  const july = ReviewPeriod(2026, 7);
  const august = ReviewPeriod(2026, 8);
  const september = ReviewPeriod(2026, 9);
  const months = [july, august, september];
  final oct31 = DateTime(2026, 10, 31, 23, 59, 59, 999);

  const closedMessage = 'Self-rating for September 2026 has been closed by the '
      'administrator.';
  const closed = ApiError(
    type: ApiErrorType.validation,
    code: 'AUTHZ_RATING_CLOSED',
    message: closedMessage,
    statusCode: 403,
  );

  RatingWindow window(ReviewPeriod month, ReviewStage stage,
      {DateTime? reopenedUntil}) {
    final n = month.next;
    return RatingWindow(
      source: reopenedUntil == null
          ? RatingWindowSource.deadline
          : RatingWindowSource.opened,
      closed: false,
      opensAt: ist(n.year, n.month, 1),
      closesAt: reopenedUntil ??
          ist(n.year, n.month, stage.publishedDeadlineDay ?? 10, 23),
    );
  }

  MonthlyReview review(
    ReviewPeriod month, {
    ReviewStage currentStage = ReviewStage.selfRating,
    Set<ReviewStage> reopened = const {},
  }) =>
      MonthlyReview(
        id: 'r-${month.key}',
        employeeId: 'emp1',
        employeeName: 'Asha',
        managerId: 'mgr1',
        period: month,
        currentStage: currentStage,
        rows: [
          const MonthlyKraRow(
            id: 'k1',
            name: 'Safety of the Facility',
            weightagePercent: 100,
            maxScore: 10,
            reviewerGroup: KraReviewer.reportingManager,
            displayOrder: 1,
          ).withStageScore(ReviewStage.selfRating, const RowScore(value: 8)),
        ],
        ratingWindows: {
          for (final s in ReviewStage.values)
            if (s.isRatingStage)
              s: window(month, s,
                  reopenedUntil: reopened.contains(s) ? oct31 : null),
        },
      );

  const employee =
      ReviewScope(userId: 'emp1', userName: 'Asha', role: UserRole.employee);
  const manager =
      ReviewScope(userId: 'mgr1', userName: 'Manish', role: UserRole.manager);
  const management = ReviewScope(
      userId: 'boss1', userName: 'Founder', role: UserRole.management);

  /// Fixed frames rather than pumpAndSettle: the submit and rework bars spin
  /// an indeterminate progress indicator for as long as their dialog is up,
  /// so the tree never settles while one is open.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Pumps the screen and returns how many times the sheet has been fetched.
  Future<int Function()> pumpScreen(
    WidgetTester tester, {
    required ReviewScope scope,
    required List<MonthlyReview?> reviews,
    ApiError error = closed,
  }) async {
    // Tall enough that the lazily built list reaches the bars under the grid.
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var fetches = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => AuthNotifier(_SignedOut())),
        currentReviewScopeProvider.overrideWithValue(scope),
        monthlyReviewRepositoryProvider
            .overrideWithValue(_RefusingRepository(error)),
        quarterlySheetProvider.overrideWith((ref, args) async {
          fetches++;
          return (months: months, reviews: reviews);
        }),
        kraReviewerMapProvider.overrideWith((ref, employeeId) async => (
              byName: const <String, KraReviewer>{},
              byOrder: const <KraReviewer?>[],
            )),
      ],
      // A router because the app bar's leading asks GoRouter whether it can
      // pop.
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(
            path: '/',
            builder: (_, __) =>
                QuarterlyKraSheetScreen(employeeId: 'emp1', clock: now),
          ),
        ]),
      ),
    ));
    await settle(tester);
    expect(tester.takeException(), isNull);
    return () => fetches;
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  /// Lets the SnackBar's timer run out, so no timer outlives the test.
  Future<void> dismissSnackBar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
  }

  testWidgets('a refused rating re-reads the sheet and says why',
      (tester) async {
    final fetches = await pumpScreen(tester, scope: manager, reviews: [
      review(july, reopened: {ReviewStage.reportingManagerRating}),
      null,
      null,
    ]);
    expect(fetches(), 1);

    await tapVisible(tester, find.text('Rate'));
    await tapVisible(tester, find.text('Save 0%'));

    expect(find.text(closedMessage), findsOneWidget);
    expect(fetches(), 2, reason: 'the stale windows must be re-read');
    await dismissSnackBar(tester);
  });

  testWidgets('any other refusal of the same save does not re-read',
      (tester) async {
    const invalid = ApiError(
      type: ApiErrorType.validation,
      code: 'VAL_001',
      message: 'Score is out of range.',
      statusCode: 400,
    );
    final fetches =
        await pumpScreen(tester, scope: manager, error: invalid, reviews: [
      review(july, reopened: {ReviewStage.reportingManagerRating}),
      null,
      null,
    ]);

    await tapVisible(tester, find.text('Rate'));
    await tapVisible(tester, find.text('Save 0%'));

    expect(find.text('Score is out of range.'), findsOneWidget);
    expect(fetches(), 1);
    await dismissSnackBar(tester);
  });

  testWidgets('a refused self-submit is not reported as "moved on"',
      (tester) async {
    final fetches = await pumpScreen(tester,
        scope: employee, reviews: [null, null, review(september)]);

    await tapVisible(tester, find.text(AppStrings.selfSubmitAction));
    await tapVisible(tester, find.text(AppStrings.selfSubmitConfirmAction));

    expect(find.text(closedMessage), findsOneWidget);
    expect(find.text(AppStrings.selfSubmitAlreadyMoved), findsNothing);
    expect(fetches(), 2);
    await dismissSnackBar(tester);
  });

  testWidgets('a refused send-back shows the sentence, never the debug form',
      (tester) async {
    final fetches = await pumpScreen(tester, scope: manager, reviews: [
      null,
      null,
      review(september, currentStage: ReviewStage.reportingManagerRating),
    ]);

    await tapVisible(tester, find.text(AppStrings.sheetReworkAction));
    await tester.enterText(find.byType(TextField), 'Please revisit KRA 1');
    await tapVisible(tester, find.text(AppStrings.sheetReworkConfirm));

    expect(find.text(closedMessage), findsOneWidget);
    expect(find.textContaining('ApiError('), findsNothing);
    expect(fetches(), 2);
    await dismissSnackBar(tester);
  });

  group('management\'s lock bar', () {
    testWidgets('is not offered when no month\'s sign-off window is open',
        (tester) async {
      await pumpScreen(tester,
          scope: management, reviews: [review(july), review(august), null]);
      expect(find.text('Save & Lock'), findsNothing);
    });

    testWidgets('is offered once a month has been reopened for it',
        (tester) async {
      await pumpScreen(tester, scope: management, reviews: [
        review(july),
        review(august, reopened: {ReviewStage.managementReview}),
        null,
      ]);
      expect(find.text('Save & Lock'), findsOneWidget);
    });
  });
}

/// Signed out as far as the drawer is concerned; the review scope is supplied
/// directly. Nothing here is ever called.
class _SignedOut implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Refuses every write with [error], as the server does for a closed window.
class _RefusingRepository extends MockMonthlyReviewRepository {
  final ApiError error;
  _RefusingRepository(this.error) : super(now: DateTime(2026, 10, 2));

  @override
  Future<MonthlyReview> saveStageScores(
    String reviewId,
    ReviewStage stage, {
    required Map<String, RowScore> rowScores,
  }) async =>
      throw error;

  @override
  Future<MonthlyReview> submitStage(
    String reviewId,
    ReviewStage stage, {
    Map<String, RowScore>? rowScores,
    bool? approved,
    String? comment,
    required String actorId,
    required String actorName,
  }) async =>
      throw error;
}
