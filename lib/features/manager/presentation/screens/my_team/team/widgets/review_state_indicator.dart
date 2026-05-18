import 'package:flutter/material.dart';

import '../../../../../../../core/constants/app_colors.dart';
import '../../../../../../../core/constants/app_strings.dart';
import '../../../../../../employee/data/models/enums.dart';
import '../../../../../../employee/presentation/widgets/_formatters.dart';
import '../../../../../data/models/team_member.dart';

/// Trailing widget on the team list tile. Shows a state-badge + the
/// most-current score, with manager-specific copy that differs from
/// the employee-side badge:
///   - DRAFT/NOT_SUBMITTED → "Not Started"
///   - IN_PROGRESS → "In Progress (Employee)"
///   - EMPLOYEE_SUBMITTED_ALL → "Ready for Review" (CTA-styled purple)
///   - MANAGER_RATED_ALL → "You Rated"
///   - FINALIZED/ACKNOWLEDGED → "Finalized"
///   - OVERDUE flag wins regardless of state
class ReviewStateIndicator extends StatelessWidget {
  final TeamMember member;
  const ReviewStateIndicator({super.key, required this.member});

  @override
  Widget build(BuildContext context) {
    final palette = _palette();
    final scoreText = _scoreText();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: palette.foreground.withValues(alpha: 0.18),
            ),
          ),
          child: Text(
            palette.label.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: palette.foreground,
            ),
          ),
        ),
        if (scoreText != null) ...[
          const SizedBox(height: 4),
          Text(
            scoreText,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ],
    );
  }

  _StatePalette _palette() {
    if (member.isOverdue) {
      return _StatePalette(
        label: AppStrings.managerTeamStateOverdue,
        foreground: AppColors.accentRed,
        background: AppColors.accentRed.withValues(alpha: 0.10),
      );
    }
    switch (member.reviewState) {
      case ReviewState.draft:
        return _StatePalette(
          label: AppStrings.managerTeamStateNotStarted,
          foreground: AppColors.textSecondary,
          background: AppColors.divider.withValues(alpha: 0.6),
        );
      case ReviewState.inProgress:
        return _StatePalette(
          label: AppStrings.managerTeamStateInProgress,
          foreground: AppColors.accentOrange,
          background:
              AppColors.accentOrange.withValues(alpha: 0.12),
        );
      case ReviewState.employeeSubmittedAll:
        return _StatePalette(
          label: AppStrings.managerTeamStateReadyForReview,
          foreground: AppColors.primaryPurple,
          background: AppColors.primaryPurple.withValues(alpha: 0.14),
        );
      case ReviewState.managerRatedAll:
        return _StatePalette(
          label: AppStrings.managerTeamStateYouRated,
          foreground: AppColors.success,
          background: AppColors.success.withValues(alpha: 0.12),
        );
      case ReviewState.finalized:
      case ReviewState.acknowledged:
        return _StatePalette(
          label: AppStrings.managerTeamStateFinalized,
          foreground: AppColors.success,
          background: AppColors.success.withValues(alpha: 0.10),
        );
    }
  }

  String? _scoreText() {
    // Show the most-current score the manager cares about, in order
    // of preference: final > manager > self.
    final score =
        member.finalTotal ?? member.managerTotal ?? member.selfTotal;
    if (score == null) return null;
    return EmployeeFormatters.percent(score);
  }
}

class _StatePalette {
  final String label;
  final Color foreground;
  final Color background;
  const _StatePalette({
    required this.label,
    required this.foreground,
    required this.background,
  });
}
