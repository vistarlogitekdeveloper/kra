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
    required this.weightage,
    required this.sortOrder,
  });

  /// Convenience getter — returns weightage as 0–100 regardless of how
  /// the server stored it.
  double get weightagePercent => weightage <= 1.0 ? weightage * 100 : weightage;

  factory KraTemplateItem.empty({int sortOrder = 0}) => KraTemplateItem(
        name: '',
        weightage: 0,
        sortOrder: sortOrder,
      );

  factory KraTemplateItem.fromJson(Map<String, dynamic> json) {
    // Backend stores weightage as Prisma Decimal, which serialises to a
    // JSON string ("0.05") — not a number. Tolerate both shapes.
    final raw = _parseDouble(json['weightage']) ?? 0;
    // Normalise to percentage (0–100).
    final pct = raw <= 1.0 ? raw * 100 : raw;
    return KraTemplateItem(
      id: json['id'] as String?,
      name: (json['name'] ?? '') as String,
      description: json['description'] as String?,
      target: json['target'] as String?,
      trackingMethod: json['trackingMethod'] as String?,
      weightage: pct,
      sortOrder: _parseInt(json['sortOrder']) ?? 0,
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Wire format sends weightage as a fraction (0–1) — that is the
  /// canonical form the backend persists.
  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'name': name,
        'description': description,
        'target': target,
        'trackingMethod': trackingMethod,
        'weightage': weightagePercent / 100,
        'sortOrder': sortOrder,
      };

  KraTemplateItem copyWith({
    String? id,
    String? name,
    String? description,
    String? target,
    String? trackingMethod,
    double? weightage,
    int? sortOrder,
  }) {
    return KraTemplateItem(
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
