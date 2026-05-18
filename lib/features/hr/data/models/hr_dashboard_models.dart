import '../../../../core/api/json_parse.dart';

// Models for all 8 HR Dashboard API endpoints.
// Every class is a plain immutable Dart object with a [fromJson] factory.
// Null-safe — every optional field from the server is marked nullable.

// ─────────────────────────────────────────────────────────────────────
// 1. GET /hr/dashboard  → HrOverview
// ─────────────────────────────────────────────────────────────────────

class HrOverviewCycle {
  final String id;
  final String name;
  final String status;
  final DateTime endDate;

  const HrOverviewCycle({
    required this.id,
    required this.name,
    required this.status,
    required this.endDate,
  });

  factory HrOverviewCycle.fromJson(Map<String, dynamic> j) => HrOverviewCycle(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        status: (j['status'] ?? '') as String,
        endDate: _dt(j['endDate']) ?? DateTime.now(),
      );
}

class HrOverview {
  final int activeEmployees;
  final int pendingReviews;
  final double totalPayout;
  final HrOverviewCycle? cycle;

  const HrOverview({
    required this.activeEmployees,
    required this.pendingReviews,
    required this.totalPayout,
    this.cycle,
  });

  factory HrOverview.fromJson(Map<String, dynamic> j) => HrOverview(
        activeEmployees: (j['activeEmployees'] as int?) ?? 0,
        pendingReviews: (j['pendingReviews'] as int?) ?? 0,
        totalPayout: _toDoubleSafe(j['totalPayout']),
        cycle: j['cycle'] is Map<String, dynamic>
            ? HrOverviewCycle.fromJson(j['cycle'] as Map<String, dynamic>)
            : null,
      );
}

// ─────────────────────────────────────────────────────────────────────
// 2. GET /hr/dashboard/active-cycle  → HrActiveCycle
// ─────────────────────────────────────────────────────────────────────

class HrCycleMonth {
  final String id;
  final String monthLabel;
  final DateTime monthDate;
  final String status; // OPEN | CLOSED | LOCKED

  const HrCycleMonth({
    required this.id,
    required this.monthLabel,
    required this.monthDate,
    required this.status,
  });

  factory HrCycleMonth.fromJson(Map<String, dynamic> j) => HrCycleMonth(
        id: (j['id'] ?? '') as String,
        monthLabel: (j['monthLabel'] ?? '') as String,
        monthDate: _dt(j['monthDate']) ?? DateTime.now(),
        status: (j['status'] ?? 'OPEN') as String,
      );
}

class HrActiveCycle {
  final String id;
  final String name;
  final String status;
  final String? fyLabel;
  final int? quarterNum;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime? selfRatingDeadline;
  final DateTime? managerReviewDeadline;
  final DateTime? opsScoringDeadline;
  final DateTime? financeScoringDeadline;
  final List<HrCycleMonth> months;

  const HrActiveCycle({
    required this.id,
    required this.name,
    required this.status,
    this.fyLabel,
    this.quarterNum,
    required this.startDate,
    required this.endDate,
    this.selfRatingDeadline,
    this.managerReviewDeadline,
    this.opsScoringDeadline,
    this.financeScoringDeadline,
    this.months = const [],
  });

