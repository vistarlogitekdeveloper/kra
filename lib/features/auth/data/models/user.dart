import 'package:flutter/foundation.dart';

import '../../../../core/api/json_parse.dart';
import '../../../../core/enums/review_flow.dart';

/// All roles in the Vistar KRA system.
///
/// HR_ADMIN has elevated privileges within the HR module (audit log, dashboard).
/// ADMIN is the legacy super-user, also routed to the HR dashboard. SUPER_ADMIN
/// is the organisation-wide top tier and holds every seat below it.
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
  management,

  /// The organisation-wide top tier — the backend's `SUPER_ADMIN`.
  ///
  /// Its own role rather than an alias of [admin], which is what it used to
  /// collapse into. That collapse meant the app could not tell a SUPER_ADMIN
  /// from an ADMIN at all, so it could never grant one more than the other.
  ///
  /// The backend documents this role as sitting above `HR_ADMIN` as the
  /// role-granting authority, and its `RoleEnum` stores it — but as of this
  /// writing NO backend route guard names it, and `requireRoles` is a flat
  /// exact-match with no hierarchy. So a SUPER_ADMIN is currently REJECTED by
  /// every privileged endpoint (they all require `HR_ADMIN` / `ADMIN`), and the
  /// client-side access granted for it runs ahead of the API on purpose. See
  /// `docs/SUPER_ADMIN_BACKEND_SPEC.md` for the change list that makes it real;
  /// until that ships, writes answer 403.
  superAdmin;

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
        return UserRole.admin;
      // Its own role now. Collapsing it into ADMIN made the two
      // indistinguishable, so the app could never grant one more than the
      // other — which is exactly what a super-admin tier needs to do.
      case 'SUPER_ADMIN':
        return UserRole.superAdmin;
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

  /// The on-wire form — used when echoing a role back to the API.
  ///
  /// Spelled out per case rather than `name.toUpperCase()`, which silently
  /// dropped the underscore on every multi-word role: `hrAdmin` became
  /// `HRADMIN`, `bdManager` `BDMANAGER`, `warehouseMgr` `WAREHOUSEMGR` — none
  /// of which the backend's employees `RoleEnum` accepts, so they come back as
  /// `VAL_001 Validation failed`. Latent while only the scalar `role` is echoed
  /// from a cached user, but [FeatureFlags.multiRole] sends the whole `roles`
  /// array, which would have made it a 400 on every save.
  ///
  /// [UserRole.fromApi] of this value must return the same case for every role
  /// — there is a round-trip test over `UserRole.values` pinning exactly that.
  String toApiString() {
    switch (this) {
      case UserRole.admin:
        return 'ADMIN';
      case UserRole.hrAdmin:
        return 'HR_ADMIN';
      case UserRole.employee:
        return 'EMPLOYEE';
      case UserRole.manager:
        return 'MANAGER';
      case UserRole.ops:
        return 'OPS';
      case UserRole.hr:
        return 'HR';
      case UserRole.finance:
        return 'FINANCE';
      case UserRole.bdManager:
        return 'BD_MANAGER';
      case UserRole.warehouseMgr:
        return 'WAREHOUSE_MGR';
      case UserRole.management:
        return 'MANAGEMENT';
      case UserRole.superAdmin:
        return 'SUPER_ADMIN';
    }
  }

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
      case UserRole.superAdmin:
        return 'Super Admin';
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

  /// Which review pipeline this user's organisation runs.
  ///
  /// Carried on the user because it has to be readable by EVERY role: only a
  /// super admin may call `/organizations`, so HR, managers and employees
  /// cannot look their own organisation up. The auth payload is the one place
  /// all of them see.
  ///
  /// Defaults to [ReviewFlow.standard] when absent, which is the case on any
  /// server that has not shipped the field — see [ReviewFlow.fromApi].
  final ReviewFlow reviewFlow;
  final String? projectLocationId;
  final bool hasReports;

  const User({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    Set<UserRole>? roles,
    required this.organizationId,
    this.reviewFlow = ReviewFlow.standard,
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
  Set<UserRole> get effectiveRoles => roles.isEmpty ? {role} : {role, ...roles};

  /// The super-admin tier: the only one that may change other people's access.
  ///
  /// [UserRole.superAdmin] is that tier, with [UserRole.admin] kept alongside it
  /// so existing ADMIN holders don't lose the privilege they have today.
  /// Deliberately NOT [UserRole.hrAdmin]: HR admins administer employee records,
  /// but handing out roles (including their own) is a privilege-escalation path,
  /// so it stays above them.
  bool get isSuperAdmin =>
      hasAnyRole(const {UserRole.superAdmin, UserRole.admin});

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
      // Absent on any server without the field, which resolves to the
      // standard pipeline — see ReviewFlow.fromApi.
      reviewFlow: ReviewFlow.fromApi(JsonParse.parseString(json['reviewFlow'])),
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
        'reviewFlow': reviewFlow.toApiString(),
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
    ReviewFlow? reviewFlow,
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
      reviewFlow: reviewFlow ?? this.reviewFlow,
      projectLocationId: projectLocationId ?? this.projectLocationId,
      hasReports: hasReports ?? this.hasReports,
    );
  }
}
