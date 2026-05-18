import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../../../../core/api/envelope.dart';
import '../../../../core/api/json_parse.dart';
import '../models/enums.dart';
import '../models/team_member.dart';
import '../models/team_member_profile.dart';
import 'manager_team_repository.dart';

class ApiManagerTeamRepository implements ManagerTeamRepository {
  final Dio _dio;
  ApiManagerTeamRepository({required Dio dio}) : _dio = dio;

  @override
  Future<TeamMemberPage> listTeam({
    String? cycleId,
    int page = 1,
    int pageSize = 20,
    String? search,
    ManagerTeamFilter filter = ManagerTeamFilter.all,
  }) async {
    try {
      final response = await _dio.get(
        ApiConstants.managerTeam,
        queryParameters: {
          if (cycleId != null && cycleId.isNotEmpty) 'cycleId': cycleId,
          'page': page,
          'limit': pageSize,
          if (search != null && search.trim().isNotEmpty)
            'search': search.trim(),
          if (filter.toApiString() != null)
            'filterState': filter.toApiString(),
        },
      );
      final items = unwrapList(response)
          .whereType<Map<String, dynamic>>()
          .map(TeamMember.fromJson)
          .toList();
      final meta = unwrapMeta(response);
      final total = JsonParse.parseInt(meta?['total']) ?? items.length;
      final apiPage = JsonParse.parseInt(meta?['page']) ?? page;
      final apiPageSize =
          JsonParse.parseInt(meta?['limit'] ?? meta?['pageSize']) ?? pageSize;

      // `filterCounts` is an optional sibling block on the meta — used
      // by the chip-row to render count badges. Missing on legacy
      // payloads, so default to an empty map.
      final counts = <String, int>{};
      final rawCounts = meta?['filterCounts'];
      if (rawCounts is Map) {
        for (final entry in rawCounts.entries) {
          final v = JsonParse.parseInt(entry.value);
          if (v != null) counts[entry.key.toString()] = v;
        }
      }

      return TeamMemberPage(
        members: items,
        page: apiPage,
        pageSize: apiPageSize,
        total: total,
        filterCounts: counts,
      );
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  @override
  Future<TeamMemberProfile> getMemberProfile(String employeeId) async {
    try {
      final response = await _dio.get(
        '${ApiConstants.managerTeam}/$employeeId',
      );
      return TeamMemberProfile.fromJson(unwrapObject(response));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
