import 'package:dio/dio.dart';

import '../../../../core/api/envelope.dart';
import '../../../../core/api/json_parse.dart';
import '../models/hr_dashboard_models.dart';
import 'audit_log_repository.dart';

class ApiAuditLogRepository implements AuditLogRepository {
  final Dio _dio;
  ApiAuditLogRepository({required Dio dio}) : _dio = dio;

  /// Base path for audit logs. The endpoint lives under the HR sub-domain
  /// since only HR/ADMIN roles may access it. When the backend introduces
  /// a dedicated `/audit-logs` route, update this constant and leave all
  /// callers unchanged.
  static const _basePath = '/audit-logs';

  @override
  Future<AuditLogPage> fetchLogs({
    int page = 1,
    int pageSize = 20,
    String? actorId,
    String? action,
    String? entityType,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    try {
      final response = await _dio.get(
        _basePath,
        queryParameters: {
          'page': page,
          'pageSize': pageSize,
          if (actorId != null && actorId.isNotEmpty) 'actorId': actorId,
          if (action != null && action.isNotEmpty) 'action': action,
          if (entityType != null && entityType.isNotEmpty)
            'entityType': entityType,
          if (dateFrom != null) 'dateFrom': dateFrom.toIso8601String(),
          if (dateTo != null) 'dateTo': dateTo.toIso8601String(),
        },
      );
      final list = unwrapList(response)
          .whereType<Map<String, dynamic>>()
          .map(HrActivityEntry.fromJson)
          .toList();
      final meta = unwrapMeta(response);
      final total = JsonParse.parseInt(meta?['total']) ?? list.length;
      final apiPage = JsonParse.parseInt(meta?['page']) ?? page;
      final apiPageSize =
          JsonParse.parseInt(meta?['limit'] ?? meta?['pageSize']) ?? pageSize;
      return AuditLogPage(
        entries: list,
        page: apiPage,
        pageSize: apiPageSize,
        total: total,
      );
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
