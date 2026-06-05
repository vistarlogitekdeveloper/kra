import '../../../../core/api/json_parse.dart';
import '../../../employee/data/models/enums.dart';

/// Compact reference to a past quarterly review — surfaced on the
/// detail screen as a "previous reviews" strip so the manager has
/// context (trend) before rating the current quarter.
class PreviousReview {
  final String reviewId;
  final String cycleName;
  final String? fyLabel;
  final int? quarterNum;
  final ReviewState state;
  final double? finalTotal;

  /// When the cycle ended — used for chronological sort + display.
  final DateTime? endDate;

  /// Employee whose review this is. `null` on per-employee history
  /// payloads (the surrounding screen already knows the employee);
  /// populated on the combined team-history view so the tile can
  /// render "name · cycle" without a separate lookup.
  final String? employeeName;
  final String? employeeId;

  const PreviousReview({
    required this.reviewId,
    required this.cycleName,
    this.fyLabel,
    this.quarterNum,
    required this.state,
    this.finalTotal,
    this.endDate,
    this.employeeName,
    this.employeeId,
  });

  factory PreviousReview.fromJson(Map<String, dynamic> json) {
    // Live backend nests cycle data under `reviewCycle` and employee
    // under `employee`. Older payloads inline both. Read live first,
    // fall back to flat names — matches the dual-read pattern used
    // by manager_review_detail.dart.
    final cycle = json['reviewCycle'] ?? json['cycle'];
    final cycleMap = cycle is Map<String, dynamic> ? cycle : const {};

    final employee = json['employee'];
    final empMap = employee is Map<String, dynamic> ? employee : const {};

    return PreviousReview(
      reviewId: JsonParse.parseString(json['reviewId']) ??
          JsonParse.parseString(json['id']) ??
          '',
      cycleName: JsonParse.parseString(cycleMap['name']) ??
          JsonParse.parseString(json['cycleName']) ??
          '',
      fyLabel: JsonParse.parseString(cycleMap['fyLabel']) ??
          JsonParse.parseString(json['fyLabel']),
      quarterNum: JsonParse.parseInt(cycleMap['quarterNum']) ??
          JsonParse.parseInt(json['quarterNum']),
      state: ReviewState.fromApi(
          JsonParse.parseString(json['state']) ?? 'DRAFT'),
      finalTotal: JsonParse.parseDouble(json['finalTotal']) ??
          JsonParse.parseDouble(json['finalAvgManagerPct']) ??
          JsonParse.parseDouble(json['finalAvgSelfPct']),
      endDate: JsonParse.parseDate(cycleMap['endDate']) ??
          JsonParse.parseDate(json['endDate']),
      employeeName: JsonParse.parseString(empMap['name']) ??
          JsonParse.parseString(empMap['fullName']) ??
          JsonParse.parseString(json['employeeName']),
      employeeId: JsonParse.parseString(empMap['id']) ??
          JsonParse.parseString(json['employeeId']),
    );
  }

  Map<String, dynamic> toJson() => {
        'reviewId': reviewId,
        'cycleName': cycleName,
        'fyLabel': fyLabel,
        'quarterNum': quarterNum,
        'state': state.toApiString(),
        'finalTotal': finalTotal,
        'endDate': endDate?.toIso8601String(),
        'employeeName': employeeName,
        'employeeId': employeeId,
      };
}
