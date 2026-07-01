import '../../../../core/api/json_parse.dart';
import 'review_stage.dart';
import 'row_score.dart';

/// One KRA line item on a `MonthlyReview`.
///
/// Metadata (name, weightage, max score, target, tracking method) is
/// snapshotted from the employee's active template when the monthly
/// review is generated, so a mid-month template edit doesn't retro-
/// change a row an employee already scored.
///
/// Per-stage scores live in [stageScores] keyed by [ReviewStage]. Rating
/// stages (self, account/HR, reporting manager) write there; non-rating
/// stages (management review, incentive payout) leave the map alone.
class MonthlyKraRow {
  final String id;
  final String name;
  final String? category;

  /// 0..100. The template stores weightage as a fraction (0..1) on the
  /// wire; this row keeps it as a percentage so the UI renders directly.
  final double weightagePercent;

  /// Row-level max score (default 100 unless the template overrides).
  final double maxScore;

  final String? target;
  final String? trackingMethod;

  /// Sort position within the review — lower renders first.
  final int displayOrder;

  final Map<ReviewStage, RowScore> stageScores;

  const MonthlyKraRow({
    required this.id,
    required this.name,
    this.category,
    required this.weightagePercent,
    this.maxScore = 100,
    this.target,
    this.trackingMethod,
    this.displayOrder = 0,
    this.stageScores = const {},
  });

  RowScore? scoreFor(ReviewStage stage) => stageScores[stage];

  /// Has the actor for [stage] entered any value or remark yet?
  bool hasEntryFor(ReviewStage stage) {
    final s = stageScores[stage];
    return s != null && (s.value != null || (s.remark ?? '').isNotEmpty);
  }

  factory MonthlyKraRow.fromJson(Map<String, dynamic> json) {
    final scores = <ReviewStage, RowScore>{};
    final raw = JsonParse.parseMap(json['stageScores']);
    if (raw != null) {
      raw.forEach((k, v) {
        final map = JsonParse.parseMap(v);
        if (map != null) scores[ReviewStage.fromApi(k)] = RowScore.fromJson(map);
      });
    }
    return MonthlyKraRow(
      id: JsonParse.parseString(json['id']) ?? '',
      name: JsonParse.parseString(json['name']) ?? '',
      category: JsonParse.parseString(json['category']),
      weightagePercent: JsonParse.parseDouble(json['weightagePercent']) ?? 0,
      maxScore: JsonParse.parseDouble(json['maxScore']) ?? 100,
      target: JsonParse.parseString(json['target']),
      trackingMethod: JsonParse.parseString(json['trackingMethod']),
      displayOrder: JsonParse.parseInt(json['displayOrder']) ?? 0,
      stageScores: scores,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'weightagePercent': weightagePercent,
        'maxScore': maxScore,
        'target': target,
        'trackingMethod': trackingMethod,
        'displayOrder': displayOrder,
        'stageScores':
            stageScores.map((k, v) => MapEntry(k.toApiString(), v.toJson())),
      };

  MonthlyKraRow copyWith({
    String? id,
    String? name,
    String? category,
    double? weightagePercent,
    double? maxScore,
    String? target,
    String? trackingMethod,
    int? displayOrder,
    Map<ReviewStage, RowScore>? stageScores,
  }) {
    return MonthlyKraRow(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      weightagePercent: weightagePercent ?? this.weightagePercent,
      maxScore: maxScore ?? this.maxScore,
      target: target ?? this.target,
      trackingMethod: trackingMethod ?? this.trackingMethod,
      displayOrder: displayOrder ?? this.displayOrder,
      stageScores: stageScores ?? this.stageScores,
    );
  }

  /// Fresh row with [score] set for [stage] (overwrite).
  MonthlyKraRow withStageScore(ReviewStage stage, RowScore score) {
    final next = Map<ReviewStage, RowScore>.from(stageScores);
    next[stage] = score;
    return copyWith(stageScores: next);
  }
}
