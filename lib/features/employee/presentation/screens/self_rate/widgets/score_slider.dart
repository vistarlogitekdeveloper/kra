import 'package:flutter/material.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../widgets/_formatters.dart';

/// Score selector for one cell. Combines a slider (coarse) with a
/// "N/A" toggle (skips the cell). Values snap to half-points so the
/// thumb rolls smoothly between integer and 0.5 increments — most
/// real rubrics use 0.5-step grading.
class ScoreSlider extends StatelessWidget {
  final double? value;
  final double maxScore;
  final bool isNotApplicable;
  final ValueChanged<double> onChanged;

  /// Fires after the user releases the thumb (vs. continuously while
  /// dragging). Used by the parent to commit the value rather than
  /// rebuild on every micro-step.
  final ValueChanged<double>? onChangeEnd;

  final ValueChanged<bool> onToggleNotApplicable;

  /// Marks the field as showing a validation error — paints the
  /// slider and value pill in `AppColors.error` to draw the eye.
  final bool hasError;

  const ScoreSlider({
    super.key,
    required this.value,
    required this.maxScore,
    required this.isNotApplicable,
    required this.onChanged,
    this.onChangeEnd,
    required this.onToggleNotApplicable,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = isNotApplicable;
    final effective = (value ?? 0).clamp(0.0, maxScore);
    final accent =
        hasError && !disabled ? AppColors.error : AppColors.primaryPurple;
    final label = isNotApplicable
        ? 'N/A'
        : value == null
            ? '—'
            : EmployeeFormatters.scoreOutOf(value!, maxScore);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: disabled
                    ? AppColors.textMuted
                    : (value == null
                        ? AppColors.textSecondary
                        : accent),
              ),
            ),
            const Spacer(),
            FilterChip(
              label: const Text(
                'N/A',
                style:
                    TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
              ),
              selected: isNotApplicable,
              showCheckmark: false,
              onSelected: onToggleNotApplicable,
              backgroundColor: AppColors.divider.withValues(alpha: 0.5),
              selectedColor:
                  AppColors.primaryPurple.withValues(alpha: 0.16),
              labelStyle: TextStyle(
                color: isNotApplicable
                    ? AppColors.primaryPurple
                    : AppColors.textSecondary,
              ),
              side: BorderSide(
                color: isNotApplicable
                    ? AppColors.primaryPurple.withValues(alpha: 0.4)
                    : AppColors.divider,
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: disabled ? AppColors.textMuted : accent,
            inactiveTrackColor: AppColors.divider,
            thumbColor: disabled ? AppColors.textMuted : accent,
            overlayColor: accent.withValues(alpha: 0.12),
            valueIndicatorColor: accent,
            valueIndicatorTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
            overlayShape:
                const RoundSliderOverlayShape(overlayRadius: 22),
          ),
          child: Slider(
            value: effective.toDouble(),
            min: 0,
            max: maxScore,
            // Half-point snaps. `(maxScore*2).toInt()` divisions gives
            // 21 stops for a 10-point scale.
            divisions: (maxScore * 2).toInt().clamp(1, 100),
            label: EmployeeFormatters.scoreOutOf(effective, maxScore),
            onChanged: disabled ? null : onChanged,
            onChangeEnd: disabled ? null : onChangeEnd,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
              Text('Max',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}
