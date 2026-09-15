import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/providers/org_scope_provider.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';
import 'package:vistar_app/features/auth/presentation/providers/auth_providers.dart';

/// The tenancy boundary.
///
/// Every list the backend serves is filtered by the `organizationId` claim in
/// the caller's JWT. Riverpod caches those lists and records nothing about
/// which organisation they came from — `employeeListProvider` even holds itself
/// alive with `ref.keepAlive()`. So a switch that does not invalidate the graph
/// leaves the previous tenant's employees, templates and reviews on screen
/// under the new tenant's name: no crash, just confidently wrong data
/// attributed to the wrong company.
///
/// Every `*RepositoryProvider` therefore watches [currentOrgIdProvider], and
/// the data providers watch their repository — so one dependency edge
/// invalidates everything. These tests pin both halves of that.
void main() {
  User userIn(String orgId) => User(
        id: 'u1',
        email: 'a@b.test',
        fullName: 'A',
        role: UserRole.superAdmin,
        organizationId: orgId,
      );

  group('currentOrgIdProvider', () {
    test('is null when nobody is signed in', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(currentOrgIdProvider), isNull);
    });

    test('reports the signed-in organisation', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(authStateProvider.notifier).hydrate(userIn('org_a'));
      expect(c.read(currentOrgIdProvider), 'org_a');
    });

    test('treats a blank organisation as none, not as ""', () {
      // An empty string would be a perfectly valid Prisma `where` value and
      // would silently match nothing, so it must not be mistaken for a real id.
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(authStateProvider.notifier).hydrate(userIn(''));
      expect(c.read(currentOrgIdProvider), isNull);
    });

    test('changes when the user is republished after a switch', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final notifier = c.read(authStateProvider.notifier);

      notifier.hydrate(userIn('org_a'));
      expect(c.read(currentOrgIdProvider), 'org_a');

      notifier.hydrate(userIn('org_b'));
      expect(c.read(currentOrgIdProvider), 'org_b');
    });
  });

  group('the invalidation edge', () {
    test('a dependent provider is rebuilt when the organisation changes', () {
      // Stands in for a repository provider: watching currentOrgIdProvider is
      // exactly what makes the whole downstream graph refetch.
      var builds = 0;
      final repoLike = Provider<String>((ref) {
        builds++;
        return 'repo-for-${ref.watch(currentOrgIdProvider)}';
      });
      // Stands in for a data provider watching its repository.
      final dataLike =
          Provider<String>((ref) => 'data(${ref.watch(repoLike)})');

      final c = ProviderContainer();
      addTearDown(c.dispose);
      final notifier = c.read(authStateProvider.notifier);

      notifier.hydrate(userIn('org_a'));
      expect(c.read(dataLike), 'data(repo-for-org_a)');
      expect(builds, 1);

      notifier.hydrate(userIn('org_b'));
      expect(c.read(dataLike), 'data(repo-for-org_b)',
          reason: 'the data provider must follow the repository, not cache');
      expect(builds, 2, reason: 'the repository must be rebuilt, not reused');
    });

    test('no rebuild when the organisation is unchanged', () {
      // Republishing the same user (a token refresh, say) must not churn every
      // list in the app.
      var builds = 0;
      final repoLike = Provider<String>((ref) {
        builds++;
        ref.watch(currentOrgIdProvider);
        return 'r';
      });

      final c = ProviderContainer();
      addTearDown(c.dispose);
      final notifier = c.read(authStateProvider.notifier);

      notifier.hydrate(userIn('org_a'));
      c.read(repoLike);
      notifier.hydrate(userIn('org_a'));
      c.read(repoLike);

      expect(builds, 1);
    });
  });

  group('coverage', () {
    test('every repository provider is org-scoped, except auth', () {
      // Source-level, because a missed provider is invisible until someone
      // notices another company's data on screen. auth is the one exemption:
      // currentOrgIdProvider watches authStateProvider, which is built from
      // authRepositoryProvider, so scoping it there would close a cycle.
      const exempt = 'auth_providers.dart';
      final missing = <String>[];
      var checked = 0;

      for (final entity
          in Directory('lib/features').listSync(recursive: true)) {
        if (entity is! File) continue;
        final path = entity.path.replaceAll(r'\', '/');
        if (!path.endsWith('_providers.dart')) continue;
        if (path.endsWith(exempt)) continue;

        final src = entity.readAsStringSync();
        if (!RegExp(r'final\s+\w*RepositoryProvider\s*=').hasMatch(src)) {
          continue;
        }

        checked++;
        if (!src.contains('currentOrgIdProvider')) {
          missing.add(path);
        }
      }

      expect(checked, greaterThan(10),
          reason: 'found almost no repository providers — the scan is broken, '
              'not the app');
      expect(
        missing,
        isEmpty,
        reason: 'These declare a repository provider that does NOT watch '
            'currentOrgIdProvider, so their cached data survives an '
            'organization switch and will be shown under the wrong tenant:\n'
            '  ${missing.join('\n  ')}',
      );
    });
  });

  group('acting vs home organisation', () {
    // The root cause of "switch says it worked but the header shows the old
    // tenant": /auth/me returns the employee row's HOME organizationId, which a
    // switch never changes, while the token's claim is what every backend query
    // scopes by. Measured against the deployed API:
    //   token claim -> vistar-logitek | /auth/me -> org_vistar_test
    //   GET /employees -> vistar-logitek's employees
    test('the acting organisation wins over the home one', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(authStateProvider.notifier).hydrate(userIn('org_home'));
      expect(c.read(currentOrgIdProvider), 'org_home');

      c.read(actingOrgProvider.notifier).adopt('org_acting');
      expect(c.read(currentOrgIdProvider), 'org_acting',
          reason: 'the token claim decides what the server returns');
    });

    test('clearing the override falls back to the home organisation', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(authStateProvider.notifier).hydrate(userIn('org_home'));
      c.read(actingOrgProvider.notifier).adopt('org_acting');
      c.read(actingOrgProvider.notifier).adopt(null);
      expect(c.read(currentOrgIdProvider), 'org_home');
    });

    test('a switch does NOT clear itself when the user is republished', () {
      // adoptTokens republishes the same user. Resetting on that would wipe the
      // value the switch had just set, which is why the reset is keyed on the
      // user ID rather than on the auth state object.
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final auth = c.read(authStateProvider.notifier);
      auth.hydrate(userIn('org_home'));
      c.read(currentOrgIdProvider); // subscribe
      c.read(actingOrgProvider.notifier).adopt('org_acting');

      auth.hydrate(userIn('org_home')); // same user id, as after a switch
      expect(c.read(currentOrgIdProvider), 'org_acting');
    });

    test('a DIFFERENT user signing in clears the override', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final auth = c.read(authStateProvider.notifier);
      auth.hydrate(userIn('org_home'));
      c.read(currentOrgIdProvider); // subscribe so the listener is live
      c.read(actingOrgProvider.notifier).adopt('org_acting');

      auth.hydrate(const User(
        id: 'someone-else',
        email: 'b@b.test',
        fullName: 'B',
        role: UserRole.employee,
        organizationId: 'org_other',
      ));
      expect(c.read(currentOrgIdProvider), 'org_other',
          reason: 'a fresh session must not inherit the previous acting org');
    });

    test('an empty override is ignored', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(authStateProvider.notifier).hydrate(userIn('org_home'));
      c.read(actingOrgProvider.notifier).adopt('');
      expect(c.read(currentOrgIdProvider), 'org_home');
    });
  });
}
