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
    test('HR-tier roles (ADMIN / HR_ADMIN / HR) land on /hr/home', () {
      expect(AppRoutes.dashboardForRole(UserRole.admin), AppRoutes.hrHome);
      expect(AppRoutes.dashboardForRole(UserRole.hrAdmin), AppRoutes.hrHome);
      expect(AppRoutes.dashboardForRole(UserRole.hr), AppRoutes.hrHome);
    });

    test('Manager-tier roles land on the team dashboard', () {
      expect(
        AppRoutes.dashboardForRole(UserRole.manager),
        AppRoutes.managerTeamDashboard,
      );
      expect(
        AppRoutes.dashboardForRole(UserRole.bdManager),
        AppRoutes.managerTeamDashboard,
      );
      expect(
        AppRoutes.dashboardForRole(UserRole.warehouseMgr),
        AppRoutes.managerTeamDashboard,
      );
    });

    test('Everyone else lands on /employee/home', () {
      expect(
        AppRoutes.dashboardForRole(UserRole.employee),
        AppRoutes.employeeHome,
      );
      expect(
        AppRoutes.dashboardForRole(UserRole.ops),
        AppRoutes.employeeHome,
      );
      expect(
        AppRoutes.dashboardForRole(UserRole.finance),
        AppRoutes.employeeHome,
      );
    });

    test('every enum case is handled (no unreachable role)', () {
      // Dart's switch enforces exhaustiveness at compile time; this
      // extra assert is documentary: if we ever add a new UserRole
      // and forget to map it, the iteration here would surface a
      // missing case to the dev rather than the user.
      for (final r in UserRole.values) {
        final dest = AppRoutes.dashboardForRole(r);
        expect(
          [
            AppRoutes.hrHome,
            AppRoutes.managerTeamDashboard,
            AppRoutes.employeeHome,
          ],
          contains(dest),
          reason: 'unexpected landing route for $r: $dest',
        );
      }
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
