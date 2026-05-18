import 'package:flutter/material.dart';

import '../../../../../../../core/constants/app_colors.dart';

/// Last-3-months sparkline-style row of coloured dots. Each dot's
/// fill grades the score (purple = strong, orange = mid, red = weak,
/// grey = no data).
class ThreeMonthTrendStrip extends StatelessWidget {
  /// Oldest → newest. Length is expected to be ≤ 3; longer lists tail-
  /// truncate to keep the strip a fixed width.
  final List<double?> scores;
  const ThreeMonthTrendStrip({super.key, required this.scores});

  @override
  Widget build(BuildContext context) {
    final visible = scores.length > 3
        ? scores.sublist(scores.length - 3)
        : scores;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < visible.length; i++) ...[
          _Dot(score: visible[i]),
          if (i != visible.length - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final double? score;
  const _Dot({required this.score});

  Color _colorFor(double? s) {
    if (s == null) return AppColors.divider;
    if (s >= 80) return AppColors.success;
    if (s >= 60) return AppColors.accentOrange;
    return AppColors.accentRed;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _colorFor(score),
      ),
    );
  }
}
