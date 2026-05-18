import 'package:flutter/material.dart';

import '../../../../../../../core/constants/app_colors.dart';
import '../../../../../../employee/data/models/enums.dart';
import '../../../../../data/models/manager_review_detail.dart';

/// Top-of-column header for the matrix table view. Shows the month
/// label + a tiny status icon when the month is locked. Compact —
/// designed for the narrow column widths the matrix uses.
class MonthColumnHeader extends StatelessWidget {
  final ManagerReviewMonth month;
  const MonthColumnHeader({super.key, required this.month});

  @override
  Widget build(BuildContext context) {
    final isLocked = month.status != ReviewMonthStatus.open;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            month.monthLabel.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: isLocked
                  ? AppColors.textMuted
                  : AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          if (isLocked) ...[
            const SizedBox(height: 3),
            const Icon(
              Icons.lock_rounded,
              size: 11,
              color: AppColors.textMuted,
            ),
          ],
        ],
      ),
    );
  }
}
