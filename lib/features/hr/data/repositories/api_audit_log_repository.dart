import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../../../../core/api/envelope.dart';
import '../models/hr_dashboard_models.dart';
import 'audit_log_repository.dart';

/// Currently aliased to `GET /hr/dashboard/recent-activity?limit=N` —
/// the backend does not yet expose a dedicated `/audit-logs` route
/// (returns 404 RES_001). The recent-activity endpoint returns the
/// same `HrActivityEntry` shape, just without server-side pagination
/// or filters.
///
/// Until the dedicated route ships:
///   * `page` is ignored; we always fetch a single batch sized by
///     [_maxEntries] and report `hasMore = false`.
///   * Actor / action / entityType / date-range filters are dropped
///     at this boundary. Re-introduce when the real endpoint exists.
class ApiAuditLogRepository implements AuditLogRepository {
  final Dio _dio;
  ApiAuditLogRepository({required Dio dio}) : _dio = dio;

  static const String _basePath =
      '${ApiConstants.hrDashboard}/recent-activity';

  /// Upper bound the temporary endpoint will return. Generous so users
  /// see a meaningful trail without us pretending to paginate.
  static const int _maxEntries = 200;

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
    // Only the first page resolves to data while the route is aliased;
    // every subsequent page returns empty so the infinite-scroll loader
    // terminates cleanly.
    if (page > 1) {
      return const AuditLogPage(
        entries: [],
        page: 1,
        pageSize: _maxEntries,
        total: 0,
      );
    }
    try {
      final response = await _dio.get(
        _basePath,
        queryParameters: {'limit': _maxEntries},
      );
      final list = unwrapList(response)
          .whereType<Map<String, dynamic>>()
          .map(HrActivityEntry.fromJson)
          .toList();
      return AuditLogPage(
        entries: list,
        page: 1,
        pageSize: _maxEntries,
        total: list.length,
      );
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
