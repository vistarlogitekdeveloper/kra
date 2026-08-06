import 'package:flutter/foundation.dart';

import '../../../../core/api/json_parse.dart';

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
  warehouseMgr,

  /// The management tier (founder / CEO / director) — holds the Management
  /// review, the approval/override that is the final word on a score and its
  /// incentive.
  ///
  /// Deliberately separate from [hrAdmin]: HR administers the cycle and rates
  /// the HR seat, but must not also sign off on it. Recognised here ahead of the
  /// backend so that the day its employees enum gains `MANAGEMENT`, holders are
  /// read correctly instead of falling through [fromApi]'s default to
  /// [employee] — which would silently demote the founder to a plain employee.
  management;

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
      case 'MANAGEMENT':
        return UserRole.management;
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
      case UserRole.management:
        return 'Management';
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

  /// PRIMARY role — the one used for display and for the single-role decisions
  /// that predate multi-role (a user's "home" workspace, for instance). Always
  /// a member of [roles].
  final UserRole role;

  /// EVERY role this user holds. One post can carry several responsibilities —
  /// the commercial/HR-admin who also rates the Accounts seat — and a single
  /// enum value cannot say that.
  ///
  /// Falls back to `{role}` when the backend sends only the scalar `role`, which
  /// is the case today, so every permission check below behaves exactly as it
  /// did before until a `roles` array actually arrives.
  final Set<UserRole> roles;
  final String organizationId;
  final String? projectLocationId;
  final bool hasReports;

  const User({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    Set<UserRole>? roles,
    required this.organizationId,
    this.projectLocationId,
    this.hasReports = false,
  }) : roles = roles ?? const {};

  /// True when the user holds [r] — checks the whole set, not just [role].
  bool hasRole(UserRole r) => effectiveRoles.contains(r);

  /// True when the user holds ANY of [candidates]. The workhorse for permission
  /// checks, which are all "is one of these seats mine?".
  bool hasAnyRole(Set<UserRole> candidates) =>
      effectiveRoles.intersection(candidates).isNotEmpty;

  /// [roles], or `{role}` when the backend sent only the scalar. Never empty, so
  /// callers never have to special-case a role-less user.
  Set<UserRole> get effectiveRoles =>
      roles.isEmpty ? {role} : {role, ...roles};

  /// The super-admin tier: the only one that may change other people's access.
  ///
  /// [UserRole.admin] is that tier — the backend's `ADMIN` / `SUPER_ADMIN` both
  /// map to it. Deliberately NOT [UserRole.hrAdmin]: HR admins administer
  /// employee records, but handing out roles (including their own) is a
  /// privilege-escalation path, so it stays above them.
  bool get isSuperAdmin => hasRole(UserRole.admin);

  factory User.fromJson(Map<String, dynamic> json) {
    // The login endpoint returns `name`; /auth/me returns `fullName`.
    // Tolerate both so clients work against either response shape.
    // Read every field tolerantly — some backends serialise ids as
    // numbers. A hard `as String` cast on a numeric id would throw a
    // TypeError that surfaces as a generic "Something went wrong" on
    // login (or a wiped cache on boot), with no clue to the real cause.
    final displayName =
        JsonParse.parseString(json['fullName'] ?? json['name']) ?? '';
    // `roles` is the multi-role shape; absent today, so fall back to the scalar
    // `role`. Unknown strings resolve to EMPLOYEE via fromApi rather than
    // throwing, so a role added server-side can't take out login.
    final rawRoles = json['roles'];
    final parsedRoles = rawRoles is List
        ? rawRoles
            .map((r) => JsonParse.parseString(r))
            .whereType<String>()
            .map(UserRole.fromApi)
            .toSet()
        : <UserRole>{};
    return User(
      id: JsonParse.parseString(json['id']) ?? '',
      email: JsonParse.parseString(json['email']) ?? '',
      fullName: displayName,
      role: UserRole.fromApi(JsonParse.parseString(json['role']) ??
          (parsedRoles.isNotEmpty
              ? parsedRoles.first.toApiString()
              : 'EMPLOYEE')),
      roles: parsedRoles,
      organizationId: JsonParse.parseString(json['organizationId']) ?? '',
      projectLocationId: JsonParse.parseString(json['projectLocationId']),
      hasReports: json['hasReports'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'fullName': fullName,
        'role': role.toApiString(),
        'roles': [for (final r in effectiveRoles) r.toApiString()],
        'organizationId': organizationId,
        'projectLocationId': projectLocationId,
        'hasReports': hasReports,
      };

  User copyWith({
    String? id,
    String? email,
    String? fullName,
    UserRole? role,
    Set<UserRole>? roles,
    String? organizationId,
    String? projectLocationId,
    bool? hasReports,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      roles: roles ?? this.roles,
      organizationId: organizationId ?? this.organizationId,
      projectLocationId: projectLocationId ?? this.projectLocationId,
      hasReports: hasReports ?? this.hasReports,
    );
  }
}
