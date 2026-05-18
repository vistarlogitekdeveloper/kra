import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/connectivity_wrapper.dart';

/// Bottom-nav shell for the Employee module. Wraps a
/// [StatefulShellRoute.indexedStack] so each tab keeps its own
/// navigation stack — switching from a deep self-rate screen to
/// History and back preserves the form state.
///
/// Exposes the four canonical tabs:
///   0. Home        — personal dashboard
///   1. Self-Rate   — current month rating form
///   2. History     — all my past reviews
///   3. Profile     — view / edit own info
class EmployeeShellScreen extends ConsumerWidget {
  /// The shell-router-provided container that swaps children based on
  /// [StatefulNavigationShell.currentIndex].
  final StatefulNavigationShell navigationShell;

  const EmployeeShellScreen({
    super.key,
    required this.navigationShell,
  });

  static const _tabs = [
    _EmployeeTab(
      label: AppStrings.employeeShellHome,
      icon: Icons.home_rounded,
      activeIcon: Icons.home_rounded,
    ),
    _EmployeeTab(
      label: AppStrings.employeeShellSelfRate,
      icon: Icons.rate_review_outlined,
      activeIcon: Icons.rate_review_rounded,
    ),
    _EmployeeTab(
      label: AppStrings.employeeShellHistory,
      icon: Icons.history_rounded,
      activeIcon: Icons.history_rounded,
    ),
    _EmployeeTab(
      label: AppStrings.employeeShellProfile,
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
    ),
  ];

  void _goBranch(int index) {
    // initialLocation: true sends the user back to the root of a tab
    // when re-tapping its current icon — same UX as Instagram / X.
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

class _EmployeeTab {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _EmployeeTab({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}

class _BrandedBottomNav extends StatelessWidget {
  final List<_EmployeeTab> tabs;
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
              for (int i = 0; i < tabs.length; i++)
                _NavItem(
                  tab: tabs[i],
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
  final _EmployeeTab tab;
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
                  child: Icon(
                    isActive ? tab.activeIcon : tab.icon,
                    color: color,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tab.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        isActive ? FontWeight.w800 : FontWeight.w600,
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
