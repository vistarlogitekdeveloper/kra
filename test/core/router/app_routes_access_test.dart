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
    test('HR_ADMIN / ADMIN boot straight into the HR console', () {
      // Admins run the HR console day to day, so they keep landing there.
      for (final r in [UserRole.hrAdmin, UserRole.admin]) {
        expect(
          AppRoutes.dashboardForRole(r),
          AppRoutes.hrHome,
          reason: 'admin role $r must land in the HR admin area',
        );
      }
    });

    test('every non-admin role lands on the shared My KRA self-view', () {
      // One home for all non-admin logins — employee, manager, and the
      // review-only HR / Accounts roles. Role only ADDS reachable areas
      // (My Team / Reviews) via the "☰" switcher, so Accounts / HR get the
      // same first-class home as everyone else, not a bare review dashboard.
      for (final r in UserRole.values.where((r) => !AppRoutes.canAccessHr(r))) {
        expect(
          AppRoutes.dashboardForRole(r),
          AppRoutes.employeeHome,
          reason: 'role $r must land on the shared My KRA self-view',
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
    test('only HR_ADMIN / ADMIN can access the /hr/* admin console', () {
      expect(AppRoutes.canAccessHr(UserRole.hrAdmin), isTrue);
      expect(AppRoutes.canAccessHr(UserRole.admin), isTrue);
    });

    test('review + operational roles are walled off from /hr/*', () {
      // Plain HR is review-only now — the admin console is HR_ADMIN / ADMIN.
      expect(AppRoutes.canAccessHr(UserRole.hr), isFalse);
      expect(AppRoutes.canAccessHr(UserRole.finance), isFalse);
      expect(AppRoutes.canAccessHr(UserRole.manager), isFalse);
      expect(AppRoutes.canAccessHr(UserRole.bdManager), isFalse);
      expect(AppRoutes.canAccessHr(UserRole.warehouseMgr), isFalse);
      expect(AppRoutes.canAccessHr(UserRole.employee), isFalse);
      expect(AppRoutes.canAccessHr(UserRole.ops), isFalse);
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

  group('AppRoutes.canReview', () {
    test('HR / Accounts / HR_ADMIN / ADMIN get the Reviews workspace', () {
      expect(AppRoutes.canReview(UserRole.hr), isTrue);
      expect(AppRoutes.canReview(UserRole.finance), isTrue);
      expect(AppRoutes.canReview(UserRole.hrAdmin), isTrue);
      expect(AppRoutes.canReview(UserRole.admin), isTrue);
    });

    test('employees / ops / plain managers do not (managers use My Team)', () {
      expect(AppRoutes.canReview(UserRole.employee), isFalse);
      expect(AppRoutes.canReview(UserRole.ops), isFalse);
      expect(AppRoutes.canReview(UserRole.manager), isFalse);
      expect(AppRoutes.canReview(UserRole.bdManager), isFalse);
      expect(AppRoutes.canReview(UserRole.warehouseMgr), isFalse);
    });
  });

  group('UserRole.fromApi safety', () {
    test('unknown role demotes to EMPLOYEE (least privilege)', () {
      expect(UserRole.fromApi('CFO'), UserRole.employee);
      expect(UserRole.fromApi(''), UserRole.employee);
      expect(UserRole.fromApi('not_a_real_role'), UserRole.employee);
    });

    test('known aliases map to canonical enum cases', () {
      // SUPER_ADMIN is its OWN role, no longer an alias of ADMIN — the two
      // used to collapse together, which made it impossible to grant the
      // super-admin tier anything ADMIN did not already have.
      expect(UserRole.fromApi('SUPER_ADMIN'), UserRole.superAdmin);
      expect(UserRole.fromApi('ADMIN'), UserRole.admin);
      expect(UserRole.fromApi('OPS_EXCELLENCE'), UserRole.ops);
      // Tolerant of case + whitespace.
      expect(UserRole.fromApi('  hr_admin  '), UserRole.hrAdmin);
      expect(UserRole.fromApi('Manager'), UserRole.manager);
    });
  });
}
