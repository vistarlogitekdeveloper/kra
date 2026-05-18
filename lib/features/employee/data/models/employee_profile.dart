import '../../../../core/api/json_parse.dart';

/// Rich profile shape returned by GET /employee/profile.
///
/// Distinct from the HR module's [Employee] model on purpose — this
/// endpoint carries fields HR doesn't expose (`position`, `phone`,
/// `authMethod`, `monthlyIncentiveAmount`) and uses richer nested
/// shapes for `manager`, `projectLocation`, and `defaultTemplate`.
///
/// The PATCH /employee/profile endpoint accepts only `phone` and
/// `photoUrl` from the employee themselves; everything else is HR-only.
class EmployeeProfile {
  final String id;
  final String employeeCode;
  final String name;
  final String email;
  final String? position;
  final String? grade;
  final String? department;
  final String? phone;

  /// Wire-format role string (UPPER_SNAKE_CASE) — the UI maps this
  /// to a humanised pill at render time.
  final String role;

  /// Authentication method the user signs in with (`PASSWORD` / `SSO`).
  /// Drives the "change password" affordance — if `SSO`, password
  /// changes happen at the IdP, not here.
  final String? authMethod;

  /// Per-employee override of the bonus slab. Falls through to slab
  /// → org default on the backend (see incentive-summary spec).
  final double? monthlyIncentiveAmount;

  final DateTime? joinedDate;
  final DateTime? exitDate;
  final bool isActive;

  final ProfileManagerRef? manager;
  final ProfileProjectLocation? projectLocation;
  final ProfileTemplateRef? defaultTemplate;

  const EmployeeProfile({
    required this.id,
    required this.employeeCode,
    required this.name,
    required this.email,
    this.position,
    this.grade,
    this.department,
    this.phone,
    required this.role,
    this.authMethod,
    this.monthlyIncentiveAmount,
    this.joinedDate,
    this.exitDate,
    this.isActive = true,
    this.manager,
    this.projectLocation,
    this.defaultTemplate,
  });

  factory EmployeeProfile.fromJson(Map<String, dynamic> json) {
    return EmployeeProfile(
      id: JsonParse.parseString(json['id']) ?? '',
      employeeCode: JsonParse.parseString(json['employeeCode']) ?? '',
      name: JsonParse.parseString(json['name']) ?? '',
      email: JsonParse.parseString(json['email']) ?? '',
      position: JsonParse.parseString(json['position']),
      grade: JsonParse.parseString(json['grade']),
      department: JsonParse.parseString(json['department']),
      phone: JsonParse.parseString(json['phone']),
      role: JsonParse.parseString(json['role']) ?? 'EMPLOYEE',
      authMethod: JsonParse.parseString(json['authMethod']),
      monthlyIncentiveAmount:
          JsonParse.parseDouble(json['monthlyIncentiveAmount']),
      joinedDate: JsonParse.parseDate(json['joinedDate']),
      exitDate: JsonParse.parseDate(json['exitDate']),
      isActive: JsonParse.parseBool(json['isActive']) ?? true,
      manager: JsonParse.parseMap(json['manager']) == null
          ? null
          : ProfileManagerRef.fromJson(JsonParse.parseMap(json['manager'])!),
      projectLocation: JsonParse.parseMap(json['projectLocation']) == null
          ? null
          : ProfileProjectLocation.fromJson(
              JsonParse.parseMap(json['projectLocation'])!),
      defaultTemplate: JsonParse.parseMap(json['defaultTemplate']) == null
          ? null
          : ProfileTemplateRef.fromJson(
              JsonParse.parseMap(json['defaultTemplate'])!),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeCode': employeeCode,
        'name': name,
        'email': email,
        'position': position,
        'grade': grade,
        'department': department,
        'phone': phone,
        'role': role,
        'authMethod': authMethod,
        'monthlyIncentiveAmount': monthlyIncentiveAmount,
        'joinedDate': joinedDate?.toIso8601String(),
        'exitDate': exitDate?.toIso8601String(),
        'isActive': isActive,
        'manager': manager?.toJson(),
        'projectLocation': projectLocation?.toJson(),
        'defaultTemplate': defaultTemplate?.toJson(),
      };

  EmployeeProfile copyWith({
    String? id,
    String? employeeCode,
    String? name,
    String? email,
    String? position,
    String? grade,
    String? department,
    String? phone,
    String? role,
    String? authMethod,
    double? monthlyIncentiveAmount,
    DateTime? joinedDate,
    DateTime? exitDate,
    bool? isActive,
    ProfileManagerRef? manager,
    ProfileProjectLocation? projectLocation,
    ProfileTemplateRef? defaultTemplate,
  }) {
    return EmployeeProfile(
      id: id ?? this.id,
      employeeCode: employeeCode ?? this.employeeCode,
      name: name ?? this.name,
      email: email ?? this.email,
      position: position ?? this.position,
      grade: grade ?? this.grade,
      department: department ?? this.department,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      authMethod: authMethod ?? this.authMethod,
      monthlyIncentiveAmount:
          monthlyIncentiveAmount ?? this.monthlyIncentiveAmount,
      joinedDate: joinedDate ?? this.joinedDate,
      exitDate: exitDate ?? this.exitDate,
      isActive: isActive ?? this.isActive,
      manager: manager ?? this.manager,
      projectLocation: projectLocation ?? this.projectLocation,
      defaultTemplate: defaultTemplate ?? this.defaultTemplate,
    );
  }
}

class ProfileManagerRef {
  final String id;
  final String name;
  final String? email;
  final String? employeeCode;

