import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../data/models/review_cycle.dart';
import '_formatters.dart';
import 'status_badge.dart';

/// Compact card representing a [ReviewCycle] in the cycles list. Shows
/// name, status, date range, and exposes action buttons for activating
/// (DRAFT → ACTIVE) or closing (ACTIVE → CLOSED).
class ReviewCycleCard extends StatelessWidget {
  final ReviewCycle cycle;
  final VoidCallback? onTap;
  final VoidCallback? onActivate;
  final VoidCallback? onClose;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const ReviewCycleCard({
    super.key,
    required this.cycle,
    this.onTap,
    this.onActivate,
    this.onClose,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cycle.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${HrFormatters.date(cycle.startDate)}  →  ${HrFormatters.date(cycle.endDate)}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(status: cycle.status),
                ],
              ),
              if (cycle.status == ReviewCycleStatus.active)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _DaysRemainingBar(daysRemaining: cycle.daysRemaining),
                ),
              const SizedBox(height: 12),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onActivate != null &&
                      cycle.status == ReviewCycleStatus.draft)
                    _ActionChip(
                      icon: Icons.play_arrow_rounded,
                      label: AppStrings.reviewCyclesActivate,
                      color: AppColors.success,
                      onTap: onActivate!,
                    ),
                  if (onClose != null &&
                      cycle.status == ReviewCycleStatus.active)
                    _ActionChip(
                      icon: Icons.lock_outline_rounded,
                      label: AppStrings.reviewCyclesClose,
                      color: AppColors.error,
                      onTap: onClose!,
                    ),
                  if (onEdit != null &&
                      cycle.status != ReviewCycleStatus.closed)
                    _ActionChip(
                      icon: Icons.edit_outlined,
                      label: AppStrings.commonEdit,
                      color: AppColors.primaryPurple,
                      onTap: onEdit!,
                    ),
                  if (onDelete != null)
                    _ActionChip(
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete',
                      color: AppColors.error,
                      onTap: onDelete!,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DaysRemainingBar extends StatelessWidget {
  final int daysRemaining;
  const _DaysRemainingBar({required this.daysRemaining});

  @override
  Widget build(BuildContext context) {
    final overdue = daysRemaining < 0;
    final color = overdue
        ? AppColors.error
        : (daysRemaining <= 7
            ? AppColors.accentOrange
            : AppColors.primaryPurple);
    final label = overdue
        ? AppStrings.hrHomeCycleEnded
        : '$daysRemaining ${daysRemaining == 1 ? AppStrings.hrHomeDayRemaining : AppStrings.hrHomeDaysRemaining}';
    return Row(
      children: [
        Icon(Icons.event_outlined, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
