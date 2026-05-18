import 'kra_template_item.dart';

/// An assignment binds an [Employee] to a set of KRA items for a specific
/// review cycle. Once `isLocked` flips true (typically after the manager
/// approves the self-rating) the items can no longer be edited; HR has
/// to create a new cycle to revise.
class KraAssignment {
  final String id;
  final String employeeId;
  final String? employeeName;
  final String cycleId;
  final String? cycleName;
  final String? templateId;
  final String? templateName;
  final List<KraTemplateItem> items;
  final bool isLocked;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const KraAssignment({
    required this.id,
    required this.employeeId,
    this.employeeName,
    required this.cycleId,
    this.cycleName,
    this.templateId,
    this.templateName,
    this.items = const [],
    this.isLocked = false,
    this.createdAt,
    this.updatedAt,
  });

  factory KraAssignment.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] ?? const []) as List<dynamic>;
    return KraAssignment(
      id: json['id'] as String,
      employeeId: (json['employeeId'] ?? '') as String,
      employeeName: json['employeeName'] as String?,
      cycleId: (json['cycleId'] ?? '') as String,
      cycleName: json['cycleName'] as String?,
      templateId: json['templateId'] as String?,
      templateName: json['templateName'] as String?,
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(KraTemplateItem.fromJson)
          .toList(),
      isLocked: (json['isLocked'] as bool?) ?? false,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeId': employeeId,
        'employeeName': employeeName,
        'cycleId': cycleId,
        'cycleName': cycleName,
        'templateId': templateId,
        'templateName': templateName,
        'items': items.map((e) => e.toJson()).toList(),
        'isLocked': isLocked,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  KraAssignment copyWith({
    String? id,
    String? employeeId,
    String? employeeName,
    String? cycleId,
    String? cycleName,
    String? templateId,
    String? templateName,
    List<KraTemplateItem>? items,
    bool? isLocked,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return KraAssignment(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      employeeName: employeeName ?? this.employeeName,
      cycleId: cycleId ?? this.cycleId,
      cycleName: cycleName ?? this.cycleName,
      templateId: templateId ?? this.templateId,
      templateName: templateName ?? this.templateName,
      items: items ?? this.items,
      isLocked: isLocked ?? this.isLocked,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }
}
