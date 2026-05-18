import 'package:flutter/material.dart';

import '../../../../../../../core/constants/app_colors.dart';
import '../../../../../../../core/constants/app_strings.dart';
import '../../../../../data/models/review_permissions.dart';

/// Compact warning card that appears above the review-detail content
/// when the manager-review deadline is within 3 days (or already
/// passed). Hidden otherwise — the deadline chip on the rate-screen
/// header carries the always-on cue.
class DeadlineWarningCard extends StatelessWidget {
  final ReviewPermissions permissions;
  const DeadlineWarningCard({super.key, required this.permissions});

  @override
  Widget build(BuildContext context) {
    if (!permissions.isUrgent && !permissions.isOverdue) {
      return const SizedBox.shrink();
    }
    final overdue = permissions.isOverdue;
    final accent =
        overdue ? AppColors.accentRed : AppColors.accentOrange;
    final daysRemaining = permissions.deadlineRemaining ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              overdue
                  ? Icons.warning_amber_rounded
                  : Icons.schedule_rounded,
              color: accent,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    overdue
                        ? AppStrings.managerRateDeadlinePassed
                        : AppStrings.managerRateDeadlineWarning,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                  if (!overdue) ...[
                    const SizedBox(height: 2),
                    Text(
                      '$daysRemaining '
                      '${daysRemaining == 1 ? "day" : "days"} '
                      'remaining',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
