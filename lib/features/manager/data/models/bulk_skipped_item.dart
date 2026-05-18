import '../../../../core/api/json_parse.dart';
import 'enums.dart';

/// One row in the `skipped` section of a bulk-approve response.
/// Carries enough context for the result screen to render the
/// employee name, the parsed reason ([BulkSkipReason]), and the raw
/// detail string for the "expand for technical detail" accordion.
class BulkSkippedItem {
  final String reviewId;
  final String employeeName;
  final String? employeeCode;
  final BulkSkipReason reason;

  /// Raw reason code from the backend — kept so the mapper can fall
  /// back to a generic message when the enum is [BulkSkipReason.other].
  final String reasonCode;

  /// Free-form additional detail (e.g. which Ops feed is missing).
  final String? detail;

  const BulkSkippedItem({
    required this.reviewId,
    required this.employeeName,
    this.employeeCode,
    required this.reason,
    required this.reasonCode,
    this.detail,
  });

  factory BulkSkippedItem.fromJson(Map<String, dynamic> json) {
    final code = JsonParse.parseString(json['reason']) ?? 'UNKNOWN';
    return BulkSkippedItem(
      reviewId: JsonParse.parseString(json['reviewId']) ?? '',
      employeeName: JsonParse.parseString(json['employeeName']) ?? '',
      employeeCode: JsonParse.parseString(json['employeeCode']),
      reason: BulkSkipReason.fromApi(code),
      reasonCode: code,
      detail: JsonParse.parseString(json['detail']),
    );
  }

  Map<String, dynamic> toJson() => {
        'reviewId': reviewId,
        'employeeName': employeeName,
        'employeeCode': employeeCode,
        'reason': reasonCode,
        'detail': detail,
      };
}
