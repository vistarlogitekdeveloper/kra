import 'package:flutter/material.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../reviews/data/models/rating_access.dart';
import 'rating_access_handlers.dart';
import 'rating_access_message.dart';
import 'rating_access_stage_card.dart';

/// A loaded month: its title, the bulk actions, and one card per stage the
/// organisation's flow uses.
class RatingAccessMonthSection extends StatelessWidget {
  final RatingAccessMonth month;
  final DateTime now;
  final bool busy;
  final RatingAccessHandlers handlers;

  const RatingAccessMonthSection({
    super.key,
    required this.month,
    required this.now,
    required this.busy,
    required this.handlers,
  });

  @override
  Widget build(BuildContext context) {
    final stages = month.stagesInFlow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          month.period.label,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          AppStrings.ratingAccessRatedDuring(month.period.next.label),
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: (busy || stages.isEmpty)
                  ? null
                  : () => handlers.onOpenAll(month),
              icon: const Icon(Icons.more_time_rounded, size: 18),
              label: const Text(AppStrings.ratingAccessActionOpenAll),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                minimumSize: const Size(48, 48),
              ),
            ),
            if (month.hasOverrideInFlow)
              OutlinedButton.icon(
                onPressed: busy ? null : () => handlers.onResetAll(month),
                icon: const Icon(Icons.restore_rounded, size: 18),
                label: const Text(AppStrings.ratingAccessActionResetAll),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  iconColor: AppColors.primaryPurple,
                  minimumSize: const Size(48, 48),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (stages.isEmpty)
          const RatingAccessMessage(
            icon: Icons.event_busy_rounded,
            title: AppStrings.ratingAccessTitle,
            message: AppStrings.ratingAccessNoStages,
          ),
        for (final entry in stages) ...[
          RatingAccessStageCard(
            entry: entry,
            flow: month.reviewFlow,
            now: now,
            busy: busy,
            onOpenUntil: () => handlers.onOpenUntil(month, entry),
            onClose: () => handlers.onClose(month, entry),
            onUseDeadline: () => handlers.onUseDeadline(month, entry),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
