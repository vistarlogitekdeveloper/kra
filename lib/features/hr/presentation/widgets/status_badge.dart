import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/models/review_cycle.dart';

/// Compact status chip used by [ReviewCycleCard] and the cycles list.
/// Three variants — DRAFT (muted gray), ACTIVE (success green),
/// CLOSED (neutral). Sized to read comfortably at a glance.
class StatusBadge extends StatelessWidget {
  final ReviewCycleStatus status;
  final bool small;

  const StatusBadge({
    super.key,
    required this.status,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _palette(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 8 : 10,
        vertical: small ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.fg.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: small ? 6 : 7,
            height: small ? 6 : 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.fg,
            ),
          ),
          SizedBox(width: small ? 5 : 6),
          Text(
            status.displayName,
            style: TextStyle(
              color: palette.fg,
              fontWeight: FontWeight.w700,
              fontSize: small ? 10.5 : 11.5,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  _BadgePalette _palette(ReviewCycleStatus s) {
    switch (s) {
      case ReviewCycleStatus.draft:
        return const _BadgePalette(
          bg: AppColors.primaryPurpleSurface,
          fg: AppColors.textSecondary,
        );
      case ReviewCycleStatus.active:
        return _BadgePalette(
          bg: AppColors.success.withValues(alpha: 0.10),
          fg: AppColors.success,
        );
      case ReviewCycleStatus.closed:
        return const _BadgePalette(
          bg: AppColors.primaryPurpleSurface,
          fg: AppColors.primaryPurple,
        );
    }
  }
}

class _BadgePalette {
  final Color bg;
  final Color fg;
  const _BadgePalette({required this.bg, required this.fg});
}
