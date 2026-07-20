import 'package:flutter/material.dart';

import '../constants/app_strings.dart';
import '../router/app_router.dart';
import '../../features/auth/data/models/user.dart';

/// Access-control source of truth for cross-role workspace navigation.
///
/// Every authenticated user HAS **My KRA** — the employee self-view — whatever
/// their role, and it is always first in this list. Role only ADDS workspaces on
/// top: a manager also gets **My Team**, HR/admin also get **HR Admin**.
/// [WorkspaceDrawer] renders the left "☰" menu from this list.
///
/// Note this is about what a role can REACH, not where it starts: HR-tier roles
/// land in the HR area on login (see [AppRoutes.dashboardForRole]) and come back
/// to My KRA through this switcher.
///
/// The list is derived from the same predicates the router's guards use
/// ([AppRoutes.canAccessManager] / [AppRoutes.canAccessHr]), so the menu can
/// only ever offer areas the router would actually let the user into.
class WorkspaceSwitcher {
  const WorkspaceSwitcher._();

  /// True when [user] has at least one workspace beyond My KRA — i.e. the
  /// "☰" menu is worth surfacing. Pure employees (and ops/finance) have only
  /// their own KRA, so callers hide the menu for them entirely.
  static bool hasExtras(User user) =>
      AppRoutes.canAccessManager(user.role, hasReports: user.hasReports) ||
      AppRoutes.canAccessHr(user.role);

  /// The ordered workspaces available to [user]. My KRA is always first.
  static List<Workspace> workspacesFor(User user) {
    return [
      const Workspace(
        label: AppStrings.workspaceMyKra,
        subtitle: AppStrings.workspaceMyKraSubtitle,
        icon: Icons.assignment_ind_rounded,
        route: AppRoutes.employeeHome,
        areaPrefix: AppRoutes.employeeDashboard, // '/employee'
      ),
      if (AppRoutes.canAccessManager(user.role, hasReports: user.hasReports))
        const Workspace(
          label: AppStrings.workspaceMyTeam,
          subtitle: AppStrings.workspaceMyTeamSubtitle,
          icon: Icons.groups_rounded,
          route: AppRoutes.managerTeamDashboard,
          areaPrefix: AppRoutes.managerDashboard, // '/manager'
        ),
      if (AppRoutes.canAccessHr(user.role))
        const Workspace(
          label: AppStrings.workspaceHrAdmin,
          subtitle: AppStrings.workspaceHrAdminSubtitle,
          icon: Icons.admin_panel_settings_rounded,
          route: AppRoutes.hrHome,
          areaPrefix: AppRoutes.hrDashboard, // '/hr'
        ),
    ];
  }
}

/// A single workspace destination in the switcher menu.
class Workspace {
  final String label;
  final String subtitle;
  final IconData icon;

  /// Navigation target passed to `context.go`.
  final String route;

  /// Route prefix used to detect whether this workspace is the current one
  /// (exact match or `$prefix/...`), mirroring the router's guard idiom.
  final String areaPrefix;

  const Workspace({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.route,
    required this.areaPrefix,
  });
}
