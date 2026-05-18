import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_strings.dart';

/// "My Team" mode inner shell — 4-tab bottom nav backed by a
/// `StatefulShellRoute.indexedStack`. Active-tab indicator uses
/// brand purple to match the My Team mode pill.
class MyTeamShell extends ConsumerWidget {
  /// Provided by go_router's `StatefulShellRoute.indexedStack`.
  final StatefulNavigationShell navigationShell;
  const MyTeamShell({super.key, required this.navigationShell});

  static const _tabs = [
    _Tab(
      label: AppStrings.managerTeamNavDashboard,
      icon: Icons.dashboard_rounded,
    ),
    _Tab(
      label: AppStrings.managerTeamNavTeam,
      icon: Icons.groups_rounded,
    ),
    _Tab(
      label: AppStrings.managerTeamNavHistory,
      icon: Icons.history_rounded,
    ),
    _Tab(
      label: AppStrings.managerTeamNavProfile,
      icon: Icons.person_outline_rounded,
    ),
  ];

  void _goBranch(int index) {
    // initialLocation: true → re-tap pops back to the branch root.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: navigationShell,
      bottomNavigationBar: _MyTeamBottomNav(
        activeIndex: navigationShell.currentIndex,
        onTap: _goBranch,
      ),
    );
  }
}

class _Tab {
  final String label;
  final IconData icon;
  const _Tab({required this.label, required this.icon});
}

class _MyTeamBottomNav extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onTap;
  const _MyTeamBottomNav({
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
            color: AppColors.primaryPurple.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (int i = 0; i < MyTeamShell._tabs.length; i++)
                _NavItem(
                  tab: MyTeamShell._tabs[i],
                  isActive: i == activeIndex,
                  onTap: () => onTap(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final _Tab tab;
  final bool isActive;
  final VoidCallback onTap;
  const _NavItem({
    required this.tab,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        isActive ? AppColors.primaryPurple : AppColors.textSecondary;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.primaryPurple.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(tab.icon, color: color, size: 22),
                ),
                const SizedBox(height: 4),
                Text(
                  tab.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                    color: color,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
