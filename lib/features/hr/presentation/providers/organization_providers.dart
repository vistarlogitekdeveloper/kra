import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/org_scope_provider.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/api/jwt_claims.dart';
import '../../../../core/api/dio_client.dart';
import '../../../auth/data/models/user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../../core/enums/review_flow.dart';
import '../../data/models/organization.dart';
import '../../data/repositories/organizations_repository.dart';

final organizationsRepositoryProvider =
    Provider<OrganizationsRepository>((ref) {
  // Org-scoped: recreated whenever the caller switches organisation, which
  // invalidates every provider that watches this repository. Without it,
  // cached lists from the previous tenant would be served under the new
  // tenant's name. See core/providers/org_scope_provider.dart.
  ref.watch(currentOrgIdProvider);
  return ApiOrganizationsRepository(dio: ref.read(dioProvider));
});

/// Whether the signed-in user may administer tenants at all.
///
/// Deliberately NOT [User.isSuperAdmin], which also covers the legacy
/// `UserRole.admin`. Tenant administration is the one capability reserved for
/// the org-wide tier alone: `ADMIN` is not even a storable role in the
/// backend's employees RoleEnum, and every `/organizations` route is gated on
/// `SUPER_ADMIN` exactly. Offering the screen to anyone else would only render
/// a 403.
final canManageOrganizationsProvider = Provider<bool>((ref) {
  final auth = ref.watch(authStateProvider);
  if (auth is! AuthAuthenticated) return false;
  return auth.user.hasRole(UserRole.superAdmin);
});

/// The organisation the caller is currently scoped to.
///
/// Every list in the app is filtered by this on the server, so it is what
/// decides which employees, templates and reviews are visible. Shown in the UI
/// so a super admin who has switched tenants can tell which one they are in —
/// without it, two tenants look identical apart from their contents.
/// Alias of [currentOrgIdProvider], which lives in core/ so every feature can
/// depend on it without an import cycle. Kept here so existing callers in this
/// feature read naturally; there is only ONE definition of "current org".
final currentOrganizationIdProvider =
    Provider<String?>((ref) => ref.watch(currentOrgIdProvider));

/// Search text for the organisations list. Kept in a provider rather than
/// screen state so the list refetches without the screen owning the query.
final organizationSearchProvider = StateProvider<String>((ref) => '');

/// Every tenant, with employee counts.
///
/// autoDispose so re-entering the screen re-reads: headcounts change whenever
/// anyone adds an employee, and a stale count is worse than a brief spinner.
final organizationsProvider =
    FutureProvider.autoDispose<List<Organization>>((ref) async {
  final search = ref.watch(organizationSearchProvider);
  return ref.watch(organizationsRepositoryProvider).list(search: search);
});

final organizationDetailProvider =
    FutureProvider.autoDispose.family<Organization, String>((ref, id) async {
  return ref.watch(organizationsRepositoryProvider).getById(id);
});

/// Create / update / switch. Every mutation invalidates the list so counts and
/// names stay honest.
class OrganizationActions {
  final Ref _ref;
  OrganizationActions(this._ref);

  OrganizationsRepository get _repo =>
      _ref.read(organizationsRepositoryProvider);

  Future<Organization> create({
    required String name,
    required String slug,
    String? logoUrl,
    ReviewFlow? reviewFlow,
  }) async {
    final org = await _repo.create(
        name: name, slug: slug, logoUrl: logoUrl, reviewFlow: reviewFlow);
    _ref.invalidate(organizationsProvider);
    return org;
  }

  Future<Organization> update(
    String id, {
    String? name,
    String? slug,
    String? logoUrl,
    bool clearLogo = false,
    ReviewFlow? reviewFlow,
  }) async {
    final org = await _repo.update(
      id,
      name: name,
      slug: slug,
      logoUrl: logoUrl,
      clearLogo: clearLogo,
      reviewFlow: reviewFlow,
    );
    _ref.invalidate(organizationsProvider);
    _ref.invalidate(organizationDetailProvider(id));
    return org;
  }

  /// Switches the caller into [organizationId] and re-authenticates with the
  /// tokens the server returns.
  ///
  /// The token swap is the entire point: the backend reads the organisation
  /// from the JWT, so nothing else in the app changes tenant until the stored
  /// tokens do. Delegated to the auth layer, which owns secure storage and the
  /// Dio interceptors — writing tokens from here would leave the interceptor
  /// holding the previous pair.
  Future<Organization> switchTo(String organizationId) async {
    final result = await _repo.switchTo(organizationId);
    if (result.accessToken.isEmpty || result.refreshToken.isEmpty) {
      throw const ApiError(
        type: ApiErrorType.unknown,
        code: 'SWITCH_NO_TOKENS',
        message: 'The server did not return a usable token pair for that '
            'organization.',
      );
    }

    // VERIFY against the TOKEN, not against /auth/me.
    //
    // /auth/me returns the employee row's own organizationId — their HOME
    // organisation — which a switch never changes. The token's claim is what
    // every backend query actually scopes by. Comparing against /auth/me was
    // the bug: the switch had genuinely worked (the employee list showed the
    // new tenant's people) yet the check declared it had not.
    final claimed = JwtClaims.organizationId(result.accessToken);
    if (claimed != organizationId) {
      throw ApiError(
        type: ApiErrorType.unknown,
        code: 'SWITCH_NOT_APPLIED',
        message: 'The organization did not change. The new token is scoped to '
            '"${claimed ?? 'no organization'}".',
      );
    }

    await _ref
        .read(authStateProvider.notifier)
        .adoptTokens(result.accessToken, result.refreshToken);

    // Record the acting organisation AFTER adoptTokens: that republishes the
    // user, and doing it in the other order would be overwritten.
    //
    // The FLOW is carried along deliberately. It is right here in the switch
    // response and used to be thrown away, which left the reviews layer reading
    // `auth.user.reviewFlow` — the acting user's HOME organisation. A super
    // admin switched into an administrators-only tenant therefore ran the
    // standard pipeline, and since only a super admin can set an organisation's
    // flow at all, that was the one account most likely to be testing it.
    _ref.read(actingOrgProvider.notifier).adopt(
          organizationId,
          reviewFlow: result.organization.reviewFlow,
        );

    return result.organization;
  }
}

final organizationActionsProvider =
    Provider<OrganizationActions>((ref) => OrganizationActions(ref));
