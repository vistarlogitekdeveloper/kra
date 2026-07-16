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

  /// Optional actor **reason** for this specific row — why they gave this
  /// score. Rating comments live here rather than on the stage-level record
  /// because they're per-KRA context. Surfaced as the "Reason" field on the
  /// My KRA quarterly sheet's rating dialog.
  final String? remark;

  /// Optional **proof** the actor cites for this score — a link or short note
  /// (evidence). Persisted alongside the score. The quarterly sheet's rating
  /// dialog also allows attaching a proof *file*, but that stays local-only
  /// (not carried on this model) until a backend upload endpoint exists.
  final String? proofNote;

  const RowScore({this.value, this.remark, this.proofNote});

  bool get isNA => value == null;

  /// True when the actor attached any written justification (reason or proof
  /// note) to this score — drives the small indicator on the sheet cell.
  bool get hasJustification =>
      (remark?.trim().isNotEmpty ?? false) ||
      (proofNote?.trim().isNotEmpty ?? false);

  factory RowScore.fromJson(Map<String, dynamic> json) => RowScore(
        value: JsonParse.parseDouble(json['value']),
        remark: JsonParse.parseString(json['remark']),
        // Tolerate a couple of likely backend key spellings.
        proofNote: JsonParse.parseString(json['proofNote']) ??
            JsonParse.parseString(json['proof']),
      );

  Map<String, dynamic> toJson() => {
        'value': value,
        'remark': remark,
        'proofNote': proofNote,
      };

  RowScore copyWith({
    Object? value = _sentinel,
    String? remark,
    String? proofNote,
  }) {
    return RowScore(
      value: identical(value, _sentinel) ? this.value : value as double?,
      remark: remark ?? this.remark,
      proofNote: proofNote ?? this.proofNote,
    );
  }

  static const _sentinel = Object();
}
