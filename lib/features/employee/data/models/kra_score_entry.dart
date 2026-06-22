import 'enums.dart';
import 'my_review_detail.dart';

/// Form state for one cell in the self-rate matrix.
///
/// A "cell" is a (row × month) pair — the smallest unit the backend
/// accepts in POST /employee/reviews/:id/self-rate. The form opens to
/// the active month and presents one entry per applicable row; a
/// future iteration may show multiple months side-by-side.
///
/// This is a UI model, not an API model — it carries the values the
/// user is editing (`selfRating`, `selfRemark`, `isNotApplicable`)
/// plus the immutable row metadata copied across so the form can
/// render without holding a reference to the [MyReview] object.
///
/// Persisted verbatim to SharedPreferences for the auto-save / resume-
/// draft flow (Stage 3) — `toJson` / `fromJson` are draft-storage
/// serialisers, not API serialisers. The wire payload is shaped by
/// [SelfRateRequest] in `self_rate_request.dart`.
class KraScoreEntry {
  /// Backend cell id — what we send in `monthlyScoreId`.
  final String monthlyScoreId;

  /// Convenience for re-keying cells across reload (e.g. after the
  /// review refetches and ids stay stable but scores change).
  final String reviewRowId;
  final String monthId;

  /// Display copy from the row's templateItem.
  final String itemName;
  final String? category;
  final String? description;
  final String? target;
  final String? trackingMethod;

  /// Weightage as a 0–1 fraction (matches the wire form).
  final double weight;

  /// Maximum score the user can give themselves on this cell.
  final double maxScore;

  /// Source of the row's score. SELF and FEED are fully employee-
  /// driven (employee enters value or it's auto-filled); MANAGER rows
  /// are scored by the manager — but the employee may still record a
  /// self-rating on them, which the POST endpoint accepts.
  final ScoreSource scoreSource;

  /// Display order — taken from the parent [ReviewRow.displayOrder]
  /// so a sorted list stays stable across saves.
  final int displayOrder;

  /// Display copy for the month this cell belongs to.
  final String monthLabel;
  final ReviewMonthStatus monthStatus;

  /// Self-rating the user has entered (or restored from draft).
  /// `null` when untouched — submit gates on every applicable cell
  /// being non-null OR `isNotApplicable == true`.
  final double? selfRating;

  /// Optional per-cell comment. Defaults to empty (not null) so the
  /// text controller has a stable initial value.
  final String selfRemark;

  /// Marks the cell as N/A — excluded from weighted-average math
  /// server-side. Most cells are applicable; HR uses N/A for one-off
  /// skips like "employee on extended leave for the month".
  final bool isNotApplicable;

  /// Display name of a locally-attached proof file (image/PDF), or
  /// `null` when none. Stored in the local draft only — there is no
  /// server upload endpoint yet, so this is never sent on the wire.
  final String? attachmentName;

  /// Absolute path to the attached proof file on the device. Kept
  /// alongside [attachmentName] so the draft can re-surface the file.
  final String? attachmentPath;

  const KraScoreEntry({
    required this.monthlyScoreId,
    required this.reviewRowId,
    required this.monthId,
    required this.itemName,
    this.category,
    this.description,
    this.target,
    this.trackingMethod,
    required this.weight,
    required this.maxScore,
    required this.scoreSource,
    required this.displayOrder,
    required this.monthLabel,
    required this.monthStatus,
    this.selfRating,
    this.selfRemark = '',
    this.isNotApplicable = false,
    this.attachmentName,
    this.attachmentPath,
  });

  double get weightagePercent => weight <= 1.0 ? weight * 100 : weight;

  /// True when the cell has a locally-attached proof file.
  bool get hasAttachment =>
      attachmentName != null && attachmentName!.isNotEmpty;

  /// True once the user has supplied a value (or N/A flag) for this
  /// cell. Drives the submit button's enabled state.
  bool get isFilled => isNotApplicable || selfRating != null;

  /// Cell's contribution to the weighted average, scaled to a 0–100
  /// scale. N/A cells contribute 0 and are subtracted from the
  /// denominator at total-time.
  double get weightedContribution {
    if (isNotApplicable) return 0;
    final s = selfRating;
    if (s == null) return 0;
    final normalised = maxScore == 0 ? 0.0 : s / maxScore;
    return normalised * weightagePercent;
  }

