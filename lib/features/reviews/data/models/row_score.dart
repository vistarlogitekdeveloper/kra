import '../../../../core/api/json_parse.dart';

/// A proof attachment being written with a score.
///
/// Write-only: the bytes travel up as base64 once, on save. They never come
/// back down with the review — the server returns only the file's name/mime and
/// serves the bytes on demand (a sheet pulls 3 reviews x N rows, so inlining
/// attachments would make every fetch enormous).
class ProofFileUpload {
  final String name;
  final String mime;

  /// Raw base64 — no `data:` URI prefix.
  final String base64Data;

  const ProofFileUpload({
    required this.name,
    required this.mime,
    required this.base64Data,
  });

  Map<String, dynamic> toJson() =>
      {'name': name, 'mime': mime, 'data': base64Data};
}

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

  /// Legacy free-text proof note. Superseded by the proof *file* below; kept so
  /// existing rows keep rendering.
  final String? proofNote;

  /// Server-side name/mime of the stored proof attachment (bytes excluded —
  /// see [ProofFileUpload]). Non-null means "an attachment exists", which is
  /// what lets a reporting manager / management see that evidence was filed.
  final String? proofFileName;
  final String? proofFileMime;

  /// Write-only. The backend keys off the PRESENCE of `proofFile`:
  ///   * neither field set → key omitted → server PRESERVES the stored file.
  ///     This matters: editing a % re-sends the row, and we must not make the
  ///     client re-upload the attachment every time (nor silently wipe it).
  ///   * [clearProofFile]  → sends `null` → server REMOVES it.
  ///   * [proofFile]       → sends the object → server REPLACES it.
  final ProofFileUpload? proofFile;
  final bool clearProofFile;

  const RowScore({
    this.value,
    this.remark,
    this.proofNote,
    this.proofFileName,
    this.proofFileMime,
    this.proofFile,
    this.clearProofFile = false,
  });

  bool get isNA => value == null;

  /// True when the actor filed any justification for this score — a reason, a
  /// legacy note, or an attachment. Drives the indicator on the sheet cell.
  bool get hasJustification =>
      (remark?.trim().isNotEmpty ?? false) ||
      (proofNote?.trim().isNotEmpty ?? false) ||
      (proofFileName?.trim().isNotEmpty ?? false);

  factory RowScore.fromJson(Map<String, dynamic> json) => RowScore(
        value: JsonParse.parseDouble(json['value']),
        remark: JsonParse.parseString(json['remark']),
        // Tolerate a couple of likely backend key spellings.
        proofNote: JsonParse.parseString(json['proofNote']) ??
            JsonParse.parseString(json['proof']),
        proofFileName: JsonParse.parseString(json['proofFileName']),
        proofFileMime: JsonParse.parseString(json['proofFileMime']),
      );

  Map<String, dynamic> toJson() => {
        'value': value,
        'remark': remark,
        'proofNote': proofNote,
        // Presence is the signal — only send the key when we mean to change it.
        if (proofFile != null)
          'proofFile': proofFile!.toJson()
        else if (clearProofFile)
          'proofFile': null,
      };

  RowScore copyWith({
    Object? value = _sentinel,
    String? remark,
    String? proofNote,
    String? proofFileName,
    String? proofFileMime,
  }) {
    return RowScore(
      value: identical(value, _sentinel) ? this.value : value as double?,
      remark: remark ?? this.remark,
      proofNote: proofNote ?? this.proofNote,
      proofFileName: proofFileName ?? this.proofFileName,
      proofFileMime: proofFileMime ?? this.proofFileMime,
    );
  }

  static const _sentinel = Object();
}
