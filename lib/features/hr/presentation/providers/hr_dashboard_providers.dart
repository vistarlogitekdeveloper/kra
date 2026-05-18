import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/dio_client.dart';
import '../../data/models/hr_dashboard_models.dart';
import '../../data/repositories/api_hr_dashboard_repository.dart';
import '../../data/repositories/hr_dashboard_repository.dart';

// ─────────────────────────────────────────────────────────────────────
// Repository swap point
// ─────────────────────────────────────────────────────────────────────

final hrDashboardRepositoryProvider = Provider<HrDashboardRepository>((ref) {
  return ApiHrDashboardRepository(dio: ref.read(dioProvider));
});

// ─────────────────────────────────────────────────────────────────────
// 1. Overview cards — GET /hr/dashboard
// ─────────────────────────────────────────────────────────────────────

final hrOverviewProvider = FutureProvider.autoDispose<HrOverview>((ref) {
  return ref.watch(hrDashboardRepositoryProvider).fetchOverview();
});

// ─────────────────────────────────────────────────────────────────────
// 2. Active cycle — GET /hr/dashboard/active-cycle
//    This is the "root" provider: other cycle-scoped providers depend on
//    the id it exposes.
// ─────────────────────────────────────────────────────────────────────

final hrActiveCycleProvider =
    FutureProvider.autoDispose<HrActiveCycle?>((ref) {
  return ref.watch(hrDashboardRepositoryProvider).fetchActiveCycle();
});

// Derived: just the ID — used by the family providers below.
final hrActiveCycleIdProvider = Provider.autoDispose<AsyncValue<String?>>((ref) {
  return ref.watch(hrActiveCycleProvider).whenData((c) => c?.id);
});

// ─────────────────────────────────────────────────────────────────────
// 3-8. Cycle-scoped providers (family keyed on cycleId)
//      The HR home screen calls them with the id from hrActiveCycleProvider.
// ─────────────────────────────────────────────────────────────────────

/// 3. Detailed KPIs
final hrKpisProvider =
    FutureProvider.autoDispose.family<HrKpis, String>((ref, cycleId) {
  return ref.watch(hrDashboardRepositoryProvider).fetchKpis(cycleId);
});

/// 4. Review pipeline funnel
final hrPipelineProvider =
    FutureProvider.autoDispose.family<List<HrPipelineItem>, String>(
        (ref, cycleId) {
  return ref.watch(hrDashboardRepositoryProvider).fetchPipeline(cycleId);
});

/// 5. Action items that need HR attention
final hrActionItemsProvider =
    FutureProvider.autoDispose.family<List<HrActionItem>, String>(
        (ref, cycleId) {
  return ref.watch(hrDashboardRepositoryProvider).fetchActionItems(cycleId);
});

/// 6. Location heatmap (lazy — below the fold)
final hrLocationHeatmapProvider =
    FutureProvider.autoDispose.family<HrLocationHeatmap, String>(
        (ref, cycleId) {
  return ref
      .watch(hrDashboardRepositoryProvider)
      .fetchLocationHeatmap(cycleId);
});

/// 7. Recent activity — not cycle-scoped
final hrRecentActivityProvider =
    FutureProvider.autoDispose<List<HrActivityEntry>>((ref) {
  return ref
      .watch(hrDashboardRepositoryProvider)
      .fetchRecentActivity(limit: 15);
});

/// 8. Deadline countdown strip
final hrDeadlinesProvider =
    FutureProvider.autoDispose.family<List<HrDeadline>, String>(
        (ref, cycleId) {
  return ref.watch(hrDashboardRepositoryProvider).fetchDeadlines(cycleId);
});
