import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/connectivity_wrapper.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

/// Bottom-nav shell for the HR module, backed by
/// [StatefulShellRoute.indexedStack] so each tab keeps its own
/// navigation stack across switches — drilling into a templates form
/// and bouncing to Employees no longer loses the templates back-stack.
///
/// A side drawer provides access to Locations, Bulk Setup, Profile,
/// and Logout — modules outside the tab bar.
class HrShellScreen extends ConsumerWidget {
  /// The shell-router-provided container that swaps children based on
  /// [StatefulNavigationShell.currentIndex].
  final StatefulNavigationShell navigationShell;

  const HrShellScreen({super.key, required this.navigationShell});

  static const _tabs = [
    _HrTab(
      label: AppStrings.hrShellHome,
      icon: Icons.dashboard_rounded,
    ),
    _HrTab(
      label: AppStrings.hrShellEmployees,
      icon: Icons.groups_rounded,
    ),
    _HrTab(
      label: AppStrings.hrShellTemplates,
      icon: Icons.description_rounded,
    ),
    _HrTab(
      label: AppStrings.hrShellCycles,
      icon: Icons.event_available_rounded,
    ),
    _HrTab(
      label: AppStrings.hrShellReports,
      icon: Icons.insights_rounded,
    ),
  ];

  void _goBranch(int index) {
    // Re-tapping the current tab pops back to its root — same UX as
    // Instagram / X. The Employee shell follows the same pattern.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final user =
        authState is AuthAuthenticated ? authState.user : null;

    return ConnectivityWrapper(
      child: Scaffold(
        backgroundColor: AppColors.background,
        drawer: _HrDrawer(user: user, ref: ref),
        body: navigationShell,
        bottomNavigationBar: _BrandedBottomNav(
          tabs: _tabs,
          activeIndex: navigationShell.currentIndex,
          onTap: _goBranch,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Drawer
// ─────────────────────────────────────────────────────────

class _HrDrawer extends StatelessWidget {
  final dynamic user;
  final WidgetRef ref;
  const _HrDrawer({required this.user, required this.ref});

  @override
  Widget build(BuildContext context) {
    final name = (user?.fullName as String?) ?? 'HR Admin';
    final email = (user?.email as String?) ?? '';
    final roleLabel = (user?.role?.displayName as String?) ?? 'HR';

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
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.20),
                    ),
                    child: Text(
                      _initials(name),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.80),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      roleLabel,
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

            // ── Nav items ──
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  const _DrawerSectionLabel(title: 'Management'),
                  _DrawerItem(
                    icon: Icons.location_on_rounded,
                    label: AppStrings.hrDrawerLocations,
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go(AppRoutes.hrLocations);
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.group_add_rounded,
                    label: AppStrings.hrDrawerBulkSetup,
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go(AppRoutes.hrBulkSetup);
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.assignment_rounded,
                    label: AppStrings.hrDrawerAssignKras,
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go(AppRoutes.hrAssign);
                    },
                  ),
                  // Manager view — only renders for roles that can
                  // actually reach it. The router enforces access
                  // again, but a hidden link is cleaner than a
                  // bounce-back for users who never see it.
                  if (user != null &&
                      AppRoutes.canAccessManager(user.role))
                    _DrawerItem(
                      icon: Icons.swap_horiz_rounded,
                      label: AppStrings.hrDrawerSwitchToManager,
                      onTap: () {
                        Navigator.of(context).pop();
                        context.go(AppRoutes.managerTeamDashboard);
                      },
                    ),
                  const Divider(color: AppColors.divider, height: 24),
                  const _DrawerSectionLabel(title: 'Account'),
                  // No HR-specific profile screen exists yet — the
                  // drawer item used to no-op (just close the drawer)
                  // and confuse users. Hide it until /hr/profile is
                  // built; the drawer header already shows identity.
                  _DrawerItem(
                    icon: Icons.logout_rounded,
                    label: AppStrings.dashboardLogoutTooltip,
                    color: AppColors.error,
                    onTap: () {
                      Navigator.of(context).pop();
                      ref.read(authStateProvider.notifier).logout();
                    },
                  ),
                ],
              ),
            ),

            // ── Footer ──
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                AppStrings.appName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String full) {
    final parts = full.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _DrawerSectionLabel extends StatelessWidget {
  final String title;
  const _DrawerSectionLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: AppColors.textMuted,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fg = color ?? AppColors.textPrimary;
    return ListTile(
      leading: Icon(icon, color: fg, size: 22),
      title: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      onTap: onTap,
      horizontalTitleGap: 8,
      minLeadingWidth: 24,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Bottom nav
// ─────────────────────────────────────────────────────────

class _HrTab {
  final String label;
  final IconData icon;
  const _HrTab({
    required this.label,
    required this.icon,
  });
}

class _BrandedBottomNav extends StatelessWidget {
  final List<_HrTab> tabs;
  final int activeIndex;
  final ValueChanged<int> onTap;

  const _BrandedBottomNav({
    required this.tabs,
    required this.activeIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryPurple.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
        border: Border(
          top: BorderSide(
            color: AppColors.divider.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (int i = 0; i < tabs.length; i++)
                Expanded(
                  child: _NavItem(
                    tab: tabs[i],
                    active: i == activeIndex,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final _HrTab tab;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({
    required this.tab,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primaryPurple : AppColors.textMuted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.primaryPurple.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(tab.icon, color: color, size: 22),
              ),
              const SizedBox(height: 4),
              Text(
                tab.label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
