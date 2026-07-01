import '../../../../core/api/json_parse.dart';

/// A single actor's score for a single KRA row.
///
/// Attached to a `MonthlyKraRow`'s `stageScores` map, keyed by
/// `ReviewStage`. Only the three rating stages (self, account/HR,
/// reporting manager) create these; management review and incentive
/// payout leave the map untouched for the row.
class RowScore {
  /// 0..`MonthlyKraRow.maxScore`. `null` for "N/A" — the row is exempted
  /// from the weighted total for this stage.
  final double? value;

  /// Optional actor remark for this specific row. Rating comments tend
  /// to live here rather than on the stage-level record because they're
  /// per-KRA context.
  final String? remark;

  const RowScore({this.value, this.remark});

  bool get isNA => value == null;

  factory RowScore.fromJson(Map<String, dynamic> json) => RowScore(
        value: JsonParse.parseDouble(json['value']),
        remark: JsonParse.parseString(json['remark']),
      );

  Map<String, dynamic> toJson() => {
        'value': value,
        'remark': remark,
      };

  RowScore copyWith({
    Object? value = _sentinel,
    String? remark,
  }) {
    return RowScore(
      value: identical(value, _sentinel) ? this.value : value as double?,
      remark: remark ?? this.remark,
    );
  }

  static const _sentinel = Object();
}
