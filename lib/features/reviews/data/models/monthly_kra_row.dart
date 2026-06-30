import '../../../../core/api/json_parse.dart';
import 'review_stage.dart';

/// A score recorded by one stage against one KRA row.
class RowScore {
  final double value;
  final String? remark;

  const RowScore({required this.value, this.remark});

  factory RowScore.fromJson(Map<String, dynamic> json) => RowScore(
        value: JsonParse.parseDouble(json['value']) ?? 0,
        remark: JsonParse.parseString(json['remark']),
      );

  Map<String, dynamic> toJson() => {'value': value, 'remark': remark};

  RowScore copyWith({double? value, String? remark}) =>
      RowScore(value: value ?? this.value, remark: remark ?? this.remark);
}

/// One KRA item inside a [MonthlyReview]. Carries the immutable item
/// metadata plus the score each rating stage gave it.
///
/// `weightagePercent` is canonically 0–100 (matches the convention settled
/// in `kra_template_item.dart`). `stageScores` only holds entries for the
/// rating stages (self / accountHr / reportingManager).
class MonthlyKraRow {
  final String id;
  final String name;
  final String? category;
  final String? description;
  final String? target;
  final String? trackingMethod;
  final double weightagePercent;
  final double maxScore;
  final int displayOrder;

  /// Scores keyed by the stage that produced them. Absent ⇒ not yet rated.
  final Map<ReviewStage, RowScore> stageScores;

  const MonthlyKraRow({
    required this.id,
    required this.name,
    this.category,
    this.description,
    this.target,
    this.trackingMethod,
    required this.weightagePercent,
    this.maxScore = 10,
    this.displayOrder = 0,
    this.stageScores = const {},
  });

  RowScore? scoreFor(ReviewStage stage) => stageScores[stage];

  /// Returns a copy with [score] set (or cleared when null) for [stage].
  MonthlyKraRow withStageScore(ReviewStage stage, RowScore? score) {
    final next = Map<ReviewStage, RowScore>.from(stageScores);
    if (score == null) {
      next.remove(stage);
    } else {
      next[stage] = score;
    }
    return copyWith(stageScores: next);
  }

  factory MonthlyKraRow.fromJson(Map<String, dynamic> json) {
    final scores = <ReviewStage, RowScore>{};
    final raw = JsonParse.parseMap(json['stageScores']);
    if (raw != null) {
      raw.forEach((k, v) {
        final map = JsonParse.parseMap(v);
        if (map != null) {
          scores[ReviewStage.fromApi(k)] = RowScore.fromJson(map);
        }
      });
    }
    return MonthlyKraRow(
      id: JsonParse.parseString(json['id']) ?? '',
      name: JsonParse.parseString(json['name']) ?? '',
      category: JsonParse.parseString(json['category']),
      description: JsonParse.parseString(json['description']),
      target: JsonParse.parseString(json['target']),
      trackingMethod: JsonParse.parseString(json['trackingMethod']),
      weightagePercent: JsonParse.parseDouble(json['weightagePercent']) ?? 0,
      maxScore: JsonParse.parseDouble(json['maxScore']) ?? 10,
      displayOrder: JsonParse.parseInt(json['displayOrder']) ?? 0,
      stageScores: scores,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'description': description,
        'target': target,
        'trackingMethod': trackingMethod,
        'weightagePercent': weightagePercent,
        'maxScore': maxScore,
        'displayOrder': displayOrder,
        'stageScores': stageScores.map(
          (k, v) => MapEntry(k.toApiString(), v.toJson()),
        ),
      };

  MonthlyKraRow copyWith({
    String? id,
    String? name,
    String? category,
    String? description,
    String? target,
    String? trackingMethod,
    double? weightagePercent,
    double? maxScore,
    int? displayOrder,
    Map<ReviewStage, RowScore>? stageScores,
  }) {
    return MonthlyKraRow(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      description: description ?? this.description,
      target: target ?? this.target,
      trackingMethod: trackingMethod ?? this.trackingMethod,
      weightagePercent: weightagePercent ?? this.weightagePercent,
      maxScore: maxScore ?? this.maxScore,
      displayOrder: displayOrder ?? this.displayOrder,
      stageScores: stageScores ?? this.stageScores,
    );
  }
}
