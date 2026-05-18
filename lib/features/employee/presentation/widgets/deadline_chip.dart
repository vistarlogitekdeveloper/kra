import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';

/// Small chip that surfaces "N days remaining" or "Overdue" — used on
/// the home current-month strip and on history cards for pending months.
///
/// Three colour tiers, all from the brand palette:
///   - red    → overdue (days < 0)
///   - orange → urgent (0 ≤ days ≤ 3)
///   - purple → comfortable (days > 3)
class DeadlineChip extends StatelessWidget {
  final int daysRemaining;
  final bool isOverdue;

  /// Optional alternate label — when supplied, overrides the default
  /// "N days remaining" copy. Used on the deadline banner.
  final String? label;

  const DeadlineChip({
    super.key,
    required this.daysRemaining,
    this.isOverdue = false,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _palette();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.foreground.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 13, color: palette.foreground),
          const SizedBox(width: 5),
          Text(
            label ?? _defaultLabel(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: palette.foreground,
            ),
          ),
        ],
      ),
    );
  }

  IconData get _icon {
    if (isOverdue || daysRemaining < 0) return Icons.warning_amber_rounded;
    if (daysRemaining <= 3) return Icons.schedule_rounded;
    return Icons.event_available_rounded;
  }

  String _defaultLabel() {
    if (isOverdue || daysRemaining < 0) return AppStrings.hrOverdue;
    final unit =
        daysRemaining == 1 ? AppStrings.deadlineDay : AppStrings.deadlineDays;
    return '$daysRemaining $unit';
  }

  _ChipPalette _palette() {
    if (isOverdue || daysRemaining < 0) {
      return _ChipPalette(
        foreground: AppColors.error,
        background: AppColors.error.withValues(alpha: 0.10),
      );
    }
    if (daysRemaining <= 3) {
      return _ChipPalette(
        foreground: AppColors.accentOrange,
        background: AppColors.accentOrange.withValues(alpha: 0.12),
      );
    }
    return _ChipPalette(
      foreground: AppColors.primaryPurple,
      background: AppColors.primaryPurple.withValues(alpha: 0.10),
    );
  }
}

class _ChipPalette {
  final Color foreground;
  final Color background;
  const _ChipPalette({required this.foreground, required this.background});
}
