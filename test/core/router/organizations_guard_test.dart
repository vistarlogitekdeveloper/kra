import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vistar_app/core/router/app_router.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';
import 'package:vistar_app/features/auth/presentation/providers/auth_providers.dart';
import 'package:vistar_app/features/hr/presentation/providers/organization_providers.dart';

/// `/hr/organizations` and everything beneath it — rating access included —
/// is SUPER_ADMIN alone (docs/RATING_ACCESS.md §4.3).
///
/// The HR-area guard admits HR_ADMIN and the legacy ADMIN too, so without a
/// second guard both could deep-link into tenant administration and collect
/// nothing but 403s. These run the REAL router's redirect pipeline — the same
/// one a pushed route or a typed URL goes through — so a guard that exists but
/// is not wired in fails here.
void main() {
  User userWith(UserRole role, {Set<UserRole>? roles}) => User(
        id: 'u-${role.name}',
        email: '${role.name}@vistar.test',
        fullName: role.name,
        role: role,
        roles: roles,
        organizationId: 'org_home',
      );

  group('AppRoutes helpers', () {
    test('the rating-access location, with and without a month', () {
      expect(AppRoutes.hrOrganizationRatingAccess('org-1'),
          '/hr/organizations/org-1/rating-access');
      expect(AppRoutes.hrOrganizationRatingAccess('org-1', period: '2026-08'),
          '/hr/organizations/org-1/rating-access?period=2026-08');
      expect(AppRoutes.hrOrganizationRatingAccess('a/b'),
          '/hr/organizations/a%2Fb/rating-access',
          reason: 'an id cannot escape its path segment');
    });

    test('the HR-home shortcut falls back to the list with no organisation',
        () {
      expect(AppRoutes.ratingAccessEntryFor('org-1'),
          AppRoutes.hrOrganizationRatingAccess('org-1'));
      expect(AppRoutes.ratingAccessEntryFor(null), AppRoutes.hrOrganizations);
      expect(AppRoutes.ratingAccessEntryFor(''), AppRoutes.hrOrganizations);
    });

    test('the organisations area is the prefix and below, not a sibling', () {
      expect(AppRoutes.isOrganizationsArea('/hr/organizations'), isTrue);
      expect(
          AppRoutes.isOrganizationsArea(
              '/hr/organizations/org-1/rating-access'),
          isTrue);
      expect(
          AppRoutes.isOrganizationsArea('/hr/organizations-archive'), isFalse);
      expect(AppRoutes.isOrganizationsArea('/hr/home'), isFalse);
    });

    test('SUPER_ADMIN exactly — not the legacy ADMIN, not HR_ADMIN', () {
      for (final role in UserRole.values) {
        expect(AppRoutes.canAccessOrganizations(userWith(role)),
            role == UserRole.superAdmin,
            reason: '$role');
      }
      expect(
        AppRoutes.canAccessOrganizations(userWith(UserRole.hrAdmin,
            roles: {UserRole.hrAdmin, UserRole.superAdmin})),
        isTrue,
        reason: 'a secondary SUPER_ADMIN seat counts',
      );
    });

    test('agrees with the provider every organisations screen reads', () {
      for (final role in UserRole.values) {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final user = userWith(role);
        c.read(authStateProvider.notifier).hydrate(user);
        expect(c.read(canManageOrganizationsProvider),
            AppRoutes.canAccessOrganizations(user),
            reason: '$role');
      }
    });

    test('no role is bounced into the area that rejects it', () {
      // The bounce target is dashboardForRole; were it ever under
      // /hr/organizations, the guard would redirect to itself forever.
      for (final role in UserRole.values) {
        expect(AppRoutes.isOrganizationsArea(AppRoutes.dashboardForRole(role)),
            isFalse,
            reason: '$role');
      }
    });
  });

  group('the router', () {
    const ratingAccess = '/hr/organizations/org-1/rating-access?period=2026-08';

    /// Where [user] actually lands for [location], through the real
    /// routerProvider's matching and redirects.
    Future<String> landing(
      WidgetTester tester,
      User user,
      String location,
    ) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(authStateProvider.notifier).hydrate(user);
      final router = c.read(routerProvider);
      addTearDown(router.dispose);

      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      final matches = await router.configuration.redirect(
        context,
        router.configuration.findMatch(location),
        redirectHistory: <RouteMatchList>[],
      );
      expect(matches.isError, isFalse, reason: 'no loop, no unmatched route');
      return matches.uri.toString();
    }

    testWidgets('admits SUPER_ADMIN to the list and to rating access',
        (tester) async {
      final sa = userWith(UserRole.superAdmin);
      expect(await landing(tester, sa, ratingAccess), ratingAccess);
      expect(await landing(tester, sa, AppRoutes.hrOrganizations),
          AppRoutes.hrOrganizations);
    });

    testWidgets('bounces HR_ADMIN and ADMIN to the HR home', (tester) async {
      for (final role in [UserRole.hrAdmin, UserRole.admin]) {
        final user = userWith(role);
        expect(await landing(tester, user, ratingAccess), AppRoutes.hrHome,
            reason: '$role on rating access');
        expect(await landing(tester, user, AppRoutes.hrOrganizations),
            AppRoutes.hrHome,
            reason: '$role on the organisations list');
      }
    });

    testWidgets('everyone else never reaches /hr at all', (tester) async {
      for (final role in [UserRole.employee, UserRole.manager, UserRole.hr]) {
        expect(await landing(tester, userWith(role), ratingAccess),
            AppRoutes.employeeHome,
            reason: '$role');
      }
    });

    testWidgets('the route is nested under the organisations list',
        (tester) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final router = c.read(routerProvider);
      addTearDown(router.dispose);

      final match = router.configuration.findMatch(ratingAccess);
      expect(match.isError, isFalse);
      expect(match.pathParameters['orgId'], 'org-1');
      expect(match.uri.queryParameters['period'], '2026-08');
      final routes = [
        for (final m in match.matches)
          if (m.route case final GoRoute route) route.path,
      ];
      expect(routes, [AppRoutes.hrOrganizations, ':orgId/rating-access']);
    });
  });
}
