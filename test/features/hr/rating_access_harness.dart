import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vistar_app/core/router/app_router.dart';
import 'package:vistar_app/features/hr/presentation/providers/organization_providers.dart';
import 'package:vistar_app/features/hr/presentation/screens/rating_access_screen.dart';
import 'package:vistar_app/features/hr/presentation/widgets/rating_access/rating_access_copy.dart';
import 'package:vistar_app/features/hr/presentation/widgets/rating_access/rating_access_stage_card.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/rating_access.dart';
import 'package:vistar_app/features/reviews/presentation/providers/monthly_review_providers.dart';
import 'package:vistar_app/features/reviews/presentation/providers/rating_access_providers.dart';

import 'rating_access_fakes.dart';

/// 2 Oct 2026, 12:00 IST: September is the month being rated, and July and
/// August are past every deadline.
final ratingAccessNow = DateTime.utc(2026, 10, 2, 6, 30);

/// The picker's six newest ratable months as of [ratingAccessNow].
const ratingAccessChips = [
  september,
  august,
  july,
  ReviewPeriod(2026, 6),
  ReviewPeriod(2026, 5),
  ReviewPeriod(2026, 4),
];

class RatingAccessHarness {
  final FakeRatingAccessRepository repo;
  final GoRouter router;
  RatingAccessHarness(this.repo, this.router);

  RouteMatchList get _configuration =>
      router.routerDelegate.currentConfiguration;

  /// The location of the page on top: a pushed page's own, else the
  /// declarative one — which is also what the browser address bar shows.
  String get location {
    final last = _configuration.matches.last;
    return last is ImperativeRouteMatch
        ? last.matches.uri.toString()
        : _configuration.uri.toString();
  }

  /// The address bar on web, which go_router 13 builds from the declarative
  /// matches only.
  String get addressBar => _configuration.uri.toString();

  /// Whether the page on top was pushed rather than reached by URL.
  bool get topWasPushed => _configuration.matches.last is ImperativeRouteMatch;
}

/// The screen behind a router shaped like the app's — the organisations list
/// with rating access nested under it — against [repo].
///
/// [pushed] lands on the list first and pushes the screen, as the organisation
/// card and the HR-home shortcut do; otherwise the screen is reached by URL.
Future<RatingAccessHarness> pumpRatingAccess(
  WidgetTester tester, {
  required FakeRatingAccessRepository repo,
  ReviewPeriod? period = august,
  bool superAdmin = true,
  bool pushed = false,
}) async {
  // Tall enough that every card and history row is built without scrolling.
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final target =
      AppRoutes.hrOrganizationRatingAccess('org-1', period: period?.key);
  final router = GoRouter(
    initialLocation: pushed ? AppRoutes.hrOrganizations : target,
    routes: [
      GoRoute(
        path: AppRoutes.hrOrganizations,
        builder: (_, __) => const Scaffold(body: Text('organizations list')),
        routes: [
          GoRoute(
            path: ':orgId/rating-access',
            builder: (_, state) => RatingAccessScreen(
              organizationId: state.pathParameters['orgId'] ?? '',
              initialPeriod:
                  parseRatingPeriod(state.uri.queryParameters['period']),
            ),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      ratingAccessRepositoryProvider.overrideWithValue(repo),
      canManageOrganizationsProvider.overrideWithValue(superAdmin),
      ratingAccessClockProvider.overrideWithValue(() => ratingAccessNow),
      availablePeriodsProvider.overrideWithValue(ratingAccessChips),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  if (pushed) {
    router.push<Object?>(target);
    await tester.pumpAndSettle();
  }
  return RatingAccessHarness(repo, router);
}

/// The stage card titled [label].
Finder stageCard(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(RatingAccessStageCard),
    );

/// [text] inside the stage card titled [label].
Finder inStageCard(String label, String text) =>
    find.descendant(of: stageCard(label), matching: find.text(text));

/// [text] inside the open dialog.
Finder inDialog(String text) =>
    find.descendant(of: find.byType(Dialog), matching: find.text(text));

/// The button whose label is [label].
ButtonStyleButton buttonLabelled(WidgetTester tester, Finder label) =>
    tester.widget<ButtonStyleButton>(find
        .ancestor(of: label, matching: find.bySubtype<ButtonStyleButton>())
        .first);

/// An instant as the screen writes it.
String day(DateTime instant) => ratingAccessDate(instant);
