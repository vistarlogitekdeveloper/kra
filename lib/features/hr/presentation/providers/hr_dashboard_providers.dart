import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/org_scope_provider.dart';

import '../../../../core/api/dio_client.dart';
import '../../data/models/hr_dashboard_models.dart';
import '../../data/repositories/api_hr_dashboard_repository.dart';
import '../../data/repositories/hr_dashboard_repository.dart';
import 'employee_providers.dart';
import 'kra_assignment_providers.dart';

// ─────────────────────────────────────────────────────────────────────
// Repository swap point
// ─────────────────────────────────────────────────────────────────────

final hrDashboardRepositoryProvider = Provider<HrDashboardRepository>((ref) {
  // Org-scoped: recreated whenever the caller switches organisation, which
  // invalidates every provider that watches this repository. Without it,
  // cached lists from the previous tenant would be served under the new
  // tenant's name. See core/providers/org_scope_provider.dart.
  ref.watch(currentOrgIdProvider);
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

/// How many DISTINCT employees hold a KRA assignment, and how many are active.
///
/// Shown beside the active-employee count because the two numbers only mean
/// something together: 42 active employees with 44 pending reviews reads as
/// arithmetic gone wrong, when the real question is how many of those 42 have
/// KRAs to be reviewed at all. An unassigned employee generates no review and
/// earns no incentive, and nothing else on this dashboard says so.
///
/// DISTINCT is the whole point: an employee may hold several assignments (one
/// per template), so counting rows would report more "assigned employees" than
/// the organisation employs — the same shape of error as the count this card
/// sits next to.
///
/// Scoped to the cycle under review when there is one. An assignment from a
/// closed cycle is history: counting it would claim coverage the current
/// quarter does not have. With no active cycle every assignment counts, which
/// is the only honest answer when there is no cycle to scope to.
final hrAssignedEmployeeCountProvider =
    FutureProvider.autoDispose<({int assigned, int active})>((ref) async {
  ref.keepAlive();
  // AWAITED, not read as a current value. `hrActiveCycleIdProvider` is a
  // synchronous projection of an async fetch, so on the first build its value
  // is null — and a null here does not mean "no active cycle", it means "not
  // loaded yet". Reading it unwrapped silently counted every closed cycle's
  // assignments and produced a plausible, wrong number.
  final cycle = await ref.watch(hrActiveCycleProvider.future);
  final cycleId = cycle?.id;
  final assignments = await ref.read(kraAssignmentRepositoryProvider).list();
  final scoped = cycleId == null
      ? assignments
      : assignments.where((a) => a.cycleId == cycleId);
  final active = await ref.watch(hrActiveEmployeeCountProvider.future);
  return (
    assigned: scoped.map((a) => a.employeeId).toSet().length,
    active: active,
  );
});

// ─────────────────────────────────────────────────────────────────────
// 2. Active cycle — GET /hr/dashboard/active-cycle
//    This is the "root" provider: other cycle-scoped providers depend on
//    the id it exposes.
// ─────────────────────────────────────────────────────────────────────

final hrActiveCycleProvider = FutureProvider.autoDispose<HrActiveCycle?>((ref) {
  ref.keepAlive();
  return ref.watch(hrDashboardRepositoryProvider).fetchActiveCycle();
});

// Derived: just the ID — used by the family providers below.
final hrActiveCycleIdProvider =
    Provider.autoDispose<AsyncValue<String?>>((ref) {
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
final hrPipelineProvider = FutureProvider.autoDispose
    .family<List<HrPipelineItem>, String>((ref, cycleId) {
  ref.keepAlive();
  return ref.watch(hrDashboardRepositoryProvider).fetchPipeline(cycleId);
});

/// 5. Action items that need HR attention
final hrActionItemsProvider = FutureProvider.autoDispose
    .family<List<HrActionItem>, String>((ref, cycleId) {
  ref.keepAlive();
  return ref.watch(hrDashboardRepositoryProvider).fetchActionItems(cycleId);
});

/// 6. Location heatmap (lazy — below the fold)
final hrLocationHeatmapProvider = FutureProvider.autoDispose
    .family<HrLocationHeatmap, String>((ref, cycleId) {
  ref.keepAlive();
  return ref.watch(hrDashboardRepositoryProvider).fetchLocationHeatmap(cycleId);
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
    FutureProvider.autoDispose.family<List<HrDeadline>, String>((ref, cycleId) {
  ref.keepAlive();
  return ref.watch(hrDashboardRepositoryProvider).fetchDeadlines(cycleId);
});
