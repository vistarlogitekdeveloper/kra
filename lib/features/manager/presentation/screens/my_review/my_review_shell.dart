import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_strings.dart';

/// "My Review" mode inner shell. Same 4-tab pattern as the Employee
/// shell — and in fact reuses the Employee screens directly via
/// app_router (see lib/features/manager/presentation/screens/my_review/README.md).
///
/// The only visual difference from the Employee shell is the active-
/// tab indicator colour: accentOrange to match the My Review mode
/// pill.
class MyReviewShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const MyReviewShell({super.key, required this.navigationShell});

  static const _tabs = [
    _Tab(
      label: AppStrings.employeeShellHome,
      icon: Icons.home_rounded,
    ),
    _Tab(
      label: AppStrings.employeeShellSelfRate,
      icon: Icons.rate_review_outlined,
    ),
    _Tab(
      label: AppStrings.employeeShellHistory,
      icon: Icons.history_rounded,
    ),
    _Tab(
      label: AppStrings.employeeShellProfile,
      icon: Icons.person_outline_rounded,
    ),
  ];

  void _goBranch(int index) {
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
      bottomNavigationBar: _MyReviewBottomNav(
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

class _MyReviewBottomNav extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onTap;
  const _MyReviewBottomNav({
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
            color: AppColors.accentOrange.withValues(alpha: 0.10),
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
              for (int i = 0; i < MyReviewShell._tabs.length; i++)
                _NavItem(
                  tab: MyReviewShell._tabs[i],
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
    // accentOrange to match the My Review mode pill — only visual
    // difference from the Employee module's bottom nav.
    final color = isActive ? AppColors.accentOrange : AppColors.textSecondary;
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
                        ? AppColors.accentOrange.withValues(alpha: 0.14)
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
