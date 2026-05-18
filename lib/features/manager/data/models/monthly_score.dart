import '../../../../core/api/json_parse.dart';
import '../../../employee/data/models/enums.dart';

/// One cell in the manager-rate matrix — (KRA item × month).
///
/// Carries both the manager's input fields (`managerRating`,
/// `managerRemark`) and the employee's self-rating for context — the
/// manager-rate UI renders the self-rating as a muted chip below the
/// input so the manager has the employee's frame of reference.
///
/// `weightedScore` is the server-computed contribution of this cell
/// to the row's total once a manager rating exists. Useful for the
/// running-total preview on the matrix footer; we never edit it
/// client-side.
class MonthlyScore {
  /// Backend cell id — what we send in `monthlyScoreId` on POST.
  final String monthlyScoreId;
  final String monthId;
  final String monthLabel;
  final ReviewMonthStatus monthStatus;

  final double? selfRating;
  final String? selfRemark;

  final double? managerRating;
  final String? managerRemark;

  /// Pre-computed weighted contribution. `null` until a rating exists.
  final double? weightedScore;

  /// Employee marked the cell N/A — manager input is disabled and the
  /// cell counts as 0 weight for total calculations.
  final bool isNotApplicable;

  const MonthlyScore({
    required this.monthlyScoreId,
    required this.monthId,
    required this.monthLabel,
    this.monthStatus = ReviewMonthStatus.open,
    this.selfRating,
    this.selfRemark,
    this.managerRating,
    this.managerRemark,
    this.weightedScore,
    this.isNotApplicable = false,
  });

  /// True if the cell can be edited by the manager right now.
  bool get isEditable =>
      !isNotApplicable && monthStatus == ReviewMonthStatus.open;

  /// True once the manager has supplied a rating (or N/A was flagged
  /// upstream). Drives the per-cell "valid" / "missing" UI state.
  bool get isManagerFilled => isNotApplicable || managerRating != null;

  factory MonthlyScore.fromJson(Map<String, dynamic> json) => MonthlyScore(
        monthlyScoreId:
            JsonParse.parseString(json['monthlyScoreId']) ?? '',
        monthId: JsonParse.parseString(json['monthId']) ?? '',
        monthLabel: JsonParse.parseString(json['monthLabel']) ?? '',
        monthStatus: ReviewMonthStatus.fromApi(
            JsonParse.parseString(json['monthStatus']) ?? 'OPEN'),
        selfRating: JsonParse.parseDouble(json['selfRating']),
        selfRemark: JsonParse.parseString(json['selfRemark']),
        managerRating: JsonParse.parseDouble(json['managerRating']),
        managerRemark: JsonParse.parseString(json['managerRemark']),
        weightedScore: JsonParse.parseDouble(json['weightedScore']),
        isNotApplicable:
            JsonParse.parseBool(json['isNotApplicable']) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'monthlyScoreId': monthlyScoreId,
        'monthId': monthId,
        'monthLabel': monthLabel,
        'monthStatus': monthStatus.toApiString(),
        'selfRating': selfRating,
        'selfRemark': selfRemark,
        'managerRating': managerRating,
        'managerRemark': managerRemark,
        'weightedScore': weightedScore,
        'isNotApplicable': isNotApplicable,
      };

  MonthlyScore copyWith({
    String? monthlyScoreId,
    String? monthId,
    String? monthLabel,
    ReviewMonthStatus? monthStatus,
    Object? selfRating = _sentinel,
    Object? selfRemark = _sentinel,
    Object? managerRating = _sentinel,
    Object? managerRemark = _sentinel,
    Object? weightedScore = _sentinel,
    bool? isNotApplicable,
  }) {
    return MonthlyScore(
      monthlyScoreId: monthlyScoreId ?? this.monthlyScoreId,
      monthId: monthId ?? this.monthId,
      monthLabel: monthLabel ?? this.monthLabel,
      monthStatus: monthStatus ?? this.monthStatus,
      selfRating: identical(selfRating, _sentinel)
          ? this.selfRating
          : selfRating as double?,
      selfRemark: identical(selfRemark, _sentinel)
          ? this.selfRemark
          : selfRemark as String?,
      managerRating: identical(managerRating, _sentinel)
          ? this.managerRating
          : managerRating as double?,
      managerRemark: identical(managerRemark, _sentinel)
          ? this.managerRemark
          : managerRemark as String?,
      weightedScore: identical(weightedScore, _sentinel)
          ? this.weightedScore
          : weightedScore as double?,
      isNotApplicable: isNotApplicable ?? this.isNotApplicable,
    );
  }

  static const _sentinel = Object();
}
