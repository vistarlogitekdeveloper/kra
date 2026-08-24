import '../../../../core/api/json_parse.dart';
import '../../../../core/enums/kra_reviewer.dart';

/// A single KRA item inside a [KraTemplate]. Weightages must sum to 100
/// (or 1.0) across all items in a template — see [weightagePercent].
///
/// `id` is null for items the user has just typed into the form (not yet
/// persisted). When editing an existing template, the server-assigned id
/// is round-tripped back so the backend can track per-item updates.
class KraTemplateItem {
  final String? id;
  final String name;
  final String? description;
  final String? target;
  final String? trackingMethod;

  /// Which single reviewer rates this KRA in the Review cycle (Reporting
  /// Manager / HR / Accounts). Null until the author picks one — the form
  /// requires it before Save, but a legacy template loaded without it stays
  /// null and the review falls back to averaging whoever rated.
  final KraReviewer? reviewerGroup;

  /// Stored as a percentage (0–100). The API accepts either a decimal
  /// (0.30) or a percentage (30) — see [toJson] for the wire format.
  final double weightage;
  final int sortOrder;

  const KraTemplateItem({
    this.id,
    required this.name,
    this.description,
    this.target,
    this.trackingMethod,
    this.reviewerGroup,
    required this.weightage,
    required this.sortOrder,
  });

  /// Convenience getter — [weightage] is already canonically a 0–100
  /// percentage (normalised at [fromJson] from the wire's 0–1 decimal, and
  /// entered directly as a percentage on the form), so this is the identity.
  /// Do NOT re-apply a `<= 1.0` fraction heuristic here: that would turn a
  /// legitimate sub-1% value (e.g. 0.5%) into 50%, and a user-typed "1" into
  /// 100%, corrupting the form total and the persisted payload.
  double get weightagePercent => weightage;

  factory KraTemplateItem.empty({int sortOrder = 0}) => KraTemplateItem(
        name: '',
        weightage: 0,
        sortOrder: sortOrder,
      );

  factory KraTemplateItem.fromJson(Map<String, dynamic> json) {
    // Backend stores weightage as Prisma Decimal, which serialises to a
    // JSON string ("0.05") — not a number. Tolerate both shapes.
    final raw = JsonParse.parseDouble(json['weightage']) ?? 0;
    // Normalise to percentage (0–100).
    final pct = raw <= 1.0 ? raw * 100 : raw;
    // Wire format uses 1-based sortOrder; we keep 0-based internally so it
    // lines up with `_items[i]` in the form. Clamp at 0 so a malformed
    // payload can't produce a negative index.
    final wireSortOrder = JsonParse.parseInt(json['sortOrder']) ?? 1;
    final internalSortOrder = wireSortOrder > 0 ? wireSortOrder - 1 : 0;
    return KraTemplateItem(
      id: json['id'] as String?,
      name: (json['name'] ?? '') as String,
      description: json['description'] as String?,
      target: json['target'] as String?,
      trackingMethod: json['trackingMethod'] as String?,
      // Tolerate a few key spellings: the app sends `reviewerGroup`, the raw
      // table may surface `reviewer_group` or the legacy `scoreSource`.
      reviewerGroup: KraReviewer.fromApi((json['reviewerGroup'] ??
              json['reviewer_group'] ??
              json['scoreSource'] ??
              json['score_source'])
          ?.toString()),
      weightage: pct,
      sortOrder: internalSortOrder,
    );
  }

  /// Wire format:
  ///   * weightage as a fraction (0–1) — canonical persisted form.
  ///   * sortOrder is 1-based on the wire (backend enforces `>= 1` via Zod),
  ///     even though it stays 0-based internally to match list indices.
  ///   * description / target / trackingMethod are coerced from `null` to
  ///     `''`. The backend's GET serializes nulls fine, but POST + PATCH
  ///     Zod schemas demand strings — sending `null` for an optional field
  ///     the user left blank trips `VAL_001 "Invalid input: expected
  ///     string, received null"` on the whole payload.
  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        'description': description ?? '',
        'target': target ?? '',
        'trackingMethod': trackingMethod ?? '',
        // Which reviewer owns this KRA. `scoreSource` is the field the live
        // template API actually persists (its `score_source` column) and its
        // enum is fixed, so it MUST be sent in that vocabulary. `reviewerGroup`
        // is sent alongside for any backend that reads a dedicated column; the
        // template API simply ignores unknown keys.
        if (reviewerGroup != null)
          'scoreSource': reviewerGroup!.toScoreSource(),
        if (reviewerGroup != null)
          'reviewerGroup': reviewerGroup!.toApiString(),
        'weightage': weightagePercent / 100,
        'sortOrder': sortOrder + 1,
      };

  KraTemplateItem copyWith({
    String? id,
    String? name,
    String? description,
    String? target,
    String? trackingMethod,
    KraReviewer? reviewerGroup,
    double? weightage,
    int? sortOrder,
  }) {
    return KraTemplateItem(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      target: target ?? this.target,
      trackingMethod: trackingMethod ?? this.trackingMethod,
      reviewerGroup: reviewerGroup ?? this.reviewerGroup,
      weightage: weightage ?? this.weightage,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
