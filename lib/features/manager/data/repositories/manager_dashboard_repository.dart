import '../models/manager_dashboard.dart';

/// Contract for the manager-dashboard home aggregate.
///
/// One round-trip endpoint (`GET /manager/dashboard`) returns the
/// greeting card, active cycle, stats grid, pending-actions list, and
/// last-cycle trend. The UI splits the payload across independent
/// section widgets — each one renders its own loading / error state —
/// but they all share this single fetch.
///
/// 403 NO_DIRECT_REPORTS is a domain-meaningful response: the user
/// has manager role but isn't assigned any reports. Implementations
/// should let the typed [ApiError] surface so the screen can render a
/// "no team yet" empty state instead of a generic error.
abstract class ManagerDashboardRepository {
  Future<ManagerDashboard> fetchDashboard();
}