  /// Manager's role on the wire — useful for the reporting-tree
  /// screen which shows a role pill next to each node.
  final String? role;

  const ProfileManagerRef({
    required this.id,
    required this.name,
    this.email,
    this.employeeCode,
    this.role,
  });

  factory ProfileManagerRef.fromJson(Map<String, dynamic> json) =>
      ProfileManagerRef(
        id: JsonParse.parseString(json['id']) ?? '',
        name: JsonParse.parseString(json['name']) ?? '',
        email: JsonParse.parseString(json['email']),
        employeeCode: JsonParse.parseString(json['employeeCode']),
        role: JsonParse.parseString(json['role']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'employeeCode': employeeCode,
        'role': role,
      };

  ProfileManagerRef copyWith({
    String? id,
    String? name,
    String? email,
    String? employeeCode,
    String? role,
  }) {
    return ProfileManagerRef(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      employeeCode: employeeCode ?? this.employeeCode,
      role: role ?? this.role,
    );
  }
}

class ProfileProjectLocation {
  final String id;
  final String name;
  final String? city;
  final String? state;

  /// Customer / client name for outsourced postings — `null` for
  /// internal locations.
  final String? customer;

  const ProfileProjectLocation({
    required this.id,
    required this.name,
    this.city,
    this.state,
    this.customer,
  });

  /// Single-line label used in dropdowns / cards. Falls back to just
  /// the name when no city is set.
  String get displayLabel {
    if (city != null && city!.isNotEmpty) return '$name — $city';
    return name;
  }

  factory ProfileProjectLocation.fromJson(Map<String, dynamic> json) =>
      ProfileProjectLocation(
        id: JsonParse.parseString(json['id']) ?? '',
        name: JsonParse.parseString(json['name']) ?? '',
        city: JsonParse.parseString(json['city']),
        state: JsonParse.parseString(json['state']),
        customer: JsonParse.parseString(json['customer']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'city': city,
        'state': state,
        'customer': customer,
      };

  ProfileProjectLocation copyWith({
    String? id,
    String? name,
    String? city,
    String? state,
    String? customer,
  }) {
    return ProfileProjectLocation(
      id: id ?? this.id,
      name: name ?? this.name,
      city: city ?? this.city,
      state: state ?? this.state,
      customer: customer ?? this.customer,
    );
  }
}

class ProfileTemplateRef {
  final String id;
  final String name;

  const ProfileTemplateRef({required this.id, required this.name});

  factory ProfileTemplateRef.fromJson(Map<String, dynamic> json) =>
      ProfileTemplateRef(
        id: JsonParse.parseString(json['id']) ?? '',
        name: JsonParse.parseString(json['name']) ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  ProfileTemplateRef copyWith({String? id, String? name}) =>
      ProfileTemplateRef(id: id ?? this.id, name: name ?? this.name);
}
