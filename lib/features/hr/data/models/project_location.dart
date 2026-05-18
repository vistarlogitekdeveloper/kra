/// Project location master record returned by /locations.
class ProjectLocation {
  final String id;
  final String name;
  final String? code;
  final String? city;
  final String? state;
  final String? customer;
  final bool isActive;

  const ProjectLocation({
    required this.id,
    required this.name,
    this.code,
    this.city,
    this.state,
    this.customer,
    this.isActive = true,
  });

  factory ProjectLocation.fromJson(Map<String, dynamic> json) {
    return ProjectLocation(
      id: json['id'] as String,
      name: (json['name'] ?? '') as String,
      code: json['code'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      customer: json['customer'] as String?,
      isActive: (json['isActive'] as bool?) ?? true,
    );
  }

  /// Single-line label used in dropdown items: "Name — City" or just "Name".
  String get displayLabel {
    if (city != null && city!.isNotEmpty) return '$name — $city';
    return name;
  }
}
