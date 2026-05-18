import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../../../core/constants/app_colors.dart';
import '../../../../../../../core/constants/app_strings.dart';
import '../../../../../../../core/router/app_router.dart';
import '../../../../../data/models/enums.dart';
import '../../../../../data/models/manager_stats.dart';
import '../../../../providers/manager_team_providers.dart';

/// 2×2 (phone) / 1×4 (tablet) KPI grid. Each card maps to a pre-
/// applied team-list filter — tap drives the user straight to the
/// scoped list.
class ManagerStatsGrid extends ConsumerWidget {
  final ManagerStats stats;
  const ManagerStatsGrid({super.key, required this.stats});

  void _goToList(WidgetRef ref, BuildContext context, ManagerTeamFilter f) {
    ref.read(managerTeamFilterProvider.notifier).setFilter(f);
    context.go(AppRoutes.managerTeamList);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = <Widget>[
      _StatCard(
        icon: Icons.groups_rounded,
        label: AppStrings.managerDashboardStatTotal,
        value: stats.totalReports.toString(),
        bg: AppColors.primaryPurpleSurface,
        fg: AppColors.primaryPurple,
        highlight: false,
        onTap: () => _goToList(ref, context, ManagerTeamFilter.all),
      ),
      _StatCard(
        icon: Icons.rate_review_rounded,
        label: AppStrings.managerDashboardStatPending,
        value: stats.pendingMyReview.toString(),
        bg: AppColors.accentOrange.withValues(alpha: 0.12),
        fg: AppColors.accentOrange,
        highlight: stats.pendingMyReview > 0,
        onTap: () =>
            _goToList(ref, context, ManagerTeamFilter.pendingMyReview),
      ),
      _StatCard(
        icon: Icons.check_circle_rounded,
        label: AppStrings.managerDashboardStatCompleted,
        value: stats.completedThisMonth.toString(),
        bg: AppColors.success.withValues(alpha: 0.12),
        fg: AppColors.success,
        highlight: false,
        onTap: () => _goToList(ref, context, ManagerTeamFilter.completed),
      ),
      _StatCard(
        icon: Icons.warning_amber_rounded,
        label: AppStrings.managerDashboardStatOverdue,
        value: stats.overdueReviews.toString(),
        bg: AppColors.accentRed.withValues(alpha: 0.12),
        fg: AppColors.accentRed,
        highlight: stats.overdueReviews > 0,
        onTap: () => _goToList(ref, context, ManagerTeamFilter.overdue),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          return GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: wide ? 4 : 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: wide ? 1.4 : 1.25,
            children: cards,
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color bg;
  final Color fg;
  final bool highlight;
  final VoidCallback onTap;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.bg,
    required this.fg,
    required this.highlight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: highlight ? fg.withValues(alpha: 0.4) : AppColors.divider,
              width: highlight ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: fg, size: 20),
              ),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: highlight ? fg : AppColors.textPrimary,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
