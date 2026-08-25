import '../../../../core/api/json_parse.dart';
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

  /// Item count reported by the list endpoint via `_count.items`. The
  /// list payload omits the `items` array, so this is the only source
  /// of the count there. `0` when absent (e.g. on the detail payload,
  /// where [items] is populated instead).
  final int itemCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const KraTemplate({
    required this.id,
    required this.name,
    required this.role,
    this.description,
    this.isActive = true,
    this.items = const [],
    this.itemCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  /// Number of items to display. Prefers the loaded [items] (accurate
  /// once a detail/hydrated payload is in hand) and falls back to the
  /// list endpoint's [itemCount] when items haven't been fetched.
  int get displayItemCount => items.isNotEmpty ? items.length : itemCount;

  /// True once the per-item weightages are available to total up. The
  /// list endpoint doesn't return items, so the weightage badge is only
  /// meaningful after hydration.
  bool get hasWeightageData => items.isNotEmpty;

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
    // The list endpoint reports the item count under `_count.items`
    // (the `items` array itself is only on the detail payload).
    final count = json['_count'];
    final parsedItemCount = (count is Map && count['items'] is num)
        ? (count['items'] as num).toInt()
        : items.length;
    return KraTemplate(
      id: json['id'] as String,
      name: (json['name'] ?? '') as String,
      role: (json['role'] ?? '') as String,
      description: json['description'] as String?,
      isActive: (json['isActive'] as bool?) ?? true,
      items: items,
      itemCount: parsedItemCount,
      createdAt: JsonParse.parseDate(json['createdAt']),
      updatedAt: JsonParse.parseDate(json['updatedAt']),
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
    int? itemCount,
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
      itemCount: itemCount ?? this.itemCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Longest template name the API accepts (`z.string().min(1).max(200)`).
const int kKraTemplateNameMaxLength = 200;

/// A name for a copy of [sourceName] that none of [existingNames] already uses.
///
/// The clone endpoint REQUIRES a name and rejects a duplicate with 409, so a
/// fixed "(Copy)" suffix would fail the second time anyone duplicates the same
/// template. Numbers the suffix instead: "(Copy)", "(Copy 2)", "(Copy 3)"…
///
/// Compared case-insensitively and trimmed, which is STRICTER than the server
/// (its uniqueness check is an exact match). Erring that way can only ever
/// suggest a more distinct name — never a colliding one. The suggestion is
/// still only a suggestion: the visible list may be filtered or paginated, so
/// the caller must handle a 409 rather than assume this cannot collide.
String suggestedCloneName(String sourceName, Iterable<String> existingNames) {
  final taken = {
    for (final n in existingNames) n.trim().toLowerCase(),
  };
  final base = sourceName.trim().isEmpty ? 'Template' : sourceName.trim();

  String withSuffix(String suffix) {
    // Trim the BASE, not the suffix, when the cap bites — a name ending in a
    // half-written "(Cop" reads as corruption, and the suffix is what makes
    // the name unique.
    final room = kKraTemplateNameMaxLength - suffix.length;
    final head =
        base.length <= room ? base : base.substring(0, room).trimRight();
    return '$head$suffix';
  }

  for (var n = 1;; n++) {
    final candidate = withSuffix(n == 1 ? ' (Copy)' : ' (Copy $n)');
    if (!taken.contains(candidate.toLowerCase())) return candidate;
  }
}
