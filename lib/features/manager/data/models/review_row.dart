import '../../../../core/api/json_parse.dart';
import '../../../employee/data/models/enums.dart';
import 'monthly_score.dart';

/// One row of the manager-rate matrix — a single KRA item with its
/// per-month cells. Mirrors `ReviewRow` in the employee module but
/// adds the manager-specific bookkeeping (the manager's per-row
/// running total, an `isLocked` shortcut for the readonly view).
class ReviewRow {
  /// Stable identifier of the row's underlying KRA template item.
  /// Sent back as `assignmentItemId` on POST /scores requests.
  final String assignmentItemId;

  /// Display copy (also stored on `templateItem.name` upstream but
  /// flattened here for convenience).
  final String name;
  final String? category;
  final String? description;

  /// Decimal-on-wire — `"0.05"` is 5%. `weightagePercent` getter
  /// gives the 0–100 form used by the UI.
  final double weightage;
  final double maxScore;

  /// `SELF` rows are also rateable by the manager (manager review can
  /// override the self-rating); `MANAGER` is the standard manager-
  /// owned row; `FEED` rows are read-only on this side (Ops/Finance
  /// auto-fills them).
  final ScoreSource scoreSource;
  final int sortOrder;
  final List<MonthlyScore> monthlyScores;

  const ReviewRow({
    required this.assignmentItemId,
    required this.name,
    this.category,
    this.description,
    required this.weightage,
    required this.maxScore,
    required this.scoreSource,
    required this.sortOrder,
    this.monthlyScores = const [],
  });

  /// 0–100 form for the UI regardless of how the backend stored it
  /// (decimal fraction or percent).
  double get weightagePercent =>
      weightage <= 1.0 ? weightage * 100 : weightage;

  /// True if the row can be edited by the manager at all. `false`
  /// for `FEED` rows or once every cell is LOCKED.
  bool get isManagerEditable {
    if (scoreSource == ScoreSource.feed) return false;
    return monthlyScores.any((c) => c.isEditable);
  }

  factory ReviewRow.fromJson(Map<String, dynamic> json) {
    final cells = JsonParse.parseMapList(json['monthlyScores'])
        .map(MonthlyScore.fromJson)
        .toList();
    // The live backend exposes the row id as `templateItemId`/`id`, the
    // display copy nested under `templateItem`, the weight as `weight`,
    // and the ordering as `displayOrder`. Older spec/mock payloads use
    // the flat `assignmentItemId`/`name`/`weightage`/`sortOrder`. Read
    // the live names first, fall back to the flat ones.
    final templateItem = JsonParse.parseMap(json['templateItem']);
    return ReviewRow(
      assignmentItemId: JsonParse.parseString(json['templateItemId']) ??
          JsonParse.parseString(json['assignmentItemId']) ??
          JsonParse.parseString(json['id']) ??
          '',
      name: JsonParse.parseString(templateItem?['name']) ??
          JsonParse.parseString(json['name']) ??
          '',
      category: JsonParse.parseString(templateItem?['category']) ??
          JsonParse.parseString(json['category']),
      description: JsonParse.parseString(templateItem?['description']) ??
          JsonParse.parseString(json['description']),
      weightage: JsonParse.parseDouble(json['weight']) ??
          JsonParse.parseDouble(json['weightage']) ??
          0,
      maxScore: JsonParse.parseDouble(json['maxScore']) ?? 10,
      scoreSource: ScoreSource.fromApi(
          JsonParse.parseString(json['scoreSource']) ?? 'MANAGER'),
      sortOrder: JsonParse.parseInt(json['displayOrder']) ??
          JsonParse.parseInt(json['sortOrder']) ??
          0,
      monthlyScores: cells,
    );
  }

  Map<String, dynamic> toJson() => {
        'assignmentItemId': assignmentItemId,
        'name': name,
        'category': category,
        'description': description,
        'weightage': weightage,
        'maxScore': maxScore,
        'scoreSource': scoreSource.toApiString(),
        'sortOrder': sortOrder,
        'monthlyScores': monthlyScores.map((c) => c.toJson()).toList(),
      };

  ReviewRow copyWith({
    String? assignmentItemId,
    String? name,
    String? category,
    String? description,
    double? weightage,
    double? maxScore,
    ScoreSource? scoreSource,
    int? sortOrder,
    List<MonthlyScore>? monthlyScores,
  }) {
    return ReviewRow(
      assignmentItemId: assignmentItemId ?? this.assignmentItemId,
      name: name ?? this.name,
      category: category ?? this.category,
      description: description ?? this.description,
      weightage: weightage ?? this.weightage,
      maxScore: maxScore ?? this.maxScore,
      scoreSource: scoreSource ?? this.scoreSource,
      sortOrder: sortOrder ?? this.sortOrder,
      monthlyScores: monthlyScores ?? this.monthlyScores,
    );
  }

  /// Helper to splice a single updated cell into this row's matrix
  /// without rebuilding the whole list at the call site.
  ReviewRow withUpdatedCell(MonthlyScore updated) {
    final out = [
      for (final c in monthlyScores)
        c.monthlyScoreId == updated.monthlyScoreId ? updated : c,
    ];
    return copyWith(monthlyScores: out);
  }
}
