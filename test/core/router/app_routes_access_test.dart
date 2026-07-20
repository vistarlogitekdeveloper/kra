import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/router/app_router.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';

/// The role-access matrix is the security boundary that decides
/// which dashboard each user lands on and which `/manager/*` and
/// `/hr/*` deep-links are walled off. Lock the matrix in tests so a
/// future refactor can't quietly downgrade a role (e.g. drop HR's
/// /hr access by missing a switch case).
///
/// Note: `_canAccessHr` is private and only reachable through the
/// router redirect; this test covers the equivalent intent via
/// `dashboardForRole` — every role that lands on `/hr/home` is, by
/// the redirect logic, an HR-allowed role.
void main() {
  group('AppRoutes.dashboardForRole', () {
    test('HR-tier roles land in the HR admin area', () {
      // HR/admin run the HR workspace day to day, so landing them on their own
      // KRA forced a detour through the workspace switcher every login.
      for (final r in [UserRole.hr, UserRole.hrAdmin, UserRole.admin]) {
        expect(
          AppRoutes.dashboardForRole(r),
          AppRoutes.hrHome,
          reason: 'HR-tier role $r must land in the HR admin area',
        );
      }
    });

    test('every non-HR role lands on the employee self-view (My KRA)', () {
      // The self-view is a user's OWN KRA/review and lives only under
      // /employee/*. It stays the landing for everyone else so that e.g. a
      // manager with zero direct reports still sees their own KRA rather than
      // a blank/403 team screen.
      for (final r in UserRole.values.where((r) => !AppRoutes.canAccessHr(r))) {
        expect(
          AppRoutes.dashboardForRole(r),
          AppRoutes.employeeHome,
          reason: 'role $r must land on the employee self-view',
        );
      }
    });

    test('never lands a role in an area its own guard would reject', () {
      // Load-bearing invariant, not a nicety: the redirect uses this same
      // function to bounce a role OUT of an area it can't access. If it ever
      // returned /hr/home for a non-HR role, that bounce would target the very
      // area being rejected and the router would spin in a redirect loop.
      for (final r in UserRole.values) {
        if (AppRoutes.dashboardForRole(r) == AppRoutes.hrHome) {
          expect(
            AppRoutes.canAccessHr(r),
            isTrue,
            reason: 'role $r lands on /hr/home but the HR guard rejects it — '
                'this would be an infinite redirect loop',
          );
        }
      }
    });
  });

  group('AppRoutes.canAccessHr', () {
    test('HR-tier roles (HR / HR_ADMIN / ADMIN) can access /hr/*', () {
      expect(AppRoutes.canAccessHr(UserRole.hr), isTrue);
      expect(AppRoutes.canAccessHr(UserRole.hrAdmin), isTrue);
      expect(AppRoutes.canAccessHr(UserRole.admin), isTrue);
    });

    test('non-HR roles are walled off from /hr/*', () {
      expect(AppRoutes.canAccessHr(UserRole.manager), isFalse);
      expect(AppRoutes.canAccessHr(UserRole.bdManager), isFalse);
      expect(AppRoutes.canAccessHr(UserRole.warehouseMgr), isFalse);
      expect(AppRoutes.canAccessHr(UserRole.employee), isFalse);
      expect(AppRoutes.canAccessHr(UserRole.ops), isFalse);
      expect(AppRoutes.canAccessHr(UserRole.finance), isFalse);
    });
  });

  group('AppRoutes.canAccessManager', () {
    test('manager-capable roles can access /manager/*', () {
      expect(AppRoutes.canAccessManager(UserRole.manager), isTrue);
      expect(AppRoutes.canAccessManager(UserRole.bdManager), isTrue);
      expect(AppRoutes.canAccessManager(UserRole.warehouseMgr), isTrue);
      // HR_ADMIN can hop into manager view for escalations.
      expect(AppRoutes.canAccessManager(UserRole.hrAdmin), isTrue);
      expect(AppRoutes.canAccessManager(UserRole.admin), isTrue);
    });

    test('plain HR cannot access /manager/* (HR_ADMIN can; intentional)', () {
      // HR / HR_ADMIN asymmetry is documented in app_router.dart.
      // This test pins the asymmetry — if a future refactor adds HR
      // to canAccessManager by mistake, the test surfaces it.
      expect(AppRoutes.canAccessManager(UserRole.hr), isFalse);
    });

    test('employee / ops / finance are walled off from /manager/*', () {
      expect(AppRoutes.canAccessManager(UserRole.employee), isFalse);
      expect(AppRoutes.canAccessManager(UserRole.ops), isFalse);
      expect(AppRoutes.canAccessManager(UserRole.finance), isFalse);
    });
  });

  group('UserRole.fromApi safety', () {
    test('unknown role demotes to EMPLOYEE (least privilege)', () {
      expect(UserRole.fromApi('CFO'), UserRole.employee);
      expect(UserRole.fromApi(''), UserRole.employee);
      expect(UserRole.fromApi('not_a_real_role'), UserRole.employee);
    });

    test('known aliases map to canonical enum cases', () {
      expect(UserRole.fromApi('SUPER_ADMIN'), UserRole.admin);
      expect(UserRole.fromApi('OPS_EXCELLENCE'), UserRole.ops);
      // Tolerant of case + whitespace.
      expect(UserRole.fromApi('  hr_admin  '), UserRole.hrAdmin);
      expect(UserRole.fromApi('Manager'), UserRole.manager);
    });
  });
}
