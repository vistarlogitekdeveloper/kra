import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '_formatters.dart';

/// Live weightage validator for the KRA template editor.
///
/// Shows X / 100% as a chip + a thin progress bar. Green when total
/// equals 100 (within an epsilon for decimal drift); red when it
/// undershoots/overshoots — paired with the form's submit-disabled rule.
class WeightageIndicator extends StatelessWidget {
  final double total;

  /// Same epsilon used by [KraTemplate.hasValidWeightage].
  static const double _epsilon = 0.01;

  const WeightageIndicator({super.key, required this.total});

  bool get _isValid => (total - 100).abs() < _epsilon;

  @override
  Widget build(BuildContext context) {
    final color = _isValid ? AppColors.success : AppColors.error;
    final progress = (total / 100).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(
            _isValid
                ? Icons.check_circle_rounded
                : Icons.error_outline_rounded,
            color: color,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isValid
                          ? AppStrings.weightageValidLabel
                          : AppStrings.weightageInvalidLabel,
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${HrFormatters.weightagePercent(total)} ${AppStrings.weightageOf} 100%',
                      style: TextStyle(
                        color: color,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor:
                        AppColors.textMuted.withValues(alpha: 0.18),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
