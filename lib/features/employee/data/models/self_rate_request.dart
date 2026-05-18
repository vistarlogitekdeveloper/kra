import 'kra_score_entry.dart';

/// Wire payload for POST /employee/reviews/:reviewId/self-rate.
///
/// Built from the in-memory [KraScoreEntry] list at submit time.
/// The same endpoint handles both initial submission and edits —
/// there is no separate PATCH because the underlying repository
/// updates the cells you name and leaves the rest alone.
///
/// Field semantics (per server contract):
///   - `monthlyScoreId` — get from rows[].monthlyScores[].id
///   - `selfRating`     — number ≤ row.maxScore; pass null to clear
///   - `selfRemark`     — optional, max 500 chars
///   - `isNotApplicable` — optional, marks the cell as N/A
///   - `autoSubmit`     — defaults to true. When true and every
///                        applicable cell is rated, server transitions
///                        IN_PROGRESS → EMPLOYEE_SUBMITTED_ALL
class SelfRateRequest {
  final List<SelfRateScore> scores;

  /// When true, server auto-advances state to EMPLOYEE_SUBMITTED_ALL
  /// once every applicable cell has a rating. Pass false for partial
  /// saves where the user wants to come back later.
  final bool autoSubmit;

  const SelfRateRequest({
    required this.scores,
    this.autoSubmit = true,
  });

  /// Builds the wire payload from the current draft entries.
  ///
  /// Filtering rules:
  ///   - cells with `selfRating == null && !isNotApplicable` are
  ///     dropped (nothing to send)
  ///   - cells marked N/A always go through (even with null rating)
  ///     so the server records the N/A flag
  factory SelfRateRequest.fromEntries(
    List<KraScoreEntry> entries, {
    bool autoSubmit = true,
  }) {
    return SelfRateRequest(
      autoSubmit: autoSubmit,
      scores: entries
          .where((e) => e.isFilled)
          .map(
            (e) => SelfRateScore(
              monthlyScoreId: e.monthlyScoreId,
              selfRating: e.isNotApplicable ? null : e.selfRating,
              selfRemark:
                  e.selfRemark.trim().isEmpty ? null : e.selfRemark.trim(),
              isNotApplicable: e.isNotApplicable ? true : null,
            ),
          )
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
        'scores': scores.map((e) => e.toJson()).toList(),
        'autoSubmit': autoSubmit,
      };

  SelfRateRequest copyWith({
    List<SelfRateScore>? scores,
    bool? autoSubmit,
  }) {
    return SelfRateRequest(
      scores: scores ?? this.scores,
      autoSubmit: autoSubmit ?? this.autoSubmit,
    );
  }
}

class SelfRateScore {
  final String monthlyScoreId;

  /// Pass `null` to clear an existing rating (or for cells being
  /// flagged N/A — the backend nulls the rating in that case).
  final double? selfRating;
  final String? selfRemark;
  final bool? isNotApplicable;

  const SelfRateScore({
    required this.monthlyScoreId,
    this.selfRating,
    this.selfRemark,
    this.isNotApplicable,
  });

  Map<String, dynamic> toJson() => {
        'monthlyScoreId': monthlyScoreId,
        // Always include selfRating in the payload (including null) so
        // the backend can distinguish "clear rating" from "leave alone";
        // the latter is achieved by simply not sending the cell.
        'selfRating': selfRating,
        if (selfRemark != null) 'selfRemark': selfRemark,
        if (isNotApplicable != null) 'isNotApplicable': isNotApplicable,
      };

  SelfRateScore copyWith({
    String? monthlyScoreId,
    Object? selfRating = _sentinel,
    Object? selfRemark = _sentinel,
    Object? isNotApplicable = _sentinel,
  }) {
    return SelfRateScore(
      monthlyScoreId: monthlyScoreId ?? this.monthlyScoreId,
      selfRating: identical(selfRating, _sentinel)
          ? this.selfRating
          : selfRating as double?,
      selfRemark: identical(selfRemark, _sentinel)
          ? this.selfRemark
          : selfRemark as String?,
      isNotApplicable: identical(isNotApplicable, _sentinel)
          ? this.isNotApplicable
          : isNotApplicable as bool?,
    );
  }

  static const _sentinel = Object();
}
