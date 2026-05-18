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

  factory PreviousReview.fromJson(Map<String, dynamic> json) =>
      PreviousReview(
        reviewId: JsonParse.parseString(json['reviewId']) ?? '',
        cycleName: JsonParse.parseString(json['cycleName']) ?? '',
        fyLabel: JsonParse.parseString(json['fyLabel']),
        quarterNum: JsonParse.parseInt(json['quarterNum']),
        state: ReviewState.fromApi(
            JsonParse.parseString(json['state']) ?? 'DRAFT'),
        finalTotal: JsonParse.parseDouble(json['finalTotal']),
        endDate: JsonParse.parseDate(json['endDate']),
        employeeName: JsonParse.parseString(json['employeeName']),
        employeeId: JsonParse.parseString(json['employeeId']),
      );

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