  factory HrActiveCycle.fromJson(Map<String, dynamic> j) => HrActiveCycle(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        status: (j['status'] ?? '') as String,
        fyLabel: j['fyLabel'] as String?,
        quarterNum: j['quarterNum'] as int?,
        startDate: _dt(j['startDate']) ?? DateTime.now(),
        endDate: _dt(j['endDate']) ?? DateTime.now(),
        selfRatingDeadline: _dt(j['selfRatingDeadline']),
        managerReviewDeadline: _dt(j['managerReviewDeadline']),
        opsScoringDeadline: _dt(j['opsScoringDeadline']),
        financeScoringDeadline: _dt(j['financeScoringDeadline']),
        months: (j['months'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(HrCycleMonth.fromJson)
            .toList(),
      );
}

// ─────────────────────────────────────────────────────────────────────
// 3. GET /hr/dashboard/kpis?cycleId=  → HrKpis
// ─────────────────────────────────────────────────────────────────────

class HrKpiCompletion {
  final int finalized;
  final int total;
  final double pct;

  const HrKpiCompletion({
    required this.finalized,
    required this.total,
    required this.pct,
  });

  factory HrKpiCompletion.fromJson(Map<String, dynamic> j) => HrKpiCompletion(
        finalized: (j['finalized'] as int?) ?? 0,
        total: (j['total'] as int?) ?? 0,
        pct: _toDoubleSafe(j['pct']),
      );
}

class HrKpiPool {
  final double quarterlyFixed;
  final double payableSoFar;
  final double payoutPct;

  const HrKpiPool({
    required this.quarterlyFixed,
    required this.payableSoFar,
    required this.payoutPct,
  });

  factory HrKpiPool.fromJson(Map<String, dynamic> j) => HrKpiPool(
        quarterlyFixed: _toDoubleSafe(j['quarterlyFixed']),
        payableSoFar: _toDoubleSafe(j['payableSoFar']),
        payoutPct: _toDoubleSafe(j['payoutPct']),
      );
}

class HrKpis {
  final int activeEmployees;
  final int totalEmployees;
  final int pendingReviews;
  final double totalPayout;
  final HrKpiCompletion? completion;
  final HrKpiPool? pool;

  const HrKpis({
    required this.activeEmployees,
    required this.totalEmployees,
    required this.pendingReviews,
    required this.totalPayout,
    this.completion,
    this.pool,
  });

  factory HrKpis.fromJson(Map<String, dynamic> j) {
    // Support both flat + nested employee keys
    final empMap = j['employees'] as Map<String, dynamic>?;
    return HrKpis(
      activeEmployees:
          (empMap?['active'] as int?) ?? (j['activeEmployees'] as int?) ?? 0,
      totalEmployees:
          (empMap?['total'] as int?) ?? (j['totalEmployees'] as int?) ?? 0,
      pendingReviews: (j['pendingReviews'] as int?) ?? 0,
      totalPayout: _toDoubleSafe(j['totalPayout']),
      completion: j['completion'] is Map<String, dynamic>
          ? HrKpiCompletion.fromJson(j['completion'] as Map<String, dynamic>)
          : null,
      pool: j['pool'] is Map<String, dynamic>
          ? HrKpiPool.fromJson(j['pool'] as Map<String, dynamic>)
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// 4. GET /hr/dashboard/pipeline?cycleId=  → List<HrPipelineItem>
// ─────────────────────────────────────────────────────────────────────

class HrPipelineItem {
  final String state;
  final int count;
  final int stuck;

  const HrPipelineItem({
    required this.state,
    required this.count,
    required this.stuck,
  });

  factory HrPipelineItem.fromJson(Map<String, dynamic> j) => HrPipelineItem(
        state: (j['state'] ?? '') as String,
        count: (j['count'] as int?) ?? 0,
        stuck: (j['stuck'] as int?) ?? 0,
      );

  /// Human-readable label for this state.
  String get displayLabel {
    switch (state) {
      case 'DRAFT':
        return 'Draft';
      case 'IN_PROGRESS':
        return 'In Progress';
      case 'EMPLOYEE_SUBMITTED_ALL':
        return 'Submitted';
      case 'MANAGER_RATED_ALL':
        return 'Manager Rated';
      case 'FINALIZED':
        return 'Finalized';
      case 'ACKNOWLEDGED':
        return 'Acknowledged';
      default:
        return state;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────
// 5. GET /hr/dashboard/action-items?cycleId=  → List<HrActionItem>
// ─────────────────────────────────────────────────────────────────────

enum ActionSeverity { info, warning, critical }

class HrActionItem {
  final String key;
  final ActionSeverity severity;
  final String headline;
  final int count;
  final String? deepLink;

  const HrActionItem({
    required this.key,
    required this.severity,
    required this.headline,
    required this.count,
    this.deepLink,
  });

  factory HrActionItem.fromJson(Map<String, dynamic> j) {
    final sev = (j['severity'] ?? 'info') as String;
    return HrActionItem(
      key: (j['key'] ?? '') as String,
      severity: sev == 'critical'
          ? ActionSeverity.critical
          : sev == 'warning'
              ? ActionSeverity.warning
              : ActionSeverity.info,
      headline: (j['headline'] ?? '') as String,
      count: (j['count'] as int?) ?? 0,
      deepLink: j['deepLink'] as String?,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// 6. GET /hr/dashboard/location-heatmap?cycleId=  → HrLocationHeatmap
// ─────────────────────────────────────────────────────────────────────

class HrHeatmapMonth {
  final String id;
  final String label;

  const HrHeatmapMonth({required this.id, required this.label});

  factory HrHeatmapMonth.fromJson(Map<String, dynamic> j) => HrHeatmapMonth(
        id: (j['id'] ?? '') as String,
        label: (j['label'] ?? '') as String,
      );
}

class HrHeatmapCell {
  final String monthId;
  final String monthLabel;
  final double? avgPct; // null = no data
  final int reviewCount;

  const HrHeatmapCell({
    required this.monthId,
    required this.monthLabel,
    this.avgPct,
    required this.reviewCount,
  });

  factory HrHeatmapCell.fromJson(Map<String, dynamic> j) => HrHeatmapCell(
        monthId: (j['monthId'] ?? '') as String,
        monthLabel: (j['monthLabel'] ?? '') as String,
        avgPct: JsonParse.parseDouble(j['avgPct']),
        reviewCount: (j['reviewCount'] as int?) ?? 0,
      );
}

class HrHeatmapLocation {
  final String locationId;
  final String locationName;
  final List<HrHeatmapCell> cells;

  const HrHeatmapLocation({
    required this.locationId,
    required this.locationName,
    required this.cells,
  });

  factory HrHeatmapLocation.fromJson(Map<String, dynamic> j) =>
      HrHeatmapLocation(
        locationId: (j['locationId'] ?? '') as String,
        locationName: (j['locationName'] ?? '') as String,
        cells: (j['cells'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(HrHeatmapCell.fromJson)
            .toList(),
      );
}

class HrLocationHeatmap {
  final List<HrHeatmapMonth> months;
  final List<HrHeatmapLocation> locations;

  const HrLocationHeatmap({
    required this.months,
    required this.locations,
  });

  factory HrLocationHeatmap.fromJson(Map<String, dynamic> j) =>
      HrLocationHeatmap(
        months: (j['months'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(HrHeatmapMonth.fromJson)
            .toList(),
        locations: (j['locations'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(HrHeatmapLocation.fromJson)
            .toList(),
      );
}

// ─────────────────────────────────────────────────────────────────────
// 7. GET /hr/dashboard/recent-activity?limit=  → List<HrActivityEntry>
// ─────────────────────────────────────────────────────────────────────

class HrActivityActor {
  final String id;
  final String name;
  final String employeeCode;

  const HrActivityActor({
    required this.id,
    required this.name,
    required this.employeeCode,
  });

  factory HrActivityActor.fromJson(Map<String, dynamic> j) => HrActivityActor(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        employeeCode: (j['employeeCode'] ?? '') as String,
      );
}

class HrActivityEntry {
  final String id;
  final String action; // e.g. "KRA_ASSIGNMENT.CREATED"
  final String entityType;
  final String entityId;
  final Map<String, dynamic>? newValues;
  final Map<String, dynamic>? oldValues;
  final Map<String, dynamic>? diff;
  final String? reason;
  final DateTime createdAt;
  final HrActivityActor? user;

  const HrActivityEntry({
    required this.id,
    required this.action,
    required this.entityType,
    required this.entityId,
    this.newValues,
    this.oldValues,
    this.diff,
    this.reason,
    required this.createdAt,
    this.user,
  });

  factory HrActivityEntry.fromJson(Map<String, dynamic> j) => HrActivityEntry(
        id: (j['id'] ?? '') as String,
        action: (j['action'] ?? '') as String,
        entityType: (j['entityType'] ?? '') as String,
        entityId: (j['entityId'] ?? '') as String,
        newValues: j['newValues'] as Map<String, dynamic>?,
        oldValues: j['oldValues'] as Map<String, dynamic>?,
        diff: j['diff'] as Map<String, dynamic>?,
        reason: j['reason'] as String?,
        createdAt: _dt(j['createdAt']) ?? DateTime.now(),
        user: j['user'] is Map<String, dynamic>
            ? HrActivityActor.fromJson(j['user'] as Map<String, dynamic>)
            : null,
      );

  /// Derived human label from action string.
  String get actionLabel {
    final parts = action.split('.');
    if (parts.length < 2) return action;
    final entity = parts.first.replaceAll('_', ' ');
    final verb = parts.last
        .toLowerCase()
        .replaceAll('_', ' ');
    return '$entity $verb';
  }
}

// ─────────────────────────────────────────────────────────────────────
// 8. GET /hr/dashboard/deadlines?cycleId=  → List<HrDeadline>
// ─────────────────────────────────────────────────────────────────────

class HrDeadline {
  final String key;
  final String label;
  final DateTime date;
  final int daysRemaining;

  const HrDeadline({
    required this.key,
    required this.label,
    required this.date,
    required this.daysRemaining,
  });

  bool get isOverdue => daysRemaining < 0;
  bool get isUrgent => daysRemaining >= 0 && daysRemaining <= 7;

  factory HrDeadline.fromJson(Map<String, dynamic> j) => HrDeadline(
        key: (j['key'] ?? '') as String,
        label: (j['label'] ?? '') as String,
        date: _dt(j['date']) ?? DateTime.now(),
        daysRemaining: (j['daysRemaining'] as int?) ?? 0,
      );
}

// ─────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────

DateTime? _dt(dynamic v) => JsonParse.parseDate(v);

double _toDoubleSafe(dynamic v) => JsonParse.parseDouble(v) ?? 0.0;
