import 'kra_template_item.dart';

/// A reusable KRA template for a given role. Editable until cloned or
/// assigned — once assignments exist they snapshot the items, so changing
/// the template later doesn't retroactively alter past evaluations.
class KraTemplate {
  final String id;
  final String name;
  final String role;
  final String? description;
  final bool isActive;
  final List<KraTemplateItem> items;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const KraTemplate({
    required this.id,
    required this.name,
    required this.role,
    this.description,
    this.isActive = true,
    this.items = const [],
    this.createdAt,
    this.updatedAt,
  });

  /// Total weightage across all items, in percent (0–100).
  /// HR uses this to validate that a template sums to exactly 100.
  double get totalWeightage =>
      items.fold(0.0, (sum, item) => sum + item.weightagePercent);

  bool get hasValidWeightage {
    // Allow a tiny epsilon to account for double-precision drift when
    // the user edits decimal weightages (e.g. 33.33 + 33.33 + 33.34).
    final total = totalWeightage;
    return (total - 100).abs() < 0.01;
  }

  factory KraTemplate.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] ?? const []) as List<dynamic>;
    final items = rawItems
        .whereType<Map<String, dynamic>>()
        .map(KraTemplateItem.fromJson)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return KraTemplate(
      id: json['id'] as String,
      name: (json['name'] ?? '') as String,
      role: (json['role'] ?? '') as String,
      description: json['description'] as String?,
      isActive: (json['isActive'] as bool?) ?? true,
      items: items,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role,
        'description': description,
        'isActive': isActive,
        'items': items.map((e) => e.toJson()).toList(),
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  KraTemplate copyWith({
    String? id,
    String? name,
    String? role,
    String? description,
    bool? isActive,
    List<KraTemplateItem>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return KraTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      items: items ?? this.items,
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
