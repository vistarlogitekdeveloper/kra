import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/models/enums.dart';

/// Small coloured pill for a [ReviewState] — used on history cards, the
/// review detail header, and the home current-month strip. Colours come
/// from the AppColors brand palette, never raw `Color(0x…)`.
class ReviewStateBadge extends StatelessWidget {
  final ReviewState state;

  /// Renders the pill at a smaller size — used in dense layouts like
  /// the history strip cards. Default is the regular size.
  final bool compact;

  const ReviewStateBadge({
    super.key,
    required this.state,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(state);
    final vertical = compact ? 3.0 : 5.0;
    final horizontal = compact ? 8.0 : 10.0;
    final fontSize = compact ? 10.5 : 11.5;

    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.foreground.withValues(alpha: 0.18)),
      ),
      child: Text(
        state.displayName.toUpperCase(),
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: palette.foreground,
        ),
      ),
    );
  }

  static _StatePalette _paletteFor(ReviewState s) {
    switch (s) {
      case ReviewState.draft:
        return _StatePalette(
          foreground: AppColors.textSecondary,
          background: AppColors.divider.withValues(alpha: 0.6),
        );
      case ReviewState.inProgress:
        return _StatePalette(
          foreground: AppColors.accentOrange,
          background: AppColors.accentOrange.withValues(alpha: 0.12),
        );
      case ReviewState.employeeSubmittedAll:
        return _StatePalette(
          foreground: AppColors.primaryPurple,
          background: AppColors.primaryPurple.withValues(alpha: 0.10),
        );
      case ReviewState.managerRatedAll:
        return _StatePalette(
          foreground: AppColors.primaryPurpleDark,
          background: AppColors.primaryPurple.withValues(alpha: 0.16),
        );
      case ReviewState.finalized:
      case ReviewState.acknowledged:
        return _StatePalette(
          foreground: AppColors.success,
          background: AppColors.success.withValues(alpha: 0.12),
        );
    }
  }
}

class _StatePalette {
  final Color foreground;
  final Color background;
  const _StatePalette({required this.foreground, required this.background});
}
