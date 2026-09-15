import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/review_flow.dart';
import 'package:vistar_app/core/providers/org_scope_provider.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';
import 'package:vistar_app/features/auth/presentation/providers/auth_providers.dart';

/// Which review pipeline the app runs while acting inside another organisation.
///
/// The server resolves `reviewFlow` from the EMPLOYEE ROW's organisation on
/// both `/auth/login` and `/auth/me`, and signs no flow claim into the access
/// token. Switching organisation re-issues a token against the target and
/// leaves the employee row untouched.
///
/// So the flow the server hands you is your HOME organisation's, always. Read
/// it straight off the auth user and a super admin acting inside an
/// administrators-only tenant runs the standard pipeline — and because every
/// `/organizations` route is SUPER_ADMIN-only, that account is the *only* one
/// that can set an organisation's flow and therefore the one most likely to be
/// testing it. Signing out and back in does not help; the home organisation is
/// a column on their record.
///
/// The switch response does carry the target organisation's flow. It was being
/// returned only to populate a toast. These tests pin that it now reaches the
/// scope, and — just as importantly — that nothing else changed.
void main() {
  User user({
    String id = 'u1',
    String org = 'org_home',
    ReviewFlow flow = ReviewFlow.standard,
    UserRole role = UserRole.superAdmin,
  }) =>
      User(
        id: id,
        email: 'a@b.test',
        fullName: 'A',
        role: role,
        organizationId: org,
        reviewFlow: flow,
      );

  group('currentReviewFlowProvider', () {
    test('standard when nobody is signed in', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(currentReviewFlowProvider), ReviewFlow.standard);
    });

    test('the signed-in user\'s own flow when no switch is in effect', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(authStateProvider.notifier)
          .hydrate(user(flow: ReviewFlow.adminOnly));
      expect(c.read(currentReviewFlowProvider), ReviewFlow.adminOnly,
          reason: 'an HR user whose OWN organisation runs the new flow must '
              'get it without any switch at all');
    });

    test('THE BUG: the acting organisation\'s flow beats the home one', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      // A super admin whose own organisation is on the standard pipeline...
      c.read(authStateProvider.notifier).hydrate(user());
      expect(c.read(currentReviewFlowProvider), ReviewFlow.standard);

      // ...switches into a tenant that runs administrators-only.
      c.read(actingOrgProvider.notifier).adopt(
            'org_acting',
            reviewFlow: ReviewFlow.adminOnly,
          );
      expect(c.read(currentReviewFlowProvider), ReviewFlow.adminOnly,
          reason: 'the sheet must run the pipeline of the organisation whose '
              'data it is showing');
    });

    test('and the reverse: acting STANDARD beats a home ADMIN_ONLY', () {
      // The override is not a one-way ratchet towards the new flow. Getting
      // this wrong would run administrators-only inside a tenant that is on
      // the standard pipeline — which would strip that tenant's employees of
      // their self-rating. Worse than the original bug.
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(authStateProvider.notifier)
          .hydrate(user(flow: ReviewFlow.adminOnly));
      c.read(actingOrgProvider.notifier).adopt(
            'org_acting',
            reviewFlow: ReviewFlow.standard,
          );
      expect(c.read(currentReviewFlowProvider), ReviewFlow.standard);
    });

    test('an UNKNOWN acting flow falls back to the user\'s own', () {
      // Boot rehydration knows the organisation from the token claim and
      // nothing else — the token carries no flow. Unknown must mean "defer",
      // not "standard", or a genuine ADMIN_ONLY user would be downgraded every
      // cold start.
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(authStateProvider.notifier)
          .hydrate(user(flow: ReviewFlow.adminOnly));
      c.read(actingOrgProvider.notifier).adopt('org_acting');
      expect(c.read(currentReviewFlowProvider), ReviewFlow.adminOnly,
          reason: 'no flow was supplied, so the user\'s own still applies');
    });

    test('clearing the switch returns to the user\'s own flow', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(authStateProvider.notifier).hydrate(user());
      c
          .read(actingOrgProvider.notifier)
          .adopt('org_acting', reviewFlow: ReviewFlow.adminOnly);
      expect(c.read(currentReviewFlowProvider), ReviewFlow.adminOnly);

      c.read(actingOrgProvider.notifier).adopt(null);
      expect(c.read(currentReviewFlowProvider), ReviewFlow.standard);
    });

    test('a DIFFERENT user signing in drops the acting flow', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final auth = c.read(authStateProvider.notifier);
      auth.hydrate(user());
      c.read(currentReviewFlowProvider); // subscribe so the listener is live
      c
          .read(actingOrgProvider.notifier)
          .adopt('org_acting', reviewFlow: ReviewFlow.adminOnly);

      auth.hydrate(user(id: 'someone-else', role: UserRole.employee));
      expect(c.read(currentReviewFlowProvider), ReviewFlow.standard,
          reason: 'a fresh session must not inherit the previous tenant\'s '
              'pipeline — that would hand an employee a flow with no '
              'self-rating in an organisation that has one');
    });

    test('a switch does NOT clear itself when the user is republished', () {
      // adoptTokens republishes the same user during a switch. The org id
      // survives that (keyed on user id); the flow must too, or it would be
      // wiped by the very act that set it.
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final auth = c.read(authStateProvider.notifier);
      auth.hydrate(user());
      c.read(currentReviewFlowProvider); // subscribe
      c
          .read(actingOrgProvider.notifier)
          .adopt('org_acting', reviewFlow: ReviewFlow.adminOnly);

      auth.hydrate(user()); // same id, as after a switch
      expect(c.read(currentReviewFlowProvider), ReviewFlow.adminOnly);
    });
  });

  group('the org id contract is unchanged', () {
    test('an empty acting id is still ignored, flow and all', () {
      // '' is a valid Prisma `where` value that matches nothing, so it must
      // never be mistaken for a real switch — and a flow attached to a
      // rejected id must not leak through either.
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(authStateProvider.notifier).hydrate(user());
      c
          .read(actingOrgProvider.notifier)
          .adopt('', reviewFlow: ReviewFlow.adminOnly);
      expect(c.read(currentOrgIdProvider), 'org_home');
      expect(c.read(currentReviewFlowProvider), ReviewFlow.standard,
          reason: 'no switch took effect, so neither did its flow');
    });

    test('adopting an id still redirects the tenancy boundary', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(authStateProvider.notifier).hydrate(user());
      c.read(actingOrgProvider.notifier).adopt('org_acting');
      expect(c.read(currentOrgIdProvider), 'org_acting');
    });
  });
}
