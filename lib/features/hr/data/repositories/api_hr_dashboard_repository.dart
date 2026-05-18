import 'package:dio/dio.dart';

import '../../../../core/api/api_constants.dart';
import '../models/hr_dashboard_models.dart';
import '../../../../core/api/envelope.dart';
import 'hr_dashboard_repository.dart';

/// REST-backed implementation of [HrDashboardRepository].
/// Every method hits one endpoint and converts the unwrapped data payload.
class ApiHrDashboardRepository implements HrDashboardRepository {
  final Dio _dio;
  ApiHrDashboardRepository({required Dio dio}) : _dio = dio;

  // ── 1. GET /hr/dashboard ──────────────────────────────────────────
  @override
  Future<HrOverview> fetchOverview() async {
    try {
      final res = await _dio.get(ApiConstants.hrDashboard);
      return HrOverview.fromJson(unwrapObject(res));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  // ── 2. GET /hr/dashboard/active-cycle ────────────────────────────
  @override
  Future<HrActiveCycle?> fetchActiveCycle() async {
    try {
      final res = await _dio.get('${ApiConstants.hrDashboard}/active-cycle');
      final body = res.data;
      if (body is Map<String, dynamic> && body['success'] == true) {
        final data = body['data'];
        if (data == null) return null; // No active cycle
        if (data is Map<String, dynamic>) {
          return HrActiveCycle.fromJson(data);
        }
      }
      return null;
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  // ── 3. GET /hr/dashboard/kpis?cycleId= ───────────────────────────
  @override
  Future<HrKpis> fetchKpis(String cycleId) async {
    try {
      final res = await _dio.get(
        '${ApiConstants.hrDashboard}/kpis',
        queryParameters: {'cycleId': cycleId},
      );
      return HrKpis.fromJson(unwrapObject(res));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  // ── 4. GET /hr/dashboard/pipeline?cycleId= ───────────────────────
  @override
  Future<List<HrPipelineItem>> fetchPipeline(String cycleId) async {
    try {
      final res = await _dio.get(
        '${ApiConstants.hrDashboard}/pipeline',
        queryParameters: {'cycleId': cycleId},
      );
      final list = unwrapList(res);
      return list
          .whereType<Map<String, dynamic>>()
          .map(HrPipelineItem.fromJson)
          .toList();
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  // ── 5. GET /hr/dashboard/action-items?cycleId= ───────────────────
  @override
  Future<List<HrActionItem>> fetchActionItems(String cycleId) async {
    try {
      final res = await _dio.get(
        '${ApiConstants.hrDashboard}/action-items',
        queryParameters: {'cycleId': cycleId},
      );
      final list = unwrapList(res);
      return list
          .whereType<Map<String, dynamic>>()
          .map(HrActionItem.fromJson)
          .toList();
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  // ── 6. GET /hr/dashboard/location-heatmap?cycleId= ───────────────
  @override
  Future<HrLocationHeatmap> fetchLocationHeatmap(String cycleId) async {
    try {
      final res = await _dio.get(
        '${ApiConstants.hrDashboard}/location-heatmap',
        queryParameters: {'cycleId': cycleId},
      );
      return HrLocationHeatmap.fromJson(unwrapObject(res));
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  // ── 7. GET /hr/dashboard/recent-activity?limit= ──────────────────
  @override
  Future<List<HrActivityEntry>> fetchRecentActivity(
      {int limit = 15}) async {
    try {
      final res = await _dio.get(
        '${ApiConstants.hrDashboard}/recent-activity',
        queryParameters: {'limit': limit},
      );
      final list = unwrapList(res);
      return list
          .whereType<Map<String, dynamic>>()
          .map(HrActivityEntry.fromJson)
          .toList();
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }

  // ── 8. GET /hr/dashboard/deadlines?cycleId= ──────────────────────
  @override
  Future<List<HrDeadline>> fetchDeadlines(String cycleId) async {
    try {
      final res = await _dio.get(
        '${ApiConstants.hrDashboard}/deadlines',
        queryParameters: {'cycleId': cycleId},
      );
      final list = unwrapList(res);
      return list
          .whereType<Map<String, dynamic>>()
          .map(HrDeadline.fromJson)
          .toList();
    } catch (e, st) {
      rethrowAsApiError(e, st);
    }
  }
}
