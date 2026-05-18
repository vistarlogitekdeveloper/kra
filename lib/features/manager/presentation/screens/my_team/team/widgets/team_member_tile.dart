import 'package:flutter/material.dart';

import '../../../../../../../core/constants/app_colors.dart';
import '../../../../../../../core/constants/app_strings.dart';
import '../../../../../data/models/team_member.dart';
import 'review_state_indicator.dart';
import 'three_month_trend_strip.dart';

/// One row in the team list. Two states: normal (tappable, navigates
/// to the member profile) and selection-mode (tappable to add/remove
/// from the bulk-approve selection; non-selectable members are dimmed
/// with an explanatory tooltip).
class TeamMemberTile extends StatelessWidget {
  final TeamMember member;

  /// Whether the list is currently in multi-select mode.
  final bool isSelectionMode;

  /// Whether THIS row is selected (only meaningful in selection mode).
  final bool isSelected;

  /// `false` when the member can't be bulk-approved (e.g. their
  /// review state isn't EMPLOYEE_SUBMITTED_ALL). Renders dimmed +
  /// disables tap in selection mode.
  final bool isSelectable;

  /// Tap handler — the screen decides what "tap" means based on the
  /// current selection mode.
  final VoidCallback onTap;

  const TeamMemberTile({
    super.key,
    required this.member,
    required this.isSelectionMode,
    required this.isSelected,
    required this.isSelectable,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = isSelectionMode && !isSelectable;
    final body = Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: disabled ? null : onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? AppColors.primaryPurple
                  : AppColors.divider,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Opacity(
            opacity: disabled ? 0.55 : 1,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isSelectionMode)
                  _SelectionCheckbox(
                    isSelected: isSelected,
                    enabled: isSelectable,
                  )
                else
                  _Avatar(name: member.fullName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        member.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _MetaRow(member: member),
                      const SizedBox(height: 8),
                      ThreeMonthTrendStrip(
                          scores: member.threeMonthTrend),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                ReviewStateIndicator(member: member),
              ],
            ),
          ),
        ),
      ),
    );

    if (disabled) {
      return Tooltip(
        message: AppStrings.managerTeamBulkOnlyPending,
        child: body,
      );
    }
    return body;
  }
}

class _MetaRow extends StatelessWidget {
  final TeamMember member;
  const _MetaRow({required this.member});

  @override
  Widget build(BuildContext context) {
    final fragments = <String>[
      member.employeeCode,
      if (member.role != null && member.role!.isNotEmpty)
        member.role!.replaceAll('_', ' '),
      if (member.projectLocation != null &&
          member.projectLocation!.isNotEmpty)
        member.projectLocation!,
    ];
    return Text(
      fragments.join(' • '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 11.5,
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    );
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

class _SelectionCheckbox extends StatelessWidget {
  final bool isSelected;
  final bool enabled;
  const _SelectionCheckbox({
    required this.isSelected,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.primaryPurple
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: enabled
              ? (isSelected
                  ? AppColors.primaryPurple
                  : AppColors.textSecondary)
              : AppColors.divider,
          width: 1.5,
        ),
      ),
      child: isSelected
          ? const Icon(
              Icons.check_rounded,
              size: 16,
              color: Colors.white,
            )
          : null,
    );
  }
}
