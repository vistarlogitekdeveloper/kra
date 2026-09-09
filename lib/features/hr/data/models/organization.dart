import '../../../../core/api/json_parse.dart';
import '../../../../core/enums/review_flow.dart';

/// One tenant.
///
/// Every KRA entity is organisation-scoped — employees, locations, templates,
/// review cycles and assignments all carry an `organizationId`, and the backend
/// signs the caller's into the JWT at login. So an organisation is not a
/// cosmetic grouping: it is the boundary that decides what a signed-in user can
/// see at all.
///
/// Only a super admin may list or change these ([UserRole.superAdmin]).
class Organization {
  final String id;

  /// Display name, e.g. "Vistar Logitek North".
  final String name;

  /// URL-safe unique key, e.g. `vistar-logitek-north`. Unique across the
  /// install, which is why a duplicate comes back as a 409 rather than a
  /// field error.
  final String slug;

  final String? logoUrl;

  /// How many employees this tenant holds.
  ///
  /// Null when the payload omits it (the detail endpoint may). Null and 0 mean
  /// different things — "not counted" versus "empty" — so this stays nullable
  /// rather than defaulting to zero, which would render an empty tenant and an
  /// uncounted one identically.
  final int? employeeCount;

  /// Which review pipeline this tenant runs.
  ///
  /// Defaults to [ReviewFlow.standard] when the payload omits it — every
  /// organisation predates this field, and a server without the column simply
  /// does not send it. See [ReviewFlow.fromApi] for why the fallback must be
  /// the original pipeline.
  final ReviewFlow reviewFlow;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Organization({
    required this.id,
    required this.name,
    required this.slug,
    this.logoUrl,
    this.employeeCount,
    this.reviewFlow = ReviewFlow.standard,
    this.createdAt,
    this.updatedAt,
  });

  factory Organization.fromJson(Map<String, dynamic> json) => Organization(
        id: JsonParse.parseString(json['id']) ?? '',
        name: JsonParse.parseString(json['name']) ?? '',
        slug: JsonParse.parseString(json['slug']) ?? '',
        logoUrl: JsonParse.parseString(json['logoUrl']),
        // parseInt tolerates the string form some backends emit for counts.
        employeeCount: JsonParse.parseInt(json['employeeCount']),
        reviewFlow:
            ReviewFlow.fromApi(JsonParse.parseString(json['reviewFlow'])),
        createdAt: JsonParse.parseDate(json['createdAt']),
        updatedAt: JsonParse.parseDate(json['updatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
        'logoUrl': logoUrl,
        'employeeCount': employeeCount,
        'reviewFlow': reviewFlow.toApiString(),
      };

  Organization copyWith({
    String? id,
    String? name,
    String? slug,
    String? logoUrl,
    int? employeeCount,
    ReviewFlow? reviewFlow,
  }) =>
      Organization(
        id: id ?? this.id,
        name: name ?? this.name,
        slug: slug ?? this.slug,
        logoUrl: logoUrl ?? this.logoUrl,
        employeeCount: employeeCount ?? this.employeeCount,
        reviewFlow: reviewFlow ?? this.reviewFlow,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is Organization && other.id == id && other.slug == slug;

  @override
  int get hashCode => Object.hash(id, slug);
}
