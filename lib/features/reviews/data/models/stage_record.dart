import '../../../../core/api/json_parse.dart';

/// One row of "who did what, when" attached to a `MonthlyReview`.
///
/// A [StageRecord] is created the moment a stage is submitted — before
/// that the stage has no record. The presence of a record in the review's
/// `stageRecords` map is what the state machine uses to decide whether a stage
/// is complete — EXCEPT when [returned] is set, because that submission sent
/// the review backwards rather than completing anything.
class StageRecord {
  /// Employee id of the user who submitted this stage.
  final String actorId;

  /// Denormalised display name for "submitted by X" without a second
  /// fetch. May be empty on payloads from older backends.
  final String actorName;

  final DateTime submittedAt;

  /// Optional actor comment. Used by management-review and payout
  /// stages; rating stages usually leave this blank because per-row
  /// remarks live on `RowScore` instead.
  final String? comment;

  /// True when this submission sent the review BACK a stage instead of
  /// advancing it — management returning work to the reporting manager, or the
  /// manager returning a self-rating to the employee for rework.
  ///
  /// The stage it belongs to therefore is NOT complete, and [comment] carries
  /// the reason it came back. Absent on older payloads, so it defaults false.
  final bool returned;

  const StageRecord({
    required this.actorId,
    required this.actorName,
    required this.submittedAt,
    this.comment,
    this.returned = false,
  });

  factory StageRecord.fromJson(Map<String, dynamic> json) => StageRecord(
        actorId: JsonParse.parseString(json['actorId']) ?? '',
        actorName: JsonParse.parseString(json['actorName']) ?? '',
        submittedAt: JsonParse.parseDate(json['submittedAt']) ??
            JsonParse.parseDate(json['actedAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        comment: JsonParse.parseString(json['comment']),
        returned: JsonParse.parseBool(json['returned']) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'actorId': actorId,
        'actorName': actorName,
        'submittedAt': submittedAt.toIso8601String(),
        'comment': comment,
        'returned': returned,
      };

  StageRecord copyWith({
    String? actorId,
    String? actorName,
    DateTime? submittedAt,
    String? comment,
    bool? returned,
  }) {
    return StageRecord(
      actorId: actorId ?? this.actorId,
      actorName: actorName ?? this.actorName,
      submittedAt: submittedAt ?? this.submittedAt,
      comment: comment ?? this.comment,
      returned: returned ?? this.returned,
    );
  }
}
