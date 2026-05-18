import '../../../../core/api/json_parse.dart';

/// One row of GET /employee/kra-assignments — the set of KRA items
/// the logged-in employee is being measured on for a given cycle.
///
/// `isLocked` flips true once HR locks the cycle for changes; the
/// items can no longer be edited after that point.
///
/// Items here carry the shared metadata (name, weightage, ordering).
/// Per-row scoring metadata (`maxScore`, `scoreSource`) lives on the
/// review's `rows[]` — those are derived from the template snapshot
/// taken at review-creation time, not from the assignment record.
class MyKraAssignment {
  final String id;
  final String cycleId;
  final String? templateId;
  final bool isLocked;
  final DateTime? assignedAt;
  final List<MyKraAssignmentItem> items;
  final MyKraCycleRef? cycle;
  final MyKraTemplateRef? template;
  final MyKraAssignedByRef? assignedBy;

  const MyKraAssignment({
    required this.id,
    required this.cycleId,
    this.templateId,
    this.isLocked = false,
    this.assignedAt,
    this.items = const [],
    this.cycle,
    this.template,
    this.assignedBy,
  });

  factory MyKraAssignment.fromJson(Map<String, dynamic> json) {
    final rawItems = JsonParse.parseMapList(json['items'])
        .map(MyKraAssignmentItem.fromJson)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return MyKraAssignment(
      id: JsonParse.parseString(json['id']) ?? '',
      cycleId: JsonParse.parseString(json['cycleId']) ?? '',
      templateId: JsonParse.parseString(json['templateId']),
      isLocked: JsonParse.parseBool(json['isLocked']) ?? false,
      assignedAt: JsonParse.parseDate(json['assignedAt']),
      items: rawItems,
      cycle: JsonParse.parseMap(json['cycle']) == null
          ? null
          : MyKraCycleRef.fromJson(JsonParse.parseMap(json['cycle'])!),
      template: JsonParse.parseMap(json['template']) == null
          ? null
          : MyKraTemplateRef.fromJson(JsonParse.parseMap(json['template'])!),
      assignedBy: JsonParse.parseMap(json['assignedBy']) == null
          ? null
          : MyKraAssignedByRef.fromJson(
              JsonParse.parseMap(json['assignedBy'])!),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'cycleId': cycleId,
        'templateId': templateId,
        'isLocked': isLocked,
        'assignedAt': assignedAt?.toIso8601String(),
        'items': items.map((e) => e.toJson()).toList(),
        'cycle': cycle?.toJson(),
        'template': template?.toJson(),
        'assignedBy': assignedBy?.toJson(),
      };

  MyKraAssignment copyWith({
    String? id,
    String? cycleId,
    String? templateId,
    bool? isLocked,
    DateTime? assignedAt,
    List<MyKraAssignmentItem>? items,
    MyKraCycleRef? cycle,
    MyKraTemplateRef? template,
    MyKraAssignedByRef? assignedBy,
  }) {
    return MyKraAssignment(
      id: id ?? this.id,
      cycleId: cycleId ?? this.cycleId,
      templateId: templateId ?? this.templateId,
      isLocked: isLocked ?? this.isLocked,
      assignedAt: assignedAt ?? this.assignedAt,
      items: items ?? this.items,
      cycle: cycle ?? this.cycle,
      template: template ?? this.template,
      assignedBy: assignedBy ?? this.assignedBy,
    );
  }
}

/// One KRA inside an assignment. Slim — full scoring metadata
/// (maxScore, scoreSource) is on the review row, not here.
class MyKraAssignmentItem {
  final String id;
  final String name;
  final String? description;
  final String? target;
  final String? trackingMethod;

  /// Stored on the wire as a Decimal (e.g. 0.4 or "0.4000"). See
  /// [weightagePercent] for the 0–100 form used by the UI.
  final double weightage;
  final int sortOrder;

  const MyKraAssignmentItem({
    required this.id,
    required this.name,
    this.description,
    this.target,
    this.trackingMethod,
    required this.weightage,
    required this.sortOrder,
  });

