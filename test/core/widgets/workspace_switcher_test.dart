import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/router/app_router.dart';
import 'package:vistar_app/core/widgets/workspace_switcher.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';

/// The switcher must offer exactly the workspaces a role can actually reach —
/// mirroring the router guards — with the self-view ("My KRA") always present.
void main() {
  group('WorkspaceSwitcher.workspacesFor', () {
    List<String> labels(UserRole role) =>
        WorkspaceSwitcher.workspacesFor(role).map((w) => w.label).toList();

    test('My KRA is always first and always present', () {
      for (final r in UserRole.values) {
        final list = WorkspaceSwitcher.workspacesFor(r);
        expect(list, isNotEmpty, reason: '$r has no workspaces');
        expect(list.first.route, AppRoutes.employeeHome,
            reason: '$r must start with My KRA');
      }
    });

    test('plain employee has ONLY My KRA', () {
      expect(labels(UserRole.employee), ['My KRA']);
      expect(labels(UserRole.ops), ['My KRA']);
      expect(labels(UserRole.finance), ['My KRA']);
    });

    test('manager gets My KRA + My Team (no HR)', () {
      final list = WorkspaceSwitcher.workspacesFor(UserRole.manager);
      expect(list.map((w) => w.route),
          [AppRoutes.employeeHome, AppRoutes.managerTeamDashboard]);
    });

    test('plain HR gets My KRA + HR Admin (no team — HR cannot access /manager)',
        () {
      final list = WorkspaceSwitcher.workspacesFor(UserRole.hr);
      expect(list.map((w) => w.route),
          [AppRoutes.employeeHome, AppRoutes.hrHome]);
    });

    test('HR_ADMIN gets all three (My KRA + My Team + HR Admin)', () {
      final list = WorkspaceSwitcher.workspacesFor(UserRole.hrAdmin);
      expect(list.map((w) => w.route), [
        AppRoutes.employeeHome,
        AppRoutes.managerTeamDashboard,
        AppRoutes.hrHome,
      ]);
    });
  });

  group('WorkspaceSwitcher.hasExtras', () {
    test('false for roles with only the self-view', () {
      expect(WorkspaceSwitcher.hasExtras(UserRole.employee), isFalse);
      expect(WorkspaceSwitcher.hasExtras(UserRole.ops), isFalse);
      expect(WorkspaceSwitcher.hasExtras(UserRole.finance), isFalse);
    });

    test('true for manager / HR / admin roles', () {
      expect(WorkspaceSwitcher.hasExtras(UserRole.manager), isTrue);
      expect(WorkspaceSwitcher.hasExtras(UserRole.hr), isTrue);
      expect(WorkspaceSwitcher.hasExtras(UserRole.hrAdmin), isTrue);
      expect(WorkspaceSwitcher.hasExtras(UserRole.admin), isTrue);
    });
  });
}
