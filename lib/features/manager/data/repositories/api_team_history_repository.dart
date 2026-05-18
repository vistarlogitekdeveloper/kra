import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../../../../core/api/envelope.dart';
import '../../../../core/api/json_parse.dart';
import '../models/previous_review.dart';
import 'team_history_repository.dart';

class ApiTeamHistoryRepository implements TeamHistoryRepository {
  final Dio _dio;
  ApiTeamHistoryRepository({required Dio dio}) : _dio = dio;

  @override
  Future<TeamHistoryPage> listHistory({
    String? employeeId,
    String? cycleId,
    int page = 1,
    int pageSize = 20,
  }) async {
    final path = employeeId != null && employeeId.isNotEmpty
        // Per-employee history endpoint.
        ? '${ApiConstants.managerTeam}/$employeeId/history'
        // Combined endpoint — same /manager/team root but no id.
        : '${ApiConstants.managerTeam}/history';
    try {
      final response = await _dio.get(
        path,
        queryParameters: {
          if (cycleId != null && cycleId.isNotEmpty) 'cycleId': cycleId,
          'page': page,
          'limit': pageSize,
        },
      );
      final items = unwrapList(response)
          .whereType<Map<String, dynamic>>()
          .map(PreviousReview.fromJson)
          .toList();
      final meta = unwrapMeta(response);
      final total = JsonParse.parseInt(meta?['total']) ?? items.length;
      final apiPage = JsonParse.parseInt(meta?['page']) ?? page;
      final apiPageSize =
          JsonParse.parseInt(meta?['limit'] ?? meta?['pageSize']) ?? pageSize;
      return TeamHistoryPage(
        reviews: items,
        page: apiPage,
        pageSize: apiPageSize,
        total: total,
      );
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
