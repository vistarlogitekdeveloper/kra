import '../models/hr_dashboard_models.dart';

/// Contract for the HR Dashboard data layer.
/// Each method maps 1:1 to one backend endpoint.
/// [cycleId] is always the currently active cycle's UUID.
abstract class HrDashboardRepository {
  /// GET /hr/dashboard
  Future<HrOverview> fetchOverview();

  /// GET /hr/dashboard/active-cycle
  Future<HrActiveCycle?> fetchActiveCycle();

  /// GET /hr/dashboard/kpis?cycleId=
  Future<HrKpis> fetchKpis(String cycleId);

  /// GET /hr/dashboard/pipeline?cycleId=
  Future<List<HrPipelineItem>> fetchPipeline(String cycleId);

  /// GET /hr/dashboard/action-items?cycleId=
  Future<List<HrActionItem>> fetchActionItems(String cycleId);

  /// GET /hr/dashboard/location-heatmap?cycleId=
  Future<HrLocationHeatmap> fetchLocationHeatmap(String cycleId);

  /// GET /hr/dashboard/recent-activity?limit=
  Future<List<HrActivityEntry>> fetchRecentActivity({int limit = 15});

  /// GET /hr/dashboard/deadlines?cycleId=
  Future<List<HrDeadline>> fetchDeadlines(String cycleId);
}
