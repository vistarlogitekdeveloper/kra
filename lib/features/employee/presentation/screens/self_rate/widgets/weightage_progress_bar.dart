import 'package:flutter/material.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../widgets/_formatters.dart';

/// Sticky top bar inside the self-rate form. Shows the live weighted
/// total as the user drags sliders, with a progress fill that
/// re-colours by completeness.
///
/// Colour ramp (matches the deadline chip palette):
///   0–49 → muted grey (early)
///   50–79 → orange (mid)
///   80–100 → success green (done)
class WeightageProgressBar extends StatelessWidget {
  final double weightedTotalPct;
  final int filledCount;
  final int totalCount;

  const WeightageProgressBar({
    super.key,
    required this.weightedTotalPct,
    required this.filledCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final fillColor = _fillColorFor(weightedTotalPct);
    final pct = (weightedTotalPct / 100).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                AppStrings.selfRateLiveTotal,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              Text(
                EmployeeFormatters.percent(weightedTotalPct),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: fillColor,
                ),
              ),
              const SizedBox(width: 10),
              _CountChip(filled: filledCount, total: totalCount),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: AppColors.divider.withValues(alpha: 0.6),
              valueColor: AlwaysStoppedAnimation<Color>(fillColor),
            ),
          ),
        ],
      ),
    );
  }

  Color _fillColorFor(double pct) {
    if (pct >= 80) return AppColors.success;
    if (pct >= 50) return AppColors.accentOrange;
    return AppColors.primaryPurpleLight;
  }
}

class _CountChip extends StatelessWidget {
  final int filled;
  final int total;
  const _CountChip({required this.filled, required this.total});

  @override
  Widget build(BuildContext context) {
    final isDone = filled >= total && total > 0;
    final fg = isDone ? AppColors.success : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$filled / $total',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: fg,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
