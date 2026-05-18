import '../../../../core/api/json_parse.dart';
import 'enums.dart';

/// A single Review record — one per (employee, cycle).
///
/// The data model is a matrix: each [ReviewRow] represents one KRA,
/// and inside it [ReviewRow.monthlyScores] holds one cell per month
/// in the cycle. The self-rate form addresses cells by their
/// [MonthlyScore.id] (`monthlyScoreId` in the request body).
///
/// Both the list endpoint (GET /employee/reviews) and the detail
/// endpoint (GET /employee/reviews/:id) return this exact shape, so
/// [MyReviewSummary] is just a typedef for [MyReview] — see
/// `my_review_summary.dart`.
class MyReview {
  final String id;
  final String reviewCycleId;
  final String employeeId;
  final String? managerId;
  final String? templateId;
  final String? projectLocationId;
  final ReviewState state;

  /// Snapshot of the per-month eligible incentive at review-creation
  /// time. Decimal-on-wire — comes through as a String like "5000.00".
  final double? monthlyIncentiveAmount;
  final double? quarterlyFixedIncentive;
  final double? finalAvgSelfPct;
  final double? finalAvgManagerPct;
  final double? payableIncentive;

  /// Optional remark applied at finalisation time. `remarkCode` is a
  /// stable token (e.g. `EXCEEDS_EXPECTATIONS`) — `remarkText` is the
  /// human label and may be null on legacy rows.
  final String? remarkCode;
  final String? remarkText;

  final ReviewManagerRef? manager;
  final ReviewTemplateRef? template;
  final ReviewProjectLocationRef? projectLocation;
  final ReviewCycleRef? reviewCycle;
  final List<ReviewRow> rows;

  /// Optional structured remark — older payloads return this as a
  /// nested object alongside the flat `remarkCode` / `remarkText`
  /// fields. Carrying both keeps clients tolerant of either shape.
  final Map<String, dynamic>? remark;

  const MyReview({
    required this.id,
    required this.reviewCycleId,
    required this.employeeId,
    this.managerId,
    this.templateId,
    this.projectLocationId,
    required this.state,
    this.monthlyIncentiveAmount,
    this.quarterlyFixedIncentive,
    this.finalAvgSelfPct,
    this.finalAvgManagerPct,
    this.payableIncentive,
    this.remarkCode,
    this.remarkText,
    this.manager,
    this.template,
    this.projectLocation,
    this.reviewCycle,
    this.rows = const [],
    this.remark,
  });

  factory MyReview.fromJson(Map<String, dynamic> json) {
    return MyReview(
      id: JsonParse.parseString(json['id']) ?? '',
      reviewCycleId: JsonParse.parseString(json['reviewCycleId']) ?? '',
      employeeId: JsonParse.parseString(json['employeeId']) ?? '',
      managerId: JsonParse.parseString(json['managerId']),
      templateId: JsonParse.parseString(json['templateId']),
      projectLocationId: JsonParse.parseString(json['projectLocationId']),
      state: ReviewState.fromApi(
          JsonParse.parseString(json['state']) ?? 'DRAFT'),
      monthlyIncentiveAmount:
          JsonParse.parseDouble(json['monthlyIncentiveAmount']),
      quarterlyFixedIncentive:
          JsonParse.parseDouble(json['quarterlyFixedIncentive']),
      finalAvgSelfPct: JsonParse.parseDouble(json['finalAvgSelfPct']),
      finalAvgManagerPct: JsonParse.parseDouble(json['finalAvgManagerPct']),
      payableIncentive: JsonParse.parseDouble(json['payableIncentive']),
      remarkCode: JsonParse.parseString(json['remarkCode']),
      remarkText: JsonParse.parseString(json['remarkText']),
      manager: JsonParse.parseMap(json['manager']) == null
          ? null
          : ReviewManagerRef.fromJson(JsonParse.parseMap(json['manager'])!),
      template: JsonParse.parseMap(json['template']) == null
          ? null
          : ReviewTemplateRef.fromJson(JsonParse.parseMap(json['template'])!),
      projectLocation: JsonParse.parseMap(json['projectLocation']) == null
          ? null
          : ReviewProjectLocationRef.fromJson(
              JsonParse.parseMap(json['projectLocation'])!),
      reviewCycle: JsonParse.parseMap(json['reviewCycle']) == null
          ? null
          : ReviewCycleRef.fromJson(
              JsonParse.parseMap(json['reviewCycle'])!),
      rows: JsonParse.parseMapList(json['rows'])
          .map(ReviewRow.fromJson)
          .toList()
        ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder)),
      remark: JsonParse.parseMap(json['remark']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'reviewCycleId': reviewCycleId,
        'employeeId': employeeId,
        'managerId': managerId,
        'templateId': templateId,
        'projectLocationId': projectLocationId,
        'state': state.toApiString(),
        'monthlyIncentiveAmount': monthlyIncentiveAmount,
        'quarterlyFixedIncentive': quarterlyFixedIncentive,
        'finalAvgSelfPct': finalAvgSelfPct,
        'finalAvgManagerPct': finalAvgManagerPct,
        'payableIncentive': payableIncentive,
        'remarkCode': remarkCode,
        'remarkText': remarkText,
        'manager': manager?.toJson(),
        'template': template?.toJson(),
        'projectLocation': projectLocation?.toJson(),
        'reviewCycle': reviewCycle?.toJson(),
        'rows': rows.map((e) => e.toJson()).toList(),
        'remark': remark,
      };

