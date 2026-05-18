import 'package:flutter/material.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../data/models/my_review_detail.dart';
import '../../../widgets/_formatters.dart';

/// Compact visual showing how the manager's score for each KRA compares
/// to the employee's self-score, row by row. Two horizontal bars per
/// row — self (orange) above, manager (purple) below.
///
/// Uses [LinearProgressIndicator] under the hood so each bar respects
/// `maxScore` natively, without a custom painter.
class ScoreProgressionChart extends StatelessWidget {
  final MyReview review;
  const ScoreProgressionChart({super.key, required this.review});

  @override
  Widget build(BuildContext context) {
    final rows = review.rows.where((r) => r.monthlyScores.isNotEmpty).toList();
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Self vs Manager',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 12),
          for (final row in rows) ...[
            _RowBars(row: row),
            const SizedBox(height: 12),
          ],
          const _Legend(),
        ],
      ),
    );
  }
}

class _RowBars extends StatelessWidget {
  final ReviewRow row;
  const _RowBars({required this.row});

  double _avg(double? Function(MonthlyScore) pick) {
    final values = row.monthlyScores
        .where((c) => !c.isNotApplicable)
        .map(pick)
        .whereType<double>()
        .toList();
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  @override
  Widget build(BuildContext context) {
    final selfAvg = _avg((c) => c.selfRating);
    final managerAvg = _avg((c) => c.managerRating);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          row.templateItem?.name ?? '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        _Bar(
          value: selfAvg,
          maxValue: row.maxScore,
          color: AppColors.accentOrange,
        ),
        const SizedBox(height: 4),
        _Bar(
          value: managerAvg,
          maxValue: row.maxScore,
          color: AppColors.primaryPurple,
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final double value;
  final double maxValue;
  final Color color;
  const _Bar({
    required this.value,
    required this.maxValue,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pct = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: AppColors.divider.withValues(alpha: 0.6),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 50,
          child: Text(
            value <= 0
                ? '—'
                : EmployeeFormatters.scoreOutOf(value, maxValue),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: value <= 0 ? AppColors.textMuted : color,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _LegendDot(color: AppColors.accentOrange, label: 'Self'),
        SizedBox(width: 18),
        _LegendDot(color: AppColors.primaryPurple, label: 'Manager'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppColors.textSecondary,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}
