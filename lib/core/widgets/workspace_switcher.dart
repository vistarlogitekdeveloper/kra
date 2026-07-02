import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_colors.dart';
import '../constants/app_strings.dart';
import '../router/app_router.dart';
import '../../features/auth/data/models/user.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';

/// Cross-role navigation between the "workspaces" a user's role unlocks.
///
/// Every authenticated user's home is **My KRA** — the employee self-view —
/// regardless of role (see [AppRoutes.dashboardForRole]). Role only ADDS
/// extra workspaces on top: a manager also gets **My Team**, HR/admin also
/// get **HR Admin**. This switcher is how a user hops between them without
/// the self-view ever being replaced.
///
/// The list is derived from the same predicates the router's guards use
/// ([AppRoutes.canAccessManager] / [AppRoutes.canAccessHr]), so the switcher
/// can only ever offer areas the router would actually let the user into.
class WorkspaceSwitcher {
  const WorkspaceSwitcher._();

  /// True when [role] has at least one workspace beyond My KRA — i.e. the
  /// switcher is worth surfacing. Pure employees (and ops/finance) have only
  /// their own KRA, so callers can hide the trigger for them.
  static bool hasExtras(UserRole role) =>
      AppRoutes.canAccessManager(role) || AppRoutes.canAccessHr(role);

  /// The ordered workspaces available to [role]. My KRA is always first.
  static List<Workspace> workspacesFor(UserRole role) {
    return [
      const Workspace(
        label: AppStrings.workspaceMyKra,
        subtitle: AppStrings.workspaceMyKraSubtitle,
        icon: Icons.assignment_ind_rounded,
        route: AppRoutes.employeeHome,
        areaPrefix: AppRoutes.employeeDashboard, // '/employee'
      ),
      if (AppRoutes.canAccessManager(role))
        const Workspace(
          label: AppStrings.workspaceMyTeam,
          subtitle: AppStrings.workspaceMyTeamSubtitle,
          icon: Icons.groups_rounded,
          route: AppRoutes.managerTeamDashboard,
          areaPrefix: AppRoutes.managerDashboard, // '/manager'
        ),
      if (AppRoutes.canAccessHr(role))
        const Workspace(
          label: AppStrings.workspaceHrAdmin,
          subtitle: AppStrings.workspaceHrAdminSubtitle,
          icon: Icons.admin_panel_settings_rounded,
          route: AppRoutes.hrHome,
          areaPrefix: AppRoutes.hrDashboard, // '/hr'
        ),
    ];
  }

  /// Opens the workspace picker as a modal bottom sheet. No-op when the user
  /// isn't authenticated or has no extra workspaces (nothing to switch to).
  static Future<void> show(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(authStateProvider);
    if (auth is! AuthAuthenticated) return;
    final role = auth.user.role;
    final workspaces = workspacesFor(role);
    if (workspaces.length < 2) return;

    final currentLocation = GoRouterState.of(context).matchedLocation;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  AppStrings.workspaceSwitchTitle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              for (final w in workspaces)
                _WorkspaceTile(
                  workspace: w,
                  isCurrent: _isCurrent(currentLocation, w.areaPrefix),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    if (!_isCurrent(currentLocation, w.areaPrefix)) {
                      context.go(w.route);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _isCurrent(String location, String areaPrefix) =>
      location == areaPrefix || location.startsWith('$areaPrefix/');
}

/// A single workspace destination in the switcher.
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

class _WorkspaceTile extends StatelessWidget {
  final Workspace workspace;
  final bool isCurrent;
  final VoidCallback onTap;

  const _WorkspaceTile({
    required this.workspace,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isCurrent
            ? AppColors.primaryPurple.withValues(alpha: 0.08)
            : AppColors.background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isCurrent
                    ? AppColors.primaryPurple.withValues(alpha: 0.35)
                    : AppColors.divider,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primaryPurple.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(workspace.icon,
                      color: AppColors.primaryPurple, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        workspace.label,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        workspace.subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isCurrent)
                  const Icon(Icons.check_circle_rounded,
                      color: AppColors.primaryPurple, size: 20)
                else
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textMuted, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
