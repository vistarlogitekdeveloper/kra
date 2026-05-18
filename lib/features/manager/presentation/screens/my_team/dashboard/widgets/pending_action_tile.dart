import 'package:flutter/material.dart';

import '../../../../../../../core/constants/app_colors.dart';
import '../../../../../../../core/constants/app_strings.dart';
import '../../../../../../employee/presentation/widgets/_formatters.dart';
import '../../../../../../employee/presentation/widgets/deadline_chip.dart';
import '../../../../../data/models/pending_action.dart';

/// One row in the "Awaiting your review" list. Tappable — caller
/// supplies the navigation callback.
class PendingActionTile extends StatelessWidget {
  final PendingAction action;
  final VoidCallback onTap;
  const PendingActionTile({
    super.key,
    required this.action,
    required this.onTap,
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
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              _Avatar(name: action.employeeName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      action.employeeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (action.deadlineRemaining != null)
                DeadlineChip(
                  daysRemaining: action.deadlineRemaining!,
                  isOverdue: action.isOverdue,
                ),
              const SizedBox(width: 4),
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

  String _subtitle() {
    final code = action.employeeCode;
    final month = action.monthLabel;
    final submitted = action.submittedAt;
    final submittedFragment = submitted == null
        ? ''
        : ' • ${AppStrings.managerDashboardSubmittedAgo} '
            '${EmployeeFormatters.relativeTime(submitted)}';
    return '$code • $month$submittedFragment';
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  const _Avatar({required this.name});

  String _initials() {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '·';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primaryPurple.withValues(alpha: 0.12),
        border: Border.all(
          color: AppColors.primaryPurple.withValues(alpha: 0.4),
          width: 1.4,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: AppColors.primaryPurple,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
