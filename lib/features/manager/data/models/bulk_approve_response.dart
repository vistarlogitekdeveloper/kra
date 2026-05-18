import '../../../../core/api/json_parse.dart';
import 'bulk_approved_item.dart';
import 'bulk_skipped_item.dart';

/// Response for POST /manager/reviews/bulk-approve. Always returns
/// 200 — partial successes are reported via the `skipped` array
/// rather than HTTP error codes, so the UI can render both halves
/// of the result.
class BulkApproveResponse {
  final int approvedCount;
  final int skippedCount;
  final List<BulkApprovedItem> approved;
  final List<BulkSkippedItem> skipped;

  const BulkApproveResponse({
    required this.approvedCount,
    required this.skippedCount,
    this.approved = const [],
    this.skipped = const [],
  });

  /// Convenience — purely visual cue for the result screen banner.
  bool get isCleanSuccess => skippedCount == 0;

  factory BulkApproveResponse.fromJson(Map<String, dynamic> json) =>
      BulkApproveResponse(
        approvedCount: JsonParse.parseInt(json['approvedCount']) ?? 0,
        skippedCount: JsonParse.parseInt(json['skippedCount']) ?? 0,
        approved: JsonParse.parseMapList(json['approved'])
            .map(BulkApprovedItem.fromJson)
            .toList(),
        skipped: JsonParse.parseMapList(json['skipped'])
            .map(BulkSkippedItem.fromJson)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'approvedCount': approvedCount,
        'skippedCount': skippedCount,
        'approved': approved.map((a) => a.toJson()).toList(),
        'skipped': skipped.map((s) => s.toJson()).toList(),
      };
}
