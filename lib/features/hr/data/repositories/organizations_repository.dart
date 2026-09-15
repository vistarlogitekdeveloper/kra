import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../../../../core/api/envelope.dart';
import '../../../../core/enums/review_flow.dart';
import '../models/organization.dart';

/// Tenant administration — super admin only.
///
/// Backed by `/organizations`, which is NOT part of the original KRA API: the
/// `Organization` table has always existed and `organizationId` threads through
/// the whole backend, but no route ever exposed it, so organisations could only
/// be created by hand in SQL. The endpoints below are the contract added in
/// `docs/backend_patch_organizations.js`.
///
/// Until that patch is deployed every call here answers `404 RES_001 Route not
/// found`. The UI is built against the contract deliberately — the client work
/// does not need to wait on the deploy — so treat a 404 from these methods as
/// "the server does not have the feature yet", not as a bug in the caller.
abstract class OrganizationsRepository {
  /// Every tenant, with employee counts. [search] matches name or slug.
  Future<List<Organization>> list({String? search});

  Future<Organization> getById(String id);

  /// [slug] must be lowercase letters, digits and single hyphens — the server
  /// validates the same shape, and a duplicate answers 409.
  Future<Organization> create({
    required String name,
    required String slug,
    String? logoUrl,
    ReviewFlow? reviewFlow,
  });

  /// Sends only the supplied keys, so an omitted `logoUrl` is left alone while
  /// an explicit null clears it.
  Future<Organization> update(
    String id, {
    String? name,
    String? slug,
    String? logoUrl,
    bool clearLogo = false,
    ReviewFlow? reviewFlow,
  });

  /// Re-issues the caller's tokens against [organizationId].
  ///
  /// This is the ONLY way a super admin can act inside another tenant: every
  /// backend repository scopes by the `organizationId` claim in the JWT rather
  /// than by a request parameter, so switching organisation means getting a new
  /// token, not passing an argument.
  ///
  /// Returns the organisation now in scope. The caller is responsible for
  /// persisting the new tokens and invalidating cached, org-scoped state.
  Future<OrganizationSwitchResult> switchTo(String organizationId);
}

/// What `POST /organizations/switch` hands back: the new token pair plus the
/// organisation that is now in scope.
class OrganizationSwitchResult {
  final String accessToken;
  final String refreshToken;
  final Organization organization;

  const OrganizationSwitchResult({
    required this.accessToken,
    required this.refreshToken,
    required this.organization,
  });
}

class ApiOrganizationsRepository implements OrganizationsRepository {
  final Dio _dio;
  ApiOrganizationsRepository({required Dio dio}) : _dio = dio;

  @override
  Future<List<Organization>> list({String? search}) async {
    try {
      final response = await _dio.get(
        ApiConstants.organizations,
        queryParameters: {
          'limit': 200,
          if (search != null && search.trim().isNotEmpty)
            'search': search.trim(),
        },
      );
      return unwrapList(response)
          .whereType<Map<String, dynamic>>()
          .map(Organization.fromJson)
          .toList();
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<Organization> getById(String id) async {
    try {
      final response = await _dio.get('${ApiConstants.organizations}/$id');
      return Organization.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<Organization> create({
    required String name,
    required String slug,
    String? logoUrl,
    ReviewFlow? reviewFlow,
  }) async {
    try {
      final response = await _dio.post(
        ApiConstants.organizations,
        data: {
          'name': name.trim(),
          'slug': slug.trim(),
          if (logoUrl != null && logoUrl.trim().isNotEmpty)
            'logoUrl': logoUrl.trim(),
          // Omitted when null so a server without the column cannot 400 an
          // ordinary create; it then defaults to the standard pipeline.
          if (reviewFlow != null) 'reviewFlow': reviewFlow.toApiString(),
        },
      );
      return Organization.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<Organization> update(
    String id, {
    String? name,
    String? slug,
    String? logoUrl,
    bool clearLogo = false,
    ReviewFlow? reviewFlow,
  }) async {
    try {
      // Only the keys the caller actually set. The server rejects an empty
      // PATCH, which is the correct answer to a save with nothing changed.
      final body = <String, dynamic>{
        if (name != null) 'name': name.trim(),
        if (slug != null) 'slug': slug.trim(),
        if (clearLogo)
          'logoUrl': null
        else if (logoUrl != null && logoUrl.trim().isNotEmpty)
          'logoUrl': logoUrl.trim(),
        if (reviewFlow != null) 'reviewFlow': reviewFlow.toApiString(),
      };
      final response =
          await _dio.patch('${ApiConstants.organizations}/$id', data: body);
      return Organization.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<OrganizationSwitchResult> switchTo(String organizationId) async {
    try {
      final response = await _dio.post(
        ApiConstants.organizationsSwitch,
        data: {'organizationId': organizationId},
      );
      final data = unwrapObject(response);
      // The server nests the pair under `tokenPair`, matching /auth/login;
      // tolerate a flat shape too so a backend tweak can't break the switch.
      final pair = (data['tokenPair'] as Map<String, dynamic>?) ?? data;
      final org = data['organization'];
      return OrganizationSwitchResult(
        accessToken: (pair['accessToken'] as String?) ?? '',
        refreshToken: (pair['refreshToken'] as String?) ?? '',
        organization: org is Map<String, dynamic>
            ? Organization.fromJson(org)
            : Organization(id: organizationId, name: '', slug: ''),
      );
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
