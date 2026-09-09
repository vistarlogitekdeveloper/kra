import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/router/app_router.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';

/// The SUPER_ADMIN tier.
///
/// `UserRole.fromApi` used to fold `SUPER_ADMIN` into `UserRole.admin`, so the
/// app could not tell the two apart and could never grant one more than the
/// other. It is now its own role holding every seat beneath it.
///
/// IMPORTANT: everything asserted here is CLIENT-side authority, and the server
/// only partly agrees. Two separate mechanisms decide, and they were fixed at
/// different times:
///
///   * ROUTE guards (`requireRoles`) now honour a hierarchy —
///     `IMPLIED_ROLES.SUPER_ADMIN` in `middleware/rbac.middleware.js` holds
///     every role beneath it, so a super admin clears every route. This used to
///     be a flat exact-match naming no route guard, which left SUPER_ADMIN
///     strictly LESS privileged than HR_ADMIN.
///   * PER-STAGE rating gates in `monthly-reviews.service.js` compared
///     `user.role` directly against its own `ACTOR_ROLES` table and never
///     consulted that hierarchy — so a super admin passed the route and was
///     then refused by the service on every rating stage. Fixed by
///     docs/install_rating_roles.mjs, which routes those checks through
///     `rolesHeldBy()` instead of copying the role list a third time.
///
/// So: verify against a server that has BOTH, and see
/// docs/RATING_ROLE_DIVERGENCE.md for what the two role tables still disagree
/// about. docs/SUPER_ADMIN_BACKEND_SPEC.md has the original spec.
void main() {
  User userWith(UserRole role, {Set<UserRole>? roles}) => User(
        id: 'u1',
        email: 'boss@vistar.test',
        fullName: 'Boss',
        role: role,
        roles: roles,
        organizationId: 'org1',
      );

  group('wire mapping', () {
    test('SUPER_ADMIN is its own role, distinct from ADMIN', () {
      expect(UserRole.fromApi('SUPER_ADMIN'), UserRole.superAdmin);
      expect(UserRole.fromApi('ADMIN'), UserRole.admin);
      expect(UserRole.superAdmin, isNot(UserRole.admin));
    });

    test('tolerates case and whitespace like every other role', () {
      expect(UserRole.fromApi('  super_admin  '), UserRole.superAdmin);
    });

    test('round-trips to the wire form the backend RoleEnum stores', () {
      expect(UserRole.superAdmin.toApiString(), 'SUPER_ADMIN');
    });

    test('EVERY role round-trips through the wire form', () {
      // toApiString() used to be name.toUpperCase(), which dropped the
      // underscore on every multi-word role — hrAdmin became "HRADMIN",
      // which the backend RoleEnum rejects with VAL_001.
      for (final r in UserRole.values) {
        expect(UserRole.fromApi(r.toApiString()), r, reason: 'role ${r.name}');
      }
    });

    test('the wire forms are exactly the backend employees RoleEnum values',
        () {
      // Mirrors src/modules/kra/.../employees.types.js RoleEnum. ADMIN is
      // absent there — it is a legacy client-side role, so it is excluded.
      const backendRoleEnum = {
        'EMPLOYEE',
        'MANAGER',
        'OPS_EXCELLENCE',
        'OPS',
        'HR',
        'HR_ADMIN',
        'FINANCE',
        'BD_MANAGER',
        'WAREHOUSE_MGR',
        'MANAGEMENT',
        'SUPER_ADMIN',
      };
      for (final r in UserRole.values) {
        if (r == UserRole.admin) continue;
        expect(backendRoleEnum, contains(r.toApiString()),
            reason: 'role ${r.name} would be rejected by the API');
      }
    });

    test('has a display name — an unnamed role would render blank in the UI',
        () {
      expect(UserRole.superAdmin.displayName, 'Super Admin');
    });
  });

  group('the role-granting tier', () {
    test('super admin is the tier', () {
      expect(userWith(UserRole.superAdmin).isSuperAdmin, isTrue);
    });

    test('legacy ADMIN keeps the tier — it must not lose what it has today',
        () {
      expect(userWith(UserRole.admin).isSuperAdmin, isTrue);
    });

    test('HR admin is NOT the tier — granting roles is an escalation path', () {
      expect(userWith(UserRole.hrAdmin).isSuperAdmin, isFalse);
    });

    test('no other role is the tier', () {
      for (final r in UserRole.values) {
        if (r == UserRole.superAdmin || r == UserRole.admin) continue;
        expect(userWith(r).isSuperAdmin, isFalse, reason: 'role ${r.name}');
      }
    });

    test('holds the tier via the multi-role set, not just the primary role',
        () {
      final u = userWith(UserRole.employee, roles: {UserRole.superAdmin});
      expect(u.isSuperAdmin, isTrue);
    });
  });

  group('route access', () {
    test('reaches the HR console', () {
      expect(AppRoutes.canAccessHr(UserRole.superAdmin), isTrue);
    });

    test('reaches the manager workspace with no direct reports at all', () {
      // Unconditional, like hrAdmin/admin — it does not depend on a
      // reporting relationship.
      expect(
        AppRoutes.canAccessManager(UserRole.superAdmin, hasReports: false),
        isTrue,
      );
    });

    test('lands on the HR home after login, not the employee self-view', () {
      expect(AppRoutes.dashboardForRole(UserRole.superAdmin), AppRoutes.hrHome);
    });
  });

  group('review pipeline seats', () {
    test('holds every ORG-LEVEL stage', () {
      const orgStages = [
        ReviewStage.accountHrRating,
        ReviewStage.financeRating,
        ReviewStage.managementReview,
        ReviewStage.incentivePayout,
      ];
      for (final s in orgStages) {
        expect(s.isActionableBy(UserRole.superAdmin), isTrue,
            reason: 'stage ${s.name}');
      }
    });

    test('holds more org-level stages than any other single role', () {
      int seats(UserRole r) => [
            ReviewStage.accountHrRating,
            ReviewStage.financeRating,
            ReviewStage.managementReview,
            ReviewStage.incentivePayout,
          ].where((s) => s.isActionableBy(r)).length;

      final mine = seats(UserRole.superAdmin);
      expect(mine, 4);
      for (final r in UserRole.values) {
        if (r == UserRole.superAdmin) continue;
        expect(seats(r), lessThanOrEqualTo(mine), reason: 'role ${r.name}');
      }
    });

    test('does NOT take over the relationship stages', () {
      // Self-rating belongs to the review's owner and the reporting-manager
      // rating to that review's manager, whoever they are. Being super admin
      // must not let someone rate on another person's behalf.
      expect(
          ReviewStage.selfRating.isActionableBy(UserRole.superAdmin), isFalse);
      expect(
        ReviewStage.reportingManagerRating.isActionableBy(UserRole.superAdmin),
        isFalse,
      );
    });

    test('cannot act on the terminal stage', () {
      expect(
          ReviewStage.completed.isActionableBy(UserRole.superAdmin), isFalse);
    });

    test('management holds its own sign-off stage', () {
      // Regression guard. The sheet's management gate used to restate a role
      // list — {hrAdmin, admin} — that omitted `management` itself, so the tier
      // that exclusively owns managementReview could not open the sign-off UI.
      // The gate now derives from this stage, so the two cannot drift apart.
      expect(ReviewStage.managementReview.isActionableBy(UserRole.management),
          isTrue);
    });

    test('legacy admin holds NO review-stage authority', () {
      // The other half of that drift: `admin` passed the sheet's management
      // gate while the model granted it nothing. The model is authoritative,
      // and `ADMIN` is not even a storable role in the backend RoleEnum.
      for (final s in ReviewStage.values) {
        expect(s.isActionableBy(UserRole.admin), isFalse,
            reason: 'stage ${s.name}');
      }
    });
  });
}
