import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/connectivity_wrapper.dart';
import '../../../../core/widgets/workspace_drawer.dart';

/// Bottom-nav shell for the HR module, backed by
/// [StatefulShellRoute.indexedStack] so each tab keeps its own
/// navigation stack across switches — drilling into a templates form
/// and bouncing to Employees no longer loses the templates back-stack.
///
/// The shared [WorkspaceDrawer] hangs off the Scaffold, giving HR admins the
/// same cross-workspace menu (My KRA / My Team / HR Admin) and log-out action
/// used everywhere else in the app.
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
      label: AppStrings.hrShellReviews,
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
    return ConnectivityWrapper(
      child: Scaffold(
        backgroundColor: AppColors.background,
        drawer: workspaceDrawerFor(ref),
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
