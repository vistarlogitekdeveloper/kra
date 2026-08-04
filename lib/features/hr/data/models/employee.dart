import '../../../../core/api/json_parse.dart';

/// Employee master record returned by /employees.
///
/// Field names mirror the API contract verbatim so JSON round-trips
/// cleanly. `managerId`, `managerName`, `joinedDate`, etc. are nullable
/// because the API permits partial records (a brand-new employee may not
/// yet have a manager assigned).
class Employee {
  final String id;
  final String employeeCode;
  final String fullName;
  final String email;

  /// Functional access role (EMPLOYEE / MANAGER / HR / FINANCE / …) — drives
  /// permissions + review routing. Derived from [position] at save time.
  final String role;

  /// Job designation / title (e.g. "Cluster Manager", "Sr. Accountant"). This
  /// is what HR picks; [role] is inferred from it. Stored in the backend's
  /// `position` column.
  final String? position;
  final String? department;
  final String? projectLocation;
  final String? projectLocationId;
  final String? managerId;
  final String? managerName;
  final String? grade;

  /// Per-employee monthly performance-incentive amount. `null` means the
  /// employee has no override and falls through to the org default on the
  /// backend (see the incentive-summary precedence).
  final double? monthlyIncentiveAmount;

  final bool isActive;
  final DateTime? joinedDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Employee({
    required this.id,
    required this.employeeCode,
    required this.fullName,
    required this.email,
    required this.role,
    this.position,
    this.department,
    this.projectLocation,
    this.projectLocationId,
    this.managerId,
    this.managerName,
    this.grade,
    this.monthlyIncentiveAmount,
    this.isActive = true,
    this.joinedDate,
    this.createdAt,
    this.updatedAt,
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id'] as String,
      employeeCode: (json['employeeCode'] ?? '') as String,
      fullName: (json['fullName'] ?? json['name'] ?? '') as String,
      email: (json['email'] ?? '') as String,
      role: (json['role'] ?? 'EMPLOYEE') as String,
      position: json['position'] as String?,
      department: json['department'] as String?,
      projectLocation: _readNestedName(json['projectLocation']),
      projectLocationId: _readNestedId(json['projectLocation']) ??
          json['projectLocationId'] as String?,
      managerId: json['managerId'] as String?,
      managerName:
          _readNestedName(json['manager']) ?? json['managerName'] as String?,
      grade: json['grade'] as String?,
      monthlyIncentiveAmount:
          JsonParse.parseDouble(json['monthlyIncentiveAmount']),
      isActive: (json['isActive'] as bool?) ?? true,
      joinedDate: JsonParse.parseDate(json['joinedDate']),
      createdAt: JsonParse.parseDate(json['createdAt']),
      updatedAt: JsonParse.parseDate(json['updatedAt']),
    );
  }

  static String? _readNestedName(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is Map && value['name'] is String) return value['name'] as String;
    return null;
  }

  static String? _readNestedId(dynamic value) {
    if (value is Map && value['id'] is String) return value['id'] as String;
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeCode': employeeCode,
        'fullName': fullName,
        'email': email,
        'role': role,
        'position': position,
        'department': department,
        'projectLocation': projectLocation,
        'projectLocationId': projectLocationId,
        'managerId': managerId,
        'managerName': managerName,
        'grade': grade,
        'monthlyIncentiveAmount': monthlyIncentiveAmount,
        'isActive': isActive,
        'joinedDate': joinedDate?.toIso8601String(),
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  Employee copyWith({
    String? id,
    String? employeeCode,
    String? fullName,
    String? email,
    String? role,
    String? position,
    String? department,
    String? projectLocation,
    String? projectLocationId,
    String? managerId,
    String? managerName,
    String? grade,
    double? monthlyIncentiveAmount,
    bool? isActive,
    DateTime? joinedDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Employee(
      id: id ?? this.id,
      employeeCode: employeeCode ?? this.employeeCode,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      role: role ?? this.role,
      position: position ?? this.position,
      department: department ?? this.department,
      projectLocation: projectLocation ?? this.projectLocation,
      projectLocationId: projectLocationId ?? this.projectLocationId,
      managerId: managerId ?? this.managerId,
      managerName: managerName ?? this.managerName,
      grade: grade ?? this.grade,
      monthlyIncentiveAmount:
          monthlyIncentiveAmount ?? this.monthlyIncentiveAmount,
      isActive: isActive ?? this.isActive,
      joinedDate: joinedDate ?? this.joinedDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Wraps a single page of employees from the paginated list endpoint.
/// `total` is the unfiltered count from the server so the UI can decide
/// whether more pages exist (`employees.length < total`).
class EmployeePage {
  final List<Employee> employees;
  final int page;
  final int pageSize;
  final int total;

  const EmployeePage({
    required this.employees,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  bool get hasMore => employees.length + ((page - 1) * pageSize) < total;

  factory EmployeePage.fromJson(Map<String, dynamic> json) {
    final list = (json['items'] ?? json['employees'] ?? json['data'] ?? [])
        as List<dynamic>;
    return EmployeePage(
      employees: list
          .whereType<Map<String, dynamic>>()
          .map(Employee.fromJson)
          .toList(),
      page: (json['page'] as int?) ?? 1,
      pageSize: (json['pageSize'] as int?) ?? list.length,
      total: (json['total'] as int?) ?? list.length,
    );
  }

  EmployeePage copyWith({
    List<Employee>? employees,
    int? page,
    int? pageSize,
    int? total,
  }) {
    return EmployeePage(
      employees: employees ?? this.employees,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      total: total ?? this.total,
    );
  }
}
