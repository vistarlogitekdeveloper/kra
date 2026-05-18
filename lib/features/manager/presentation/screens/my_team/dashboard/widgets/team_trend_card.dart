import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../../../core/constants/app_colors.dart';
import '../../../../../../../core/constants/app_strings.dart';
import '../../../../../../../core/router/app_router.dart';
import '../../../../../../employee/presentation/widgets/_formatters.dart';
import '../../../../../data/models/manager_dashboard.dart';

/// Last-completed-cycle summary at the bottom of the dashboard.
/// Tappable — opens the team-history list scoped to that cycle.
class TeamTrendCard extends StatelessWidget {
  final TeamTrend trend;
  const TeamTrendCard({super.key, required this.trend});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.go(AppRoutes.managerTeamHistory),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        AppStrings.managerDashboardTrendTitle,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    Text(
                      trend.cycleName,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _MetricBlock(
                        label: AppStrings.managerDashboardTrendAverage,
                        value: EmployeeFormatters.percent(
                            trend.averageScore),
                        accent: AppColors.primaryPurple,
                      ),
                    ),
                    Expanded(
                      child: _MetricBlock(
                        label: AppStrings.managerDashboardTrendCompletion,
                        value: EmployeeFormatters.percent(
                            trend.completionRate * 100),
                        accent: AppColors.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(color: AppColors.divider, height: 1),
                const SizedBox(height: 14),
                if (trend.highest != null)
                  _PerformerRow(
                    label: AppStrings.managerDashboardTrendHighest,
                    name: trend.highest!.name,
                    score: trend.highest!.score,
                    accent: AppColors.success,
                    icon: Icons.trending_up_rounded,
                  ),
                if (trend.lowest != null) ...[
                  const SizedBox(height: 8),
                  _PerformerRow(
                    label: AppStrings.managerDashboardTrendLowest,
                    name: trend.lowest!.name,
                    score: trend.lowest!.score,
                    accent: AppColors.accentOrange,
                    icon: Icons.trending_down_rounded,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricBlock extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  const _MetricBlock({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppColors.textSecondary,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: accent,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

class _PerformerRow extends StatelessWidget {
  final String label;
  final String name;
  final double score;
  final Color accent;
  final IconData icon;

  const _PerformerRow({
    required this.label,
    required this.name,
    required this.score,
    required this.accent,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        Text(
          EmployeeFormatters.percent(score),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: accent,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}
