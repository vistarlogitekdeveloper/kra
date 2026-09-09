import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../enums/review_flow.dart';

/// The organisation this session is acting as, plus what we were told about it.
///
/// The review flow rides along because the server has no other way to give it
/// to us for an organisation that is not our own: `/auth/login` and `/auth/me`
/// both resolve the flow from the EMPLOYEE ROW's organisation — the home one —
/// and the access token carries no flow claim. Switching organisation re-issues
/// a token against the target and leaves the employee row alone, so a super
/// admin acting in another tenant would otherwise carry their own home
/// organisation's pipeline forever, and re-logging in would not help.
///
/// `POST /organizations/switch` does return the target organisation, flow
/// included. It was simply being dropped on the floor. Keeping it here is not a
/// cache — it is the only place that answer exists on the client.
class ActingOrg {
  final String id;

  /// The pipeline that organisation runs, or null when we were not told.
  ///
  /// Null is normal, not exceptional: a session rehydrated from a stored token
  /// at boot knows the organisation id from the JWT claim and nothing else.
  /// Callers must fall back to the signed-in user's own flow, which keeps the
  /// standard pipeline the answer whenever nobody has said otherwise.
  final ReviewFlow? reviewFlow;

  const ActingOrg({required this.id, this.reviewFlow});
}

/// The organisation this session is ACTING as, when it differs from the
/// signed-in user's home organisation.
///
/// Needed because the two really are different things, and the API only tells
/// you one of them:
///
///   * `/auth/me` returns the employee row's `organizationId` — their HOME
///     organisation, a column on their record. It never changes.
///   * the access token's `organizationId` claim is the organisation the
///     request is scoped to, and EVERY backend query filters by that claim.
///
/// A super admin who switches tenant gets a new token with a new claim; their
/// employee row is untouched. Measured against the deployed API:
///
///     token claim     -> be7b0ad6…        (vistar-logitek)
///     /auth/me        -> org_vistar_test  (unchanged)
///     GET /employees  -> vistar-logitek's employees
///
/// So the claim decides what the server returns, and trusting `/auth/me`
/// produced the precise bug this fixes: the employee list correctly showed the
/// new tenant's people while the header still named the old one.
///
/// Null means "no switch in effect" — use the user's home organisation.
class ActingOrgNotifier extends StateNotifier<ActingOrg?> {
  ActingOrgNotifier(Ref ref) : super(null) {
    // Clear on any change of session identity. A fresh login must not inherit
    // the previous session's acting organisation.
    //
    // Deliberately keyed on the user ID, not on the auth state object: an
    // organisation switch republishes the SAME user (adoptTokens), and
    // resetting on that would wipe the value the switch just set.
    ref.listen<AuthState>(authStateProvider, (previous, next) {
      final previousId =
          previous is AuthAuthenticated ? previous.user.id : null;
      final nextId = next is AuthAuthenticated ? next.user.id : null;
      if (previousId != nextId) state = null;
    });
  }

  /// Records the organisation this session is now acting as.
  ///
  /// Pass [reviewFlow] when the caller genuinely knows it — the switch response
  /// carries it. Omitting it means "unknown", which is honest for a session
  /// rehydrated from a token, and leaves [currentReviewFlowProvider] on the
  /// signed-in user's own flow rather than inventing one.
  ///
  /// An empty id is treated as no switch: `''` is a perfectly valid Prisma
  /// `where` value that would silently match nothing.
  void adopt(String? organizationId, {ReviewFlow? reviewFlow}) =>
      state = (organizationId == null || organizationId.isEmpty)
          ? null
          : ActingOrg(id: organizationId, reviewFlow: reviewFlow);
}

final actingOrgProvider =
    StateNotifierProvider<ActingOrgNotifier, ActingOrg?>((ref) {
  return ActingOrgNotifier(ref);
});

/// The organisation the signed-in user is currently scoped to.
///
/// This is the tenancy boundary for the ENTIRE app. Every list the backend
/// serves — employees, KRA templates, locations, review cycles, reviews — is
/// filtered by the `organizationId` claim in the caller's JWT, never by a
/// request parameter. So this value decides what is visible.
///
/// Prefers the ACTING organisation over the user's home one, because that is
/// what the server actually scopes by. See [ActingOrgNotifier].
///
/// ── WHY EVERY REPOSITORY PROVIDER WATCHES THIS ──────────────────────────────
///
/// Riverpod caches, and the app leans on that: `employeeListProvider` even
/// holds itself alive with `ref.keepAlive()`. Nothing in those caches records
/// WHICH organisation the data came from, so after a switch they would happily
/// serve the previous tenant's employees, templates and reviews under the new
/// tenant's name. That is the worst failure a multi-tenant client has — not a
/// crash, just quietly wrong data attributed to the wrong company.
///
/// Every `*RepositoryProvider` therefore watches this. Because the data
/// providers watch their repository, one dependency edge invalidates the whole
/// graph the moment the organisation changes, and each screen refetches on its
/// next build. That replaced a hand-maintained list of providers to invalidate,
/// which was only correct while somebody remembered to extend it.
///
/// Lives in `core/` rather than beside the organisation feature so auth, HR,
/// manager, employee and reviews providers can all depend on it without an
/// import cycle.
///
/// Null when nobody is signed in.
final currentOrgIdProvider = Provider<String?>((ref) {
  final auth = ref.watch(authStateProvider);
  if (auth is! AuthAuthenticated) return null;

  final acting = ref.watch(actingOrgProvider);
  if (acting != null && acting.id.isNotEmpty) return acting.id;

  final home = auth.user.organizationId;
  return home.isEmpty ? null : home;
});

/// The review pipeline the app should run RIGHT NOW.
///
/// The acting organisation's flow when a switch told us, otherwise the
/// signed-in user's own. That order matters and is the whole point: the server
/// resolves `reviewFlow` from the EMPLOYEE ROW's organisation on both
/// `/auth/login` and `/auth/me`, and signs no flow claim into the token. So a
/// super admin — the only role that can set an organisation's flow, because
/// every `/organizations` route is SUPER_ADMIN-only — would read their own home
/// organisation's pipeline while acting inside somebody else's, and signing out
/// and back in would not change it.
///
/// Falls back to [ReviewFlow.standard] only when nobody is signed in. Every
/// other unknown resolves to the user's own flow, which itself defaults to
/// standard — so the original pipeline stays the answer at every level unless
/// something positively says otherwise.
///
/// Lives beside [currentOrgIdProvider] because it answers the same question
/// about the same organisation, and for the same reason: so the reviews feature
/// can read it without core depending on the feature.
final currentReviewFlowProvider = Provider<ReviewFlow>((ref) {
  final auth = ref.watch(authStateProvider);
  if (auth is! AuthAuthenticated) return ReviewFlow.standard;

  final acting = ref.watch(actingOrgProvider);
  final actingFlow = acting?.reviewFlow;
  if (actingFlow != null) return actingFlow;

  return auth.user.reviewFlow;
});
