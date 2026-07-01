import '../../../../core/api/json_parse.dart';
import 'manager_stats.dart';
import 'pending_action.dart';

/// Full payload for GET /manager/dashboard. Each top-level field is
/// nullable so a slow or partial backend doesn't crash the home —
/// each card on the dashboard renders an empty/loading variant when
/// its slice is missing.
class ManagerDashboard {
  final ManagerCardUser manager;
  final ManagerActiveCycle? activeCycle;
  final ManagerStats stats;
  final List<PendingAction> pendingActions;
  final TeamTrend? lastCycleTrend;

  const ManagerDashboard({
    required this.manager,
    this.activeCycle,
    required this.stats,
    this.pendingActions = const [],
    this.lastCycleTrend,
  });

  factory ManagerDashboard.fromJson(Map<String, dynamic> json) {
    // The live backend surfaces the last-completed-cycle trend under
    // `teamPerformance.lastCompletedMonth`; an earlier contract used a
    // flat `lastCycleTrend`. Read the flat key first, then fall back to
    // the nested live shape. Either way the card stays hidden until the
    // backend actually populates it (both are null on an open cycle).
    final trendMap = JsonParse.parseMap(json['lastCycleTrend']) ??
        JsonParse.parseMap(
          JsonParse.parseMap(json['teamPerformance'])?['lastCompletedMonth'],
        );
    return ManagerDashboard(
      manager: ManagerCardUser.fromJson(
          JsonParse.parseMap(json['manager']) ?? const {}),
      activeCycle: JsonParse.parseMap(json['activeCycle']) == null
          ? null
          : ManagerActiveCycle.fromJson(
              JsonParse.parseMap(json['activeCycle'])!),
      stats: ManagerStats.fromJson(
          JsonParse.parseMap(json['stats']) ?? const {}),
      pendingActions: JsonParse.parseMapList(json['pendingActions'])
          .map(PendingAction.fromJson)
          .toList(),
      lastCycleTrend: trendMap == null ? null : TeamTrend.fromJson(trendMap),
    );
  }

  Map<String, dynamic> toJson() => {
        'manager': manager.toJson(),
        'activeCycle': activeCycle?.toJson(),
        'stats': stats.toJson(),
        'pendingActions':
            pendingActions.map((p) => p.toJson()).toList(),
        'lastCycleTrend': lastCycleTrend?.toJson(),
      };
}

/// Header card on the manager dashboard. Same shape as the auth User
/// but limited to display fields — keeps the dashboard self-contained
/// in case `/auth/me` data has aged out.
class ManagerCardUser {
  final String id;
  final String name;
  final String employeeCode;
  final String? role;
  final String? grade;
  final String? projectLocation;

  const ManagerCardUser({
    required this.id,
    required this.name,
    required this.employeeCode,
    this.role,
    this.grade,
    this.projectLocation,
  });

  factory ManagerCardUser.fromJson(Map<String, dynamic> json) =>
      ManagerCardUser(
        id: JsonParse.parseString(json['id']) ?? '',
        name: JsonParse.parseString(json['name']) ?? '',
        employeeCode: JsonParse.parseString(json['employeeCode']) ?? '',
        role: JsonParse.parseString(json['role']),
        grade: JsonParse.parseString(json['grade']),
        projectLocation: JsonParse.parseString(json['projectLocation']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'employeeCode': employeeCode,
        'role': role,
        'grade': grade,
        'projectLocation': projectLocation,
      };
}

/// Active-cycle card on the manager dashboard. Carries the manager-
/// review deadline so the card can render a days-remaining pill in
/// the right colour.
class ManagerActiveCycle {
  final String id;
  final String name;
  final String status;
  final String? fyLabel;
  final int? quarterNum;
  final DateTime? endDate;
  final DateTime? managerReviewDeadline;
  final int? deadlineRemaining;

  const ManagerActiveCycle({
    required this.id,
    required this.name,
    required this.status,
    this.fyLabel,
    this.quarterNum,
    this.endDate,
    this.managerReviewDeadline,
    this.deadlineRemaining,
  });

  factory ManagerActiveCycle.fromJson(Map<String, dynamic> json) =>
      ManagerActiveCycle(
        id: JsonParse.parseString(json['id']) ?? '',
        name: JsonParse.parseString(json['name']) ?? '',
        status: JsonParse.parseString(json['status']) ?? '',
        fyLabel: JsonParse.parseString(json['fyLabel']),
        quarterNum: JsonParse.parseInt(json['quarterNum']),
        endDate: JsonParse.parseDate(json['endDate']),
        managerReviewDeadline:
            JsonParse.parseDate(json['managerReviewDeadline']),
        deadlineRemaining:
            JsonParse.parseInt(json['deadlineRemaining']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'status': status,
        'fyLabel': fyLabel,
        'quarterNum': quarterNum,
        'endDate': endDate?.toIso8601String(),
        'managerReviewDeadline':
            managerReviewDeadline?.toIso8601String(),
        'deadlineRemaining': deadlineRemaining,
      };
}

/// Last-completed-cycle summary card on the dashboard.
class TeamTrend {
  final String cycleId;
  final String cycleName;
  final double averageScore;
  final TopPerformer? highest;
  final TopPerformer? lowest;
  final double completionRate;

  const TeamTrend({
    required this.cycleId,
    required this.cycleName,
    required this.averageScore,
    this.highest,
    this.lowest,
    required this.completionRate,
  });

  factory TeamTrend.fromJson(Map<String, dynamic> json) => TeamTrend(
        // Live "last completed month" uses month-based keys
        // (monthId / monthLabel / finalTotal); the earlier cycle-trend
        // contract used cycleId / cycleName / averageScore. Read both.
        cycleId: JsonParse.parseString(json['cycleId']) ??
            JsonParse.parseString(json['monthId']) ??
            '',
        cycleName: JsonParse.parseString(json['cycleName']) ??
            JsonParse.parseString(json['monthLabel']) ??
            '',
        averageScore: JsonParse.parseDouble(json['averageScore']) ??
            JsonParse.parseDouble(json['finalTotal']) ??
            0,
        highest: JsonParse.parseMap(json['highest']) == null
            ? null
            : TopPerformer.fromJson(JsonParse.parseMap(json['highest'])!),
        lowest: JsonParse.parseMap(json['lowest']) == null
            ? null
            : TopPerformer.fromJson(JsonParse.parseMap(json['lowest'])!),
        completionRate:
            JsonParse.parseDouble(json['completionRate']) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'cycleId': cycleId,
        'cycleName': cycleName,
        'averageScore': averageScore,
        'highest': highest?.toJson(),
        'lowest': lowest?.toJson(),
        'completionRate': completionRate,
      };
}

class TopPerformer {
  final String employeeId;
  final String name;
  final double score;

  const TopPerformer({
    required this.employeeId,
    required this.name,
    required this.score,
  });

  factory TopPerformer.fromJson(Map<String, dynamic> json) =>
      TopPerformer(
        employeeId: JsonParse.parseString(json['employeeId']) ?? '',
        name: JsonParse.parseString(json['name']) ?? '',
        score: JsonParse.parseDouble(json['score']) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'employeeId': employeeId,
        'name': name,
        'score': score,
      };
}