  /// Builds an entry from a (row, cell) pair. Used when the form
  /// first opens and there is no draft to restore.
  factory KraScoreEntry.fromRowAndCell(
    ReviewRow row,
    MonthlyScore cell,
  ) {
    return KraScoreEntry(
      monthlyScoreId: cell.id,
      reviewRowId: row.id,
      monthId: cell.monthId,
      itemName: row.templateItem?.name ?? '',
      category: row.templateItem?.category,
      description: row.templateItem?.description,
      target: null,
      trackingMethod: null,
      weight: row.weight,
      maxScore: row.maxScore,
      scoreSource: row.scoreSource,
      displayOrder: row.displayOrder,
      monthLabel: cell.month?.monthLabel ?? '',
      monthStatus: cell.month?.status ?? ReviewMonthStatus.open,
      selfRating: cell.selfRating,
      selfRemark: cell.selfRemark ?? '',
      isNotApplicable: cell.isNotApplicable,
    );
  }

  /// Restores an entry from local draft storage. Mirror of [toJson].
  factory KraScoreEntry.fromJson(Map<String, dynamic> json) {
    final w = json['weight'];
    final m = json['maxScore'];
    final s = json['selfRating'];
    return KraScoreEntry(
      monthlyScoreId: (json['monthlyScoreId'] ?? '') as String,
      reviewRowId: (json['reviewRowId'] ?? '') as String,
      monthId: (json['monthId'] ?? '') as String,
      itemName: (json['itemName'] ?? '') as String,
      category: json['category'] as String?,
      description: json['description'] as String?,
      target: json['target'] as String?,
      trackingMethod: json['trackingMethod'] as String?,
      weight: w is num ? w.toDouble() : double.tryParse('$w') ?? 0,
      maxScore: m is num ? m.toDouble() : double.tryParse('$m') ?? 10,
      scoreSource:
          ScoreSource.fromApi((json['scoreSource'] ?? 'MANAGER') as String),
      displayOrder: (json['displayOrder'] is int)
          ? json['displayOrder'] as int
          : int.tryParse('${json['displayOrder']}') ?? 0,
      monthLabel: (json['monthLabel'] ?? '') as String,
      monthStatus:
          ReviewMonthStatus.fromApi((json['monthStatus'] ?? 'OPEN') as String),
      selfRating:
          s == null ? null : (s is num ? s.toDouble() : double.tryParse('$s')),
      selfRemark: (json['selfRemark'] ?? '') as String,
      isNotApplicable: (json['isNotApplicable'] ?? false) as bool,
      attachmentName: json['attachmentName'] as String?,
      attachmentPath: json['attachmentPath'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'monthlyScoreId': monthlyScoreId,
        'reviewRowId': reviewRowId,
        'monthId': monthId,
        'itemName': itemName,
        'category': category,
        'description': description,
        'target': target,
        'trackingMethod': trackingMethod,
        'weight': weight,
        'maxScore': maxScore,
        'scoreSource': scoreSource.toApiString(),
        'displayOrder': displayOrder,
        'monthLabel': monthLabel,
        'monthStatus': monthStatus.toApiString(),
        'selfRating': selfRating,
        'selfRemark': selfRemark,
        'isNotApplicable': isNotApplicable,
        'attachmentName': attachmentName,
        'attachmentPath': attachmentPath,
      };

  KraScoreEntry copyWith({
    String? monthlyScoreId,
    String? reviewRowId,
    String? monthId,
    String? itemName,
    String? category,
    String? description,
    String? target,
    String? trackingMethod,
    double? weight,
    double? maxScore,
    ScoreSource? scoreSource,
    int? displayOrder,
    String? monthLabel,
    ReviewMonthStatus? monthStatus,
    Object? selfRating = _sentinel,
    String? selfRemark,
    bool? isNotApplicable,
    Object? attachmentName = _sentinel,
    Object? attachmentPath = _sentinel,
  }) {
    return KraScoreEntry(
      monthlyScoreId: monthlyScoreId ?? this.monthlyScoreId,
      reviewRowId: reviewRowId ?? this.reviewRowId,
      monthId: monthId ?? this.monthId,
      itemName: itemName ?? this.itemName,
      category: category ?? this.category,
      description: description ?? this.description,
      target: target ?? this.target,
      trackingMethod: trackingMethod ?? this.trackingMethod,
      weight: weight ?? this.weight,
      maxScore: maxScore ?? this.maxScore,
      scoreSource: scoreSource ?? this.scoreSource,
      displayOrder: displayOrder ?? this.displayOrder,
      monthLabel: monthLabel ?? this.monthLabel,
      monthStatus: monthStatus ?? this.monthStatus,
      selfRating: identical(selfRating, _sentinel)
          ? this.selfRating
          : selfRating as double?,
      selfRemark: selfRemark ?? this.selfRemark,
      isNotApplicable: isNotApplicable ?? this.isNotApplicable,
      attachmentName: identical(attachmentName, _sentinel)
          ? this.attachmentName
          : attachmentName as String?,
      attachmentPath: identical(attachmentPath, _sentinel)
          ? this.attachmentPath
          : attachmentPath as String?,
    );
  }

  static const _sentinel = Object();
}
