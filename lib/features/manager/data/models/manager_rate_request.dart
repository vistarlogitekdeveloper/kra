/// Wire payload for POST /manager/reviews/:reviewId/manager-rate.
///
/// `scores` contains only the cells the manager has rated this
/// session (cells the manager wants to leave unchanged are simply
/// omitted). `autoSubmit` controls whether the server should attempt
/// the state transition once all cells are present — set `false` for
/// "save draft and continue later", `true` for the final Submit.
class ManagerRateRequest {
  final List<ManagerRateScore> scores;
  final String? managerComment;
  final bool autoSubmit;

  const ManagerRateRequest({
    required this.scores,
    this.managerComment,
    this.autoSubmit = true,
  });

  Map<String, dynamic> toJson() => {
        'scores': scores.map((s) => s.toJson()).toList(),
        if (managerComment != null) 'managerComment': managerComment,
        'autoSubmit': autoSubmit,
      };
}

class ManagerRateScore {
  final String monthlyScoreId;

  /// Manager's rating. Numeric, ≤ `maxScore` of the row. `null`
  /// clears any previously-stored value on that cell.
  final double? managerRating;

  /// Optional per-cell comment, max 200 chars (enforced by the UI).
  final String? managerRemark;

  const ManagerRateScore({
    required this.monthlyScoreId,
    this.managerRating,
    this.managerRemark,
  });

  Map<String, dynamic> toJson() => {
        'monthlyScoreId': monthlyScoreId,
        // Always include `managerRating` (even when null) so the
        // backend can distinguish "clear" from "leave alone".
        'managerRating': managerRating,
        if (managerRemark != null) 'managerRemark': managerRemark,
      };
}
