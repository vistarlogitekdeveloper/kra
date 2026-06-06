import 'package:flutter/foundation.dart';

/// All roles in the Vistar KRA system.
/// HR_ADMIN has elevated privileges within the HR module (audit log, dashboard).
/// ADMIN is the super-user, also routed to the HR dashboard.
enum UserRole {
  admin,
  hrAdmin,
  employee,
  manager,
  ops,
  hr,
  finance,
  bdManager,
  warehouseMgr;

  /// Tolerates "ADMIN" / "Admin" / "admin" / "EMPLOYEE" / "HR_ADMIN" etc.
  /// and falls back to [employee] on any unknown value rather than
  /// throwing — new roles introduced server-side won't crash older clients.
  ///
  /// Composite roles like "HR_ADMIN" are common on the backend (one user
  /// who is both HR and an org admin). For routing we treat them as
  /// admin so they land on the HR dashboard with elevated privileges.
  static UserRole fromApi(String value) {
    final normalized = value.trim().toUpperCase();
    switch (normalized) {
      case 'ADMIN':
      case 'SUPER_ADMIN':
        return UserRole.admin;
      case 'HR_ADMIN':
        return UserRole.hrAdmin;
      case 'HR':
        return UserRole.hr;
      case 'MANAGER':
        return UserRole.manager;
      case 'OPS':
      case 'OPS_EXCELLENCE':
        return UserRole.ops;
      case 'FINANCE':
        return UserRole.finance;
      case 'EMPLOYEE':
        return UserRole.employee;
      case 'BD_MANAGER':
        return UserRole.bdManager;
      case 'WAREHOUSE_MGR':
        return UserRole.warehouseMgr;
      default:
        // Unknown role from server — default to employee (least privilege).
        // Log in debug builds so a silently-demoted user is diagnosable:
        // a new backend role rolling out will look like "every CFO user
        // lost their dashboards" otherwise.
        assert(() {
          debugPrint(
            'UserRole.fromApi: unknown server role "$value" — '
            'defaulting to EMPLOYEE',
          );
          return true;
        }());
        return UserRole.employee;
    }
  }

  /// The on-wire form (UPPERCASE) — used when echoing back to the API.
  String toApiString() => name.toUpperCase();

  String get displayName {
    switch (this) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.hrAdmin:
        return 'HR Admin';
      case UserRole.employee:
        return 'Employee';
      case UserRole.manager:
        return 'Manager';
      case UserRole.ops:
        return 'Ops Excellence';
      case UserRole.hr:
        return 'HR';
      case UserRole.finance:
        return 'Finance';
      case UserRole.bdManager:
        return 'BD Manager';
      case UserRole.warehouseMgr:
        return 'Warehouse Manager';
    }
  }
}

/// User entity as returned by /auth/login and /auth/me.
///
/// Field names mirror the API contract exactly so JSON round-trips
/// cleanly. `projectLocationId` is nullable — head-office staff (HR,
/// Finance, Ops) often don't have a site assignment.
class User {
  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final String organizationId;
  final String? projectLocationId;

  const User({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.organizationId,
    this.projectLocationId,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    // The login endpoint returns `name`; /auth/me returns `fullName`.
    // Tolerate both so clients work against either response shape.
    final displayName =
        (json['fullName'] ?? json['name'] ?? '') as String;
    return User(
      id: (json['id'] ?? '') as String,
      email: (json['email'] ?? '') as String,
      fullName: displayName,
      role: UserRole.fromApi((json['role'] ?? 'EMPLOYEE') as String),
      organizationId: (json['organizationId'] ?? '') as String,
      projectLocationId: json['projectLocationId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'fullName': fullName,
        'role': role.toApiString(),
        'organizationId': organizationId,
        'projectLocationId': projectLocationId,
      };

  User copyWith({
    String? id,
    String? email,
    String? fullName,
    UserRole? role,
    String? organizationId,
    String? projectLocationId,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      organizationId: organizationId ?? this.organizationId,
      projectLocationId: projectLocationId ?? this.projectLocationId,
    );
  }
}
