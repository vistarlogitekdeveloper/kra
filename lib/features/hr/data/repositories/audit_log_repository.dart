import '../models/hr_dashboard_models.dart';

/// Contract for fetching the organisation's audit trail.
///
/// The endpoint returns timestamped change-records (who did what to
/// which entity, with before/after diffs). Used by the HR Reports
/// sub-tab and the drawer's "Audit Log" link.
///
/// Pagination: same spec as all other list endpoints
/// (`page`, `pageSize`, `total`, `totalPages`).
abstract class AuditLogRepository {
  /// Paginated, filterable list of audit entries.
  /// All filter params are optional — when omitted the backend returns
  /// everything in reverse chronological order.
  Future<AuditLogPage> fetchLogs({
    int page = 1,
    int pageSize = 20,
    String? actorId,
    String? action,
    String? entityType,
    DateTime? dateFrom,
    DateTime? dateTo,
  });
}

/// Lightweight paged wrapper for audit entries. Mirrors `EmployeePage`
/// / `MyReviewPage` for pagination math consistency.
class AuditLogPage {
  final List<HrActivityEntry> entries;
  final int page;
  final int pageSize;
  final int total;

  const AuditLogPage({
    required this.entries,
    this.page = 1,
    this.pageSize = 20,
    this.total = 0,
  });

  bool get hasMore => entries.length + ((page - 1) * pageSize) < total;
}