  MyReview copyWith({
    String? id,
    String? reviewCycleId,
    String? employeeId,
    String? managerId,
    String? templateId,
    String? projectLocationId,
    ReviewState? state,
    double? monthlyIncentiveAmount,
    double? quarterlyFixedIncentive,
    double? finalAvgSelfPct,
    double? finalAvgManagerPct,
    double? payableIncentive,
    String? remarkCode,
    String? remarkText,
    ReviewManagerRef? manager,
    ReviewTemplateRef? template,
    ReviewProjectLocationRef? projectLocation,
    ReviewCycleRef? reviewCycle,
    List<ReviewRow>? rows,
    Map<String, dynamic>? remark,
  }) {
    return MyReview(
      id: id ?? this.id,
      reviewCycleId: reviewCycleId ?? this.reviewCycleId,
      employeeId: employeeId ?? this.employeeId,
      managerId: managerId ?? this.managerId,
      templateId: templateId ?? this.templateId,
      projectLocationId: projectLocationId ?? this.projectLocationId,
      state: state ?? this.state,
      monthlyIncentiveAmount:
          monthlyIncentiveAmount ?? this.monthlyIncentiveAmount,
      quarterlyFixedIncentive:
          quarterlyFixedIncentive ?? this.quarterlyFixedIncentive,
      finalAvgSelfPct: finalAvgSelfPct ?? this.finalAvgSelfPct,
      finalAvgManagerPct: finalAvgManagerPct ?? this.finalAvgManagerPct,
      payableIncentive: payableIncentive ?? this.payableIncentive,
      remarkCode: remarkCode ?? this.remarkCode,
      remarkText: remarkText ?? this.remarkText,
      manager: manager ?? this.manager,
      template: template ?? this.template,
      projectLocation: projectLocation ?? this.projectLocation,
      reviewCycle: reviewCycle ?? this.reviewCycle,
      rows: rows ?? this.rows,
      remark: remark ?? this.remark,
    );
  }
}

/// One KRA inside a review (a "review row"). Carries the snapshot of
/// the row's scoring metadata (weight, maxScore, scoreSource) plus
/// the cell array — one [MonthlyScore] per month in the cycle.
class ReviewRow {
  final String id;
  final double weight;
  final double maxScore;
  final ScoreSource scoreSource;
  final int displayOrder;

  /// Embedded reference to the underlying KRA template item — name,
  /// description, category. Optional because the include chain may
  /// drop it on slimmed-down endpoints in the future.
  final ReviewTemplateItemRef? templateItem;

  final List<MonthlyScore> monthlyScores;

  const ReviewRow({
    required this.id,
    required this.weight,
    required this.maxScore,
    required this.scoreSource,
    required this.displayOrder,
    this.templateItem,
    this.monthlyScores = const [],
  });

  /// Convenience getter — weightage as 0–100 regardless of how the
  /// backend stored it (decimal fraction or percent).
  double get weightPercent => weight <= 1.0 ? weight * 100 : weight;

