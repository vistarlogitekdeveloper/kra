import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/router/app_router.dart';
import 'package:vistar_app/core/widgets/workspace_switcher.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';

User mockUser(UserRole role, {bool hasReports = false}) {
  return User(
    id: 'test-id',
    email: 'test@vistar.test',
    fullName: 'Test User',
    role: role,
    organizationId: 'org-id',
    hasReports: hasReports,
  );
}

/// The switcher must offer exactly the workspaces a role can actually reach —
/// mirroring the router guards — with the self-view ("My KRA") always present.
void main() {
  group('WorkspaceSwitcher.workspacesFor', () {
    List<String> labels(UserRole role, {bool hasReports = false}) =>
        WorkspaceSwitcher.workspacesFor(mockUser(role, hasReports: hasReports))
            .map((w) => w.label)
            .toList();

    test('My KRA is always first and always present', () {
      for (final r in UserRole.values) {
        final list = WorkspaceSwitcher.workspacesFor(mockUser(r));
        expect(list, isNotEmpty, reason: '$r has no workspaces');
        expect(list.first.route, AppRoutes.employeeHome,
            reason: '$r must start with My KRA');
      }
    });

    test('plain employee / ops has ONLY My KRA', () {
      expect(labels(UserRole.employee), ['My KRA']);
      expect(labels(UserRole.ops), ['My KRA']);
    });

    test('employee with reports gets My KRA + My Team', () {
      expect(labels(UserRole.employee, hasReports: true), ['My KRA', 'My Team']);
    });

    test('manager gets My KRA + My Team (no Reviews / HR)', () {
      final list = WorkspaceSwitcher.workspacesFor(mockUser(UserRole.manager));
      expect(list.map((w) => w.route),
          [AppRoutes.employeeHome, AppRoutes.managerTeamDashboard]);
    });

    test('HR and Accounts (Finance) get My KRA + Reviews', () {
      // Review-only roles land on the shared My KRA home and reach the review
      // dashboard through the Reviews workspace — not a bare, menu-less screen.
      for (final r in [UserRole.hr, UserRole.finance]) {
        expect(labels(r), ['My KRA', 'Reviews'], reason: '$r');
        expect(
          WorkspaceSwitcher.workspacesFor(mockUser(r)).map((w) => w.route),
          [AppRoutes.employeeHome, AppRoutes.monthlyReviews],
        );
      }
    });

    test('HR_ADMIN gets all four (My KRA + My Team + Reviews + HR Admin)', () {
      final list = WorkspaceSwitcher.workspacesFor(mockUser(UserRole.hrAdmin));
      expect(list.map((w) => w.route), [
        AppRoutes.employeeHome,
        AppRoutes.managerTeamDashboard,
        AppRoutes.monthlyReviews,
        AppRoutes.hrHome,
      ]);
    });
  });

  group('WorkspaceSwitcher.hasExtras', () {
    test('false for roles with only the self-view', () {
      expect(WorkspaceSwitcher.hasExtras(mockUser(UserRole.employee)), isFalse);
      expect(WorkspaceSwitcher.hasExtras(mockUser(UserRole.ops)), isFalse);
    });

    test('true for employee with reports', () {
      expect(WorkspaceSwitcher.hasExtras(mockUser(UserRole.employee, hasReports: true)), isTrue);
    });

    test('true for reviewer roles (HR / Accounts) — they get Reviews', () {
      // They now land on My KRA and reach the review dashboard via the "☰"
      // menu, so the menu MUST surface for them.
      expect(WorkspaceSwitcher.hasExtras(mockUser(UserRole.hr)), isTrue);
      expect(WorkspaceSwitcher.hasExtras(mockUser(UserRole.finance)), isTrue);
    });

    test('true for manager / HR_ADMIN / admin roles', () {
      expect(WorkspaceSwitcher.hasExtras(mockUser(UserRole.manager)), isTrue);
      expect(WorkspaceSwitcher.hasExtras(mockUser(UserRole.hrAdmin)), isTrue);
      expect(WorkspaceSwitcher.hasExtras(mockUser(UserRole.admin)), isTrue);
    });
  });
}
