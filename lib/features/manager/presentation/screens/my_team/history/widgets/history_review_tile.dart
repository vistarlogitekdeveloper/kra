import 'package:flutter/material.dart';

import '../../../../../../../core/constants/app_colors.dart';
import '../../../../../../employee/presentation/widgets/_formatters.dart';
import '../../../../../../employee/presentation/widgets/review_state_badge.dart';
import '../../../../../data/models/previous_review.dart';

/// One row in the manager / team history list. Compact —
/// designed for the dense paginated list view.
class HistoryReviewTile extends StatelessWidget {
  final PreviousReview review;

  /// Optional employee-name label shown above the cycle in the
  /// combined view. Omitted on the per-employee history screen.
  final String? employeeName;

  final VoidCallback onTap;

  const HistoryReviewTile({
    super.key,
    required this.review,
    required this.onTap,
    this.employeeName,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (employeeName != null) ...[
                      Text(
                        employeeName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      review.cycleName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: employeeName == null ? 14 : 12.5,
                        fontWeight: employeeName == null
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: employeeName == null
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ReviewStateBadge(state: review.state, compact: true),
                        if (review.finalTotal != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            EmployeeFormatters.percent(
                                review.finalTotal!),
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.success,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
