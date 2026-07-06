import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/dio_client.dart';
import '../../data/models/hr_dashboard_models.dart';
import '../../data/repositories/api_hr_dashboard_repository.dart';
import '../../data/repositories/hr_dashboard_repository.dart';
import 'employee_providers.dart';

// ─────────────────────────────────────────────────────────────────────
// Repository swap point
// ─────────────────────────────────────────────────────────────────────

final hrDashboardRepositoryProvider = Provider<HrDashboardRepository>((ref) {
  return ApiHrDashboardRepository(dio: ref.read(dioProvider));
});

// ─────────────────────────────────────────────────────────────────────
// 1. Overview cards — GET /hr/dashboard
// ─────────────────────────────────────────────────────────────────────
//
// Why `ref.keepAlive()` on all of these:
//
// The HR home screen is a tall ListView whose sections each watch one of
// these providers. As the user scrolls past a section's viewport +
// cacheExtent, Flutter unmounts that section's element — its `ref.watch`
// drops, the autoDispose timer fires, and the cached AsyncValue is
// thrown away. Scrolling back re-mounts the section, which triggers a
// brand-new HTTP fetch. On a slow backend (Render free-tier cold start)
// this presents as the section "loading forever" because every scroll
// trip restarts the request from zero — the location heatmap, which
// sits at the bottom of the page, was the most visible victim.
//
// `ref.keepAlive()` retains the resolved AsyncValue for the session, so
// a remount picks up the cached value instead of refetching. The pull-
// to-refresh handler still calls `ref.invalidate(...)` explicitly, so
// the data stays user-refreshable.

final hrOverviewProvider = FutureProvider.autoDispose<HrOverview>((ref) {
  ref.keepAlive();
  return ref.watch(hrDashboardRepositoryProvider).fetchOverview();
});

// Authoritative active-employee count for the overview card.
//
// The backend `GET /hr/dashboard` overview returns a wrong `activeEmployees`
// figure (observed 6 while the roster actually holds 26 active employees).
// The `/employees` list is the source of truth, so we read its paginated
// `total` with `isActive: true`. We fetch `pageSize: 1` because only the
// envelope's `total` is needed, not the rows themselves.
final hrActiveEmployeeCountProvider = FutureProvider.autoDispose<int>((ref) {
  ref.keepAlive();
  return ref
      .watch(employeeRepositoryProvider)
      .list(page: 1, pageSize: 1, isActive: true)
      .then((page) => page.total);
});

// ─────────────────────────────────────────────────────────────────────
// 2. Active cycle — GET /hr/dashboard/active-cycle
//    This is the "root" provider: other cycle-scoped providers depend on
//    the id it exposes.
// ─────────────────────────────────────────────────────────────────────

final hrActiveCycleProvider =
    FutureProvider.autoDispose<HrActiveCycle?>((ref) {
  ref.keepAlive();
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
  ref.keepAlive();
  return ref.watch(hrDashboardRepositoryProvider).fetchKpis(cycleId);
});

/// 4. Review pipeline funnel
final hrPipelineProvider =
    FutureProvider.autoDispose.family<List<HrPipelineItem>, String>(
        (ref, cycleId) {
  ref.keepAlive();
  return ref.watch(hrDashboardRepositoryProvider).fetchPipeline(cycleId);
});

/// 5. Action items that need HR attention
final hrActionItemsProvider =
    FutureProvider.autoDispose.family<List<HrActionItem>, String>(
        (ref, cycleId) {
  ref.keepAlive();
  return ref.watch(hrDashboardRepositoryProvider).fetchActionItems(cycleId);
});

/// 6. Location heatmap (lazy — below the fold)
final hrLocationHeatmapProvider =
    FutureProvider.autoDispose.family<HrLocationHeatmap, String>(
        (ref, cycleId) {
  ref.keepAlive();
  return ref
      .watch(hrDashboardRepositoryProvider)
      .fetchLocationHeatmap(cycleId);
});

/// 7. Recent activity — not cycle-scoped
final hrRecentActivityProvider =
    FutureProvider.autoDispose<List<HrActivityEntry>>((ref) {
  ref.keepAlive();
  return ref
      .watch(hrDashboardRepositoryProvider)
      .fetchRecentActivity(limit: 15);
});

/// 8. Deadline countdown strip
final hrDeadlinesProvider =
    FutureProvider.autoDispose.family<List<HrDeadline>, String>(
        (ref, cycleId) {
  ref.keepAlive();
  return ref.watch(hrDashboardRepositoryProvider).fetchDeadlines(cycleId);
});
