import 'package:flutter/material.dart';

import '../../../../../../../core/constants/app_colors.dart';
import '../../../../../../../core/constants/app_strings.dart';
import '../../../../../../employee/presentation/widgets/_formatters.dart';

/// Tiny muted chip showing the employee's self-rating for context.
/// Sits directly below a `ScoreCell`'s input — the manager-rate spec
/// requires the self number to be visible "without scrolling, without
/// tapping" so the manager has the employee's frame of reference.
class SelfRatingChip extends StatelessWidget {
  final double? selfRating;
  final double maxScore;

  /// Optional remark from the employee — shown as a small comment icon
  /// the manager can long-press to expand. Hidden when null/empty.
  final String? selfRemark;

  const SelfRatingChip({
    super.key,
    required this.selfRating,
    required this.maxScore,
    this.selfRemark,
  });

  @override
  Widget build(BuildContext context) {
    final hasRating = selfRating != null;
    final label = hasRating
        ? '${AppStrings.managerRateSelfChipPrefix} '
            '${EmployeeFormatters.scoreOutOf(selfRating!, maxScore)}'
        : '${AppStrings.managerRateSelfChipPrefix} —';
    final hasRemark = selfRemark != null && selfRemark!.trim().isNotEmpty;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accentOrange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: hasRating
                  ? AppColors.accentOrange
                  : AppColors.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          if (hasRemark)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 11,
                color: AppColors.accentOrange,
              ),
            ),
        ],
      ),
    );

    if (!hasRemark) return chip;
    return GestureDetector(
      onLongPress: () => _showRemarkSheet(context),
      child: chip,
    );
  }

  void _showRemarkSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Employee comment',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accentOrange,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                selfRemark!,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.textPrimary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
