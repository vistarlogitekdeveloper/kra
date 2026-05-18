import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '_formatters.dart';

/// Small "score/max" chip used throughout the Employee module —
/// review history cards, comparison table cells, self-rate summary
/// rows. `null` score renders as an em-dash chip in muted grey.
///
/// Visual treatments via [tone]:
///   - [ScorePillTone.neutral]   → light divider grey (no opinion)
///   - [ScorePillTone.self]      → orange (employee voice)
///   - [ScorePillTone.manager]   → purple (manager voice)
///   - [ScorePillTone.finalised] → green (final / earned)
class ScorePill extends StatelessWidget {
  final double? score;
  final num? maxScore;
  final ScorePillTone tone;
  final bool small;
  final bool asPercentage;

  const ScorePill({
    super.key,
    required this.score,
    this.maxScore = 10,
    this.tone = ScorePillTone.neutral,
    this.small = false,
    this.asPercentage = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _palette(tone);
    final isEmpty = score == null;
    final label = isEmpty
        ? AppStrings.historyScoreNotApplicable
        : asPercentage
            ? EmployeeFormatters.percent(score!)
            : (maxScore == null
                ? EmployeeFormatters.score(score!)
                : EmployeeFormatters.scoreOutOf(score!, maxScore!));
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 8 : 10,
        vertical: small ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: isEmpty
            ? AppColors.divider.withValues(alpha: 0.5)
            : palette.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: small ? 11 : 12.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: isEmpty ? AppColors.textSecondary : palette.foreground,
        ),
      ),
    );
  }

  _PillPalette _palette(ScorePillTone t) {
    switch (t) {
      case ScorePillTone.neutral:
        return _PillPalette(
          foreground: AppColors.textPrimary,
          background: AppColors.divider.withValues(alpha: 0.6),
        );
      case ScorePillTone.self:
        return _PillPalette(
          foreground: AppColors.accentOrange,
          background: AppColors.accentOrange.withValues(alpha: 0.14),
        );
      case ScorePillTone.manager:
        return _PillPalette(
          foreground: AppColors.primaryPurple,
          background: AppColors.primaryPurple.withValues(alpha: 0.12),
        );
      case ScorePillTone.finalised:
        return _PillPalette(
          foreground: AppColors.success,
          background: AppColors.success.withValues(alpha: 0.14),
        );
    }
  }
}

enum ScorePillTone { neutral, self, manager, finalised }

class _PillPalette {
  final Color foreground;
  final Color background;
  const _PillPalette({required this.foreground, required this.background});
}
