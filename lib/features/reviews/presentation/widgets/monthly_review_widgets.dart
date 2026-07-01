import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/models/monthly_review.dart';
import '../../data/models/review_stage.dart';
import '../../data/models/stage_status.dart';

/// Brand colour for a stage given its status within a review.
Color stageColor(StageStatus status) {
  switch (status) {
    case StageStatus.submitted:
      return AppColors.success;
    case StageStatus.inProgress:
      return AppColors.accentOrange;
    case StageStatus.pending:
      return AppColors.textMuted;
    case StageStatus.skipped:
      return AppColors.error;
  }
}

/// Compact pill naming a stage, tinted by [status].
class StagePill extends StatelessWidget {
  final ReviewStage stage;
  final StageStatus status;
  const StagePill({super.key, required this.stage, required this.status});

  @override
  Widget build(BuildContext context) {
    final color = stageColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(
        stage.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Horizontal selector of [ReviewPeriod]s (month chips).
class PeriodSelector extends StatelessWidget {
  final List<ReviewPeriod> periods;
  final ReviewPeriod selected;
  final ValueChanged<ReviewPeriod> onSelect;
  const PeriodSelector({
    super.key,
    required this.periods,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: periods.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p = periods[i];
          final active = p == selected;
          return InkWell(
            onTap: () => onSelect(p),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: active
                    ? AppColors.primaryPurple
                    : AppColors.primaryPurple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                p.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : AppColors.primaryPurple,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Five-segment pipeline progress strip for a review's stages.
class StageTimeline extends StatelessWidget {
  final MonthlyReview review;
  const StageTimeline({super.key, required this.review});

  @override
  Widget build(BuildContext context) {
    const stages = [
      ReviewStage.selfRating,
      ReviewStage.accountHrRating,
      ReviewStage.reportingManagerRating,
      ReviewStage.managementReview,
      ReviewStage.incentivePayout,
    ];
    return Row(
      children: [
        for (final s in stages)
          Expanded(
            child: Column(
              children: [
                _dot(s),
                const SizedBox(height: 4),
                Text(
                  '${s.pipelineIndex}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _dot(ReviewStage s) {
    final done = s.pipelineIndex < review.currentStage.pipelineIndex;
    final current = s == review.currentStage;
    final color = done
        ? AppColors.success
        : current
            ? AppColors.accentOrange
            : AppColors.divider;
    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 2),
    );
  }
}
