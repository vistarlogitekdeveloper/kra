import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_colors.dart';
import '../constants/app_strings.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import 'workspace_switcher.dart';

/// The left "☰" workspace menu for the signed-in user — or `null` when they
/// have only one workspace (a plain employee), so no hamburger / team option
/// ever appears for them.
///
/// Attach the result to a screen's `Scaffold.drawer`. Flutter then renders the
/// ☰ hamburger on that screen's AppBar automatically (and the drawer + button
/// live on the same Scaffold, so it always opens). Screens without an AppBar
/// open it with `Scaffold.of(context).openDrawer()`.
///
/// The menu is access-controlled: it lists only the areas the router would let
/// this role into — My KRA (always), My Team (managers), HR Admin (HR/admin) —
/// so the same widget works UI-wide for every login without per-role branching
/// at the call site.
Widget? workspaceDrawerFor(WidgetRef ref) {
  final auth = ref.watch(authStateProvider);
  if (auth is! AuthAuthenticated) return null;
  if (!WorkspaceSwitcher.hasExtras(auth.user.role)) return null;
  return const WorkspaceDrawer();
}

class WorkspaceDrawer extends ConsumerWidget {
  const WorkspaceDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final user = auth is AuthAuthenticated ? auth.user : null;
    final workspaces = user == null
        ? const <Workspace>[]
        : WorkspaceSwitcher.workspacesFor(user.role);
    final currentLocation = GoRouterState.of(context).matchedLocation;

    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primaryPurple,
                    AppColors.primaryPurpleLight,
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.fullName ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      user?.role.displayName ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
              child: Text(
                AppStrings.workspaceSwitchTitle.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  for (final w in workspaces)
                    _WorkspaceDrawerItem(
                      workspace: w,
                      isCurrent: _isCurrent(currentLocation, w.areaPrefix),
                      onTap: () {
                        Navigator.of(context).pop(); // close the drawer
                        if (!_isCurrent(currentLocation, w.areaPrefix)) {
                          context.go(w.route);
                        }
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _isCurrent(String location, String areaPrefix) =>
      location == areaPrefix || location.startsWith('$areaPrefix/');
}

class _WorkspaceDrawerItem extends StatelessWidget {
  final Workspace workspace;
  final bool isCurrent;
  final VoidCallback onTap;

  const _WorkspaceDrawerItem({
    required this.workspace,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isCurrent
            ? AppColors.primaryPurple.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCurrent
                    ? AppColors.primaryPurple.withValues(alpha: 0.30)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primaryPurple.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(workspace.icon,
                      color: AppColors.primaryPurple, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        workspace.label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        workspace.subtitle,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isCurrent)
                  const Icon(Icons.check_circle_rounded,
                      color: AppColors.primaryPurple, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
