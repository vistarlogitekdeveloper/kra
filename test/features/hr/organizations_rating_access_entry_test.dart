import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vistar_app/core/constants/app_strings.dart';
import 'package:vistar_app/core/enums/review_flow.dart';
import 'package:vistar_app/core/router/app_router.dart';
import 'package:vistar_app/features/hr/data/models/organization.dart';
import 'package:vistar_app/features/hr/data/repositories/organizations_repository.dart';
import 'package:vistar_app/features/hr/presentation/providers/organization_providers.dart';
import 'package:vistar_app/features/hr/presentation/screens/organizations_screen.dart';

/// Rating access is entered from each organisation card, for THAT
/// organisation, without switching into it (docs/RATING_ACCESS.md §4.3).
void main() {
  Future<GoRouter> pumpOrganizations(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: AppRoutes.hrOrganizations,
      routes: [
        GoRoute(
          path: AppRoutes.hrOrganizations,
          builder: (_, __) => const OrganizationsScreen(),
          routes: [
            GoRoute(
              path: ':orgId/rating-access',
              builder: (_, state) => Scaffold(
                body:
                    Text('rating access for ${state.pathParameters['orgId']}'),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        organizationsRepositoryProvider.overrideWithValue(_TwoOrganizations()),
        canManageOrganizationsProvider.overrideWithValue(true),
        currentOrganizationIdProvider.overrideWithValue('org-1'),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('every card offers it, and it opens that organisation',
      (tester) async {
    await pumpOrganizations(tester, const Size(1024, 1400));

    expect(find.text(AppStrings.ratingAccessTitle), findsNWidgets(2));

    // The second card is NOT the acting organisation: no switch happens.
    await tester.tap(find.text(AppStrings.ratingAccessTitle).last);
    await tester.pumpAndSettle();

    expect(find.text('rating access for org-2'), findsOneWidget);
  });

  testWidgets('the card actions fit a 360 px phone', (tester) async {
    await pumpOrganizations(tester, const Size(360, 1400));

    // An overflowing Row reports through FlutterError, which fails the test
    // on its own; this states the intent.
    expect(tester.takeException(), isNull);
    expect(find.text(AppStrings.orgSwitchAction), findsOneWidget);
    expect(find.text(AppStrings.orgViewPeople), findsOneWidget);
  });
}

class _TwoOrganizations implements OrganizationsRepository {
  @override
  Future<List<Organization>> list({String? search}) async => const [
        Organization(
            id: 'org-1',
            name: 'Vistar Logitek',
            slug: 'vistar-logitek',
            employeeCount: 12),
        Organization(
            id: 'org-2',
            name: 'Vistar Logitek North',
            slug: 'vistar-logitek-north',
            employeeCount: 3),
      ];

  @override
  Future<Organization> getById(String id) => throw UnimplementedError();

  @override
  Future<Organization> create({
    required String name,
    required String slug,
    String? logoUrl,
    ReviewFlow? reviewFlow,
  }) =>
      throw UnimplementedError();

  @override
  Future<Organization> update(
    String id, {
    String? name,
    String? slug,
    String? logoUrl,
    bool clearLogo = false,
    ReviewFlow? reviewFlow,
  }) =>
      throw UnimplementedError();

  @override
  Future<OrganizationSwitchResult> switchTo(String organizationId) =>
      throw UnimplementedError();
}
