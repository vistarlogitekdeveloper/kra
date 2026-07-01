import '../../../../core/api/json_parse.dart';

/// One row of "who did what, when" attached to a `MonthlyReview`.
///
/// A [StageRecord] is created the moment a stage is submitted — before
/// that the stage has no record. The **presence** of a record in the
/// review's `stageRecords` map is what the state machine uses to decide
/// whether a stage is complete; there's no stored status flag.
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

  const StageRecord({
    required this.actorId,
    required this.actorName,
    required this.submittedAt,
    this.comment,
  });

  factory StageRecord.fromJson(Map<String, dynamic> json) => StageRecord(
        actorId: JsonParse.parseString(json['actorId']) ?? '',
        actorName: JsonParse.parseString(json['actorName']) ?? '',
        submittedAt: JsonParse.parseDate(json['submittedAt']) ??
            JsonParse.parseDate(json['actedAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        comment: JsonParse.parseString(json['comment']),
      );

  Map<String, dynamic> toJson() => {
        'actorId': actorId,
        'actorName': actorName,
        'submittedAt': submittedAt.toIso8601String(),
        'comment': comment,
      };

  StageRecord copyWith({
    String? actorId,
    String? actorName,
    DateTime? submittedAt,
    String? comment,
  }) {
    return StageRecord(
      actorId: actorId ?? this.actorId,
      actorName: actorName ?? this.actorName,
      submittedAt: submittedAt ?? this.submittedAt,
      comment: comment ?? this.comment,
    );
  }
}