  /// Convenience getter — weightage as 0–100 regardless of how the
  /// backend stored it (decimal fraction or percent).
  double get weightagePercent =>
      weightage <= 1.0 ? weightage * 100 : weightage;

  factory MyKraAssignmentItem.fromJson(Map<String, dynamic> json) {
    return MyKraAssignmentItem(
      id: JsonParse.parseString(json['id']) ?? '',
      name: JsonParse.parseString(json['name']) ?? '',
      description: JsonParse.parseString(json['description']),
      target: JsonParse.parseString(json['target']),
      trackingMethod: JsonParse.parseString(json['trackingMethod']),
      weightage: JsonParse.parseDouble(json['weightage']) ?? 0,
      sortOrder: JsonParse.parseInt(json['sortOrder']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'target': target,
        'trackingMethod': trackingMethod,
        'weightage': weightage,
        'sortOrder': sortOrder,
      };

  MyKraAssignmentItem copyWith({
    String? id,
    String? name,
    String? description,
    String? target,
    String? trackingMethod,
    double? weightage,
    int? sortOrder,
  }) {
    return MyKraAssignmentItem(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      target: target ?? this.target,
      trackingMethod: trackingMethod ?? this.trackingMethod,
      weightage: weightage ?? this.weightage,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

class MyKraCycleRef {
  final String id;
  final String name;
  final String status;
  final String? fyLabel;
  final int? quarterNum;

  const MyKraCycleRef({
    required this.id,
    required this.name,
    required this.status,
    this.fyLabel,
    this.quarterNum,
  });

  factory MyKraCycleRef.fromJson(Map<String, dynamic> json) => MyKraCycleRef(
        id: JsonParse.parseString(json['id']) ?? '',
        name: JsonParse.parseString(json['name']) ?? '',
        status: JsonParse.parseString(json['status']) ?? '',
        fyLabel: JsonParse.parseString(json['fyLabel']),
        quarterNum: JsonParse.parseInt(json['quarterNum']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'status': status,
        'fyLabel': fyLabel,
        'quarterNum': quarterNum,
      };

  MyKraCycleRef copyWith({
    String? id,
    String? name,
    String? status,
    String? fyLabel,
    int? quarterNum,
  }) =>
      MyKraCycleRef(
        id: id ?? this.id,
        name: name ?? this.name,
        status: status ?? this.status,
        fyLabel: fyLabel ?? this.fyLabel,
        quarterNum: quarterNum ?? this.quarterNum,
      );
}

class MyKraTemplateRef {
  final String id;
  final String name;
  final String? role;

  const MyKraTemplateRef({
    required this.id,
    required this.name,
    this.role,
  });

  factory MyKraTemplateRef.fromJson(Map<String, dynamic> json) =>
      MyKraTemplateRef(
        id: JsonParse.parseString(json['id']) ?? '',
        name: JsonParse.parseString(json['name']) ?? '',
        role: JsonParse.parseString(json['role']),
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'role': role};

  MyKraTemplateRef copyWith({String? id, String? name, String? role}) =>
      MyKraTemplateRef(
        id: id ?? this.id,
        name: name ?? this.name,
        role: role ?? this.role,
      );
}

/// Tiny audit ref — who created this assignment record. Surfaced on
/// the assignment detail view ("Assigned by HR Admin · 1 Apr 2026").
class MyKraAssignedByRef {
  final String id;
  final String name;
  final String? email;

  const MyKraAssignedByRef({
    required this.id,
    required this.name,
    this.email,
  });

  factory MyKraAssignedByRef.fromJson(Map<String, dynamic> json) =>
      MyKraAssignedByRef(
        id: JsonParse.parseString(json['id']) ?? '',
        name: JsonParse.parseString(json['name']) ?? '',
        email: JsonParse.parseString(json['email']),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'email': email};

  MyKraAssignedByRef copyWith({
    String? id,
    String? name,
    String? email,
  }) =>
      MyKraAssignedByRef(
        id: id ?? this.id,
        name: name ?? this.name,
        email: email ?? this.email,
      );
}
