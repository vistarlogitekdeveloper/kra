import 'package:flutter/material.dart';

import '../../../../../../../core/constants/app_colors.dart';
import '../../../../../../../core/constants/app_strings.dart';
import '../../../../../../employee/data/models/enums.dart';
import '../../../../../../employee/presentation/widgets/_formatters.dart';
import '../../../../../data/models/monthly_score.dart';
import 'self_rating_chip.dart';

/// Disabled twin of [ScoreCell]. Used when:
///   - The month's status isn't OPEN (`LOCKED` → "Locked" pill)
///   - The row's source is FEED (auto-filled by Ops/Finance)
///   - The cell was marked N/A by the employee
///
/// Renders a flat, non-interactive display of the manager rating (if
/// any) plus the self-rating context chip below.
class ReadonlyScoreCell extends StatelessWidget {
  final MonthlyScore cell;
  final double maxScore;
  final bool isFeedRow;

  const ReadonlyScoreCell({
    super.key,
    required this.cell,
    required this.maxScore,
    this.isFeedRow = false,
  });

  @override
  Widget build(BuildContext context) {
    final reason = _reason();
    final value = cell.managerRating == null
        ? '—'
        : EmployeeFormatters.scoreOutOf(cell.managerRating!, maxScore);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.divider.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.divider),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: cell.managerRating == null
                      ? AppColors.textMuted
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                reason,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        SelfRatingChip(
          selfRating: cell.selfRating,
          maxScore: maxScore,
          selfRemark: cell.selfRemark,
        ),
      ],
    );
  }

  String _reason() {
    if (cell.isNotApplicable) return 'N/A';
    if (isFeedRow) return AppStrings.managerRateReadOnlyAuto.toUpperCase();
    if (cell.monthStatus != ReviewMonthStatus.open) {
      return AppStrings.managerRateReadOnlyLocked.toUpperCase();
    }
    return '';
  }
}