  factory ReviewRow.fromJson(Map<String, dynamic> json) {
    return ReviewRow(
      id: JsonParse.parseString(json['id']) ?? '',
      weight: JsonParse.parseDouble(json['weight']) ?? 0,
      maxScore: JsonParse.parseDouble(json['maxScore']) ?? 10,
      scoreSource: ScoreSource.fromApi(
          JsonParse.parseString(json['scoreSource']) ?? 'MANAGER'),
      displayOrder: JsonParse.parseInt(json['displayOrder']) ?? 0,
      templateItem: JsonParse.parseMap(json['templateItem']) == null
          ? null
          : ReviewTemplateItemRef.fromJson(
              JsonParse.parseMap(json['templateItem'])!),
      monthlyScores: JsonParse.parseMapList(json['monthlyScores'])
          .map(MonthlyScore.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'weight': weight,
        'maxScore': maxScore,
        'scoreSource': scoreSource.toApiString(),
        'displayOrder': displayOrder,
        'templateItem': templateItem?.toJson(),
        'monthlyScores': monthlyScores.map((e) => e.toJson()).toList(),
      };

  ReviewRow copyWith({
    String? id,
    double? weight,
    double? maxScore,
    ScoreSource? scoreSource,
    int? displayOrder,
    ReviewTemplateItemRef? templateItem,
    List<MonthlyScore>? monthlyScores,
  }) {
    return ReviewRow(
      id: id ?? this.id,
      weight: weight ?? this.weight,
      maxScore: maxScore ?? this.maxScore,
      scoreSource: scoreSource ?? this.scoreSource,
      displayOrder: displayOrder ?? this.displayOrder,
      templateItem: templateItem ?? this.templateItem,
      monthlyScores: monthlyScores ?? this.monthlyScores,
    );
  }
}

class ReviewTemplateItemRef {
  final String name;
  final String? description;
  final String? category;

  const ReviewTemplateItemRef({
    required this.name,
    this.description,
    this.category,
  });

  factory ReviewTemplateItemRef.fromJson(Map<String, dynamic> json) =>
      ReviewTemplateItemRef(
        name: JsonParse.parseString(json['name']) ?? '',
        description: JsonParse.parseString(json['description']),
        category: JsonParse.parseString(json['category']),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'category': category,
      };

  ReviewTemplateItemRef copyWith({
    String? name,
    String? description,
    String? category,
  }) =>
      ReviewTemplateItemRef(
        name: name ?? this.name,
        description: description ?? this.description,
        category: category ?? this.category,
      );
}

/// One cell in the review matrix — (row × month). The self-rate POST
/// targets [id] via its `monthlyScoreId` field.
class MonthlyScore {
  final String id;
  final String monthId;

  /// Self-rating value the employee has submitted. `null` until they
  /// submit their first score for this cell.
  final double? selfRating;

  /// Manager's rating. `null` until the manager scores. Bounded by
  /// `row.maxScore` — same scale as `selfRating`.
  final double? managerRating;

  /// Score from a system feed (attendance, sales etc.). Replaces
  /// the manager rating when the row's [ScoreSource] is FEED.
  final double? feedRating;

  /// Excludes the cell from weighted-average math when true.
  /// HR uses this for one-off skips (e.g. employee on extended leave
  /// for the month).
  final bool isNotApplicable;

  final String? selfRemark;
  final String? managerRemark;
  final DateTime? selfSubmittedAt;
  final DateTime? managerSubmittedAt;

  /// Embedded month reference. Carrying it on each cell saves the
  /// caller a lookup against `reviewCycle.months[]` for every cell.
  final ReviewMonthRef? month;

  const MonthlyScore({
    required this.id,
    required this.monthId,
    this.selfRating,
    this.managerRating,
    this.feedRating,
    this.isNotApplicable = false,
    this.selfRemark,
    this.managerRemark,
    this.selfSubmittedAt,
    this.managerSubmittedAt,
    this.month,
  });

  /// True if the employee has supplied a score (or marked N/A) for
  /// this cell. Drives the self-rate form's "fill-all-cells" gate.
  bool get isSelfRated => isNotApplicable || selfRating != null;

  factory MonthlyScore.fromJson(Map<String, dynamic> json) {
    return MonthlyScore(
      id: JsonParse.parseString(json['id']) ?? '',
      monthId: JsonParse.parseString(json['monthId']) ?? '',
      selfRating: JsonParse.parseDouble(json['selfRating']),
      managerRating: JsonParse.parseDouble(json['managerRating']),
      feedRating: JsonParse.parseDouble(json['feedRating']),
      isNotApplicable: JsonParse.parseBool(json['isNotApplicable']) ?? false,
      selfRemark: JsonParse.parseString(json['selfRemark']),
      managerRemark: JsonParse.parseString(json['managerRemark']),
      selfSubmittedAt: JsonParse.parseDate(json['selfSubmittedAt']),
      managerSubmittedAt: JsonParse.parseDate(json['managerSubmittedAt']),
      month: JsonParse.parseMap(json['month']) == null
          ? null
          : ReviewMonthRef.fromJson(JsonParse.parseMap(json['month'])!),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'monthId': monthId,
        'selfRating': selfRating,
        'managerRating': managerRating,
        'feedRating': feedRating,
        'isNotApplicable': isNotApplicable,
        'selfRemark': selfRemark,
        'managerRemark': managerRemark,
        'selfSubmittedAt': selfSubmittedAt?.toIso8601String(),
        'managerSubmittedAt': managerSubmittedAt?.toIso8601String(),
        'month': month?.toJson(),
      };

  MonthlyScore copyWith({
    String? id,
    String? monthId,
    Object? selfRating = _sentinel,
    Object? managerRating = _sentinel,
    Object? feedRating = _sentinel,
    bool? isNotApplicable,
    Object? selfRemark = _sentinel,
    Object? managerRemark = _sentinel,
    DateTime? selfSubmittedAt,
    DateTime? managerSubmittedAt,
    ReviewMonthRef? month,
  }) {
    return MonthlyScore(
      id: id ?? this.id,
      monthId: monthId ?? this.monthId,
      selfRating: identical(selfRating, _sentinel)
          ? this.selfRating
          : selfRating as double?,
      managerRating: identical(managerRating, _sentinel)
          ? this.managerRating
          : managerRating as double?,
      feedRating: identical(feedRating, _sentinel)
          ? this.feedRating
          : feedRating as double?,
      isNotApplicable: isNotApplicable ?? this.isNotApplicable,
      selfRemark: identical(selfRemark, _sentinel)
          ? this.selfRemark
          : selfRemark as String?,
      managerRemark: identical(managerRemark, _sentinel)
          ? this.managerRemark
          : managerRemark as String?,
      selfSubmittedAt: selfSubmittedAt ?? this.selfSubmittedAt,
      managerSubmittedAt: managerSubmittedAt ?? this.managerSubmittedAt,
      month: month ?? this.month,
    );
  }

  static const _sentinel = Object();
}

/// Lightweight month reference used both at the cycle level
/// (`reviewCycle.months[]`) and per-cell (`monthlyScores[].month`).
class ReviewMonthRef {
  final String id;
  final String monthLabel;
  final DateTime? monthDate;
  final ReviewMonthStatus status;

  const ReviewMonthRef({
    required this.id,
    required this.monthLabel,
    this.monthDate,
    required this.status,
  });

  factory ReviewMonthRef.fromJson(Map<String, dynamic> json) =>
      ReviewMonthRef(
        id: JsonParse.parseString(json['id']) ?? '',
        monthLabel: JsonParse.parseString(json['monthLabel']) ?? '',
        monthDate: JsonParse.parseDate(json['monthDate']),
        status: ReviewMonthStatus.fromApi(
            JsonParse.parseString(json['status']) ?? 'OPEN'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'monthLabel': monthLabel,
        'monthDate': monthDate?.toIso8601String(),
        'status': status.toApiString(),
      };

  ReviewMonthRef copyWith({
    String? id,
    String? monthLabel,
    DateTime? monthDate,
    ReviewMonthStatus? status,
  }) =>
      ReviewMonthRef(
        id: id ?? this.id,
        monthLabel: monthLabel ?? this.monthLabel,
        monthDate: monthDate ?? this.monthDate,
        status: status ?? this.status,
      );
}

class ReviewManagerRef {
  final String id;
  final String name;
  final String? email;
  final String? employeeCode;

  const ReviewManagerRef({
    required this.id,
    required this.name,
    this.email,
    this.employeeCode,
  });

  factory ReviewManagerRef.fromJson(Map<String, dynamic> json) =>
      ReviewManagerRef(
        id: JsonParse.parseString(json['id']) ?? '',
        name: JsonParse.parseString(json['name']) ?? '',
        email: JsonParse.parseString(json['email']),
        employeeCode: JsonParse.parseString(json['employeeCode']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'employeeCode': employeeCode,
      };

  ReviewManagerRef copyWith({
    String? id,
    String? name,
    String? email,
    String? employeeCode,
  }) =>
      ReviewManagerRef(
        id: id ?? this.id,
        name: name ?? this.name,
        email: email ?? this.email,
        employeeCode: employeeCode ?? this.employeeCode,
      );
}

class ReviewTemplateRef {
  final String id;
  final String name;

  const ReviewTemplateRef({required this.id, required this.name});

  factory ReviewTemplateRef.fromJson(Map<String, dynamic> json) =>
      ReviewTemplateRef(
        id: JsonParse.parseString(json['id']) ?? '',
        name: JsonParse.parseString(json['name']) ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  ReviewTemplateRef copyWith({String? id, String? name}) =>
      ReviewTemplateRef(id: id ?? this.id, name: name ?? this.name);
}

class ReviewProjectLocationRef {
  final String id;
  final String name;

  const ReviewProjectLocationRef({required this.id, required this.name});

  factory ReviewProjectLocationRef.fromJson(Map<String, dynamic> json) =>
      ReviewProjectLocationRef(
        id: JsonParse.parseString(json['id']) ?? '',
        name: JsonParse.parseString(json['name']) ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  ReviewProjectLocationRef copyWith({String? id, String? name}) =>
      ReviewProjectLocationRef(id: id ?? this.id, name: name ?? this.name);
}

class ReviewCycleRef {
  final String id;
  final String name;
  final String? fyLabel;
  final String status;
  final DateTime? selfRatingDeadline;
  final DateTime? managerReviewDeadline;
  final List<ReviewMonthRef> months;

  const ReviewCycleRef({
    required this.id,
    required this.name,
    this.fyLabel,
    required this.status,
    this.selfRatingDeadline,
    this.managerReviewDeadline,
    this.months = const [],
  });

  factory ReviewCycleRef.fromJson(Map<String, dynamic> json) =>
      ReviewCycleRef(
        id: JsonParse.parseString(json['id']) ?? '',
        name: JsonParse.parseString(json['name']) ?? '',
        fyLabel: JsonParse.parseString(json['fyLabel']),
        status: JsonParse.parseString(json['status']) ?? '',
        selfRatingDeadline:
            JsonParse.parseDate(json['selfRatingDeadline']),
        managerReviewDeadline:
            JsonParse.parseDate(json['managerReviewDeadline']),
        months: JsonParse.parseMapList(json['months'])
            .map(ReviewMonthRef.fromJson)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'fyLabel': fyLabel,
        'status': status,
        'selfRatingDeadline': selfRatingDeadline?.toIso8601String(),
        'managerReviewDeadline':
            managerReviewDeadline?.toIso8601String(),
        'months': months.map((e) => e.toJson()).toList(),
      };

  ReviewCycleRef copyWith({
    String? id,
    String? name,
    String? fyLabel,
    String? status,
    DateTime? selfRatingDeadline,
    DateTime? managerReviewDeadline,
    List<ReviewMonthRef>? months,
  }) =>
      ReviewCycleRef(
        id: id ?? this.id,
        name: name ?? this.name,
        fyLabel: fyLabel ?? this.fyLabel,
        status: status ?? this.status,
        selfRatingDeadline: selfRatingDeadline ?? this.selfRatingDeadline,
        managerReviewDeadline:
            managerReviewDeadline ?? this.managerReviewDeadline,
        months: months ?? this.months,
      );
}

/// Backwards-compatible alias for code that was written against the
/// "detail vs. summary" split. Both endpoints return the same shape.
typedef MyReviewDetail = MyReview;
