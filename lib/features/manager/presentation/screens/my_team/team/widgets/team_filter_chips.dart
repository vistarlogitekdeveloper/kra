import 'package:flutter/material.dart';

import '../../../../../../../core/constants/app_colors.dart';
import '../../../../../../../core/constants/app_strings.dart';
import '../../../../../data/models/enums.dart';

/// Horizontal scroll row of the 5 filter chips. Each chip shows a
/// count badge when the filter is populated in the current dataset.
class TeamFilterChips extends StatelessWidget {
  final ManagerTeamFilter active;
  final Map<String, int> counts;
  final ValueChanged<ManagerTeamFilter> onPick;

  const TeamFilterChips({
    super.key,
    required this.active,
    required this.counts,
    required this.onPick,
  });

  static const _order = [
    _ChipDef(
      filter: ManagerTeamFilter.all,
      label: AppStrings.managerTeamFilterAll,
      countKey: 'ALL',
    ),
    _ChipDef(
      filter: ManagerTeamFilter.pendingMyReview,
      label: AppStrings.managerTeamFilterPending,
      countKey: 'PENDING_MY_REVIEW',
    ),
    _ChipDef(
      filter: ManagerTeamFilter.completed,
      label: AppStrings.managerTeamFilterCompleted,
      countKey: 'COMPLETED',
    ),
    _ChipDef(
      filter: ManagerTeamFilter.notSubmitted,
      label: AppStrings.managerTeamFilterNotSubmitted,
      countKey: 'NOT_SUBMITTED',
    ),
    _ChipDef(
      filter: ManagerTeamFilter.overdue,
      label: AppStrings.managerTeamFilterOverdue,
      countKey: 'OVERDUE',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _order.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final def = _order[i];
          return _Chip(
            label: def.label,
            count: counts[def.countKey] ?? 0,
            isActive: active == def.filter,
            onTap: () => onPick(def.filter),
          );
        },
      ),
    );
  }
}

class _ChipDef {
  final ManagerTeamFilter filter;
  final String label;
  final String countKey;
  const _ChipDef({
    required this.filter,
    required this.label,
    required this.countKey,
  });
}

class _Chip extends StatelessWidget {
  final String label;
  final int count;
  final bool isActive;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.count,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isActive ? Colors.white : AppColors.textPrimary;
    final bg = isActive ? AppColors.primaryPurple : AppColors.surface;
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: isActive ? AppColors.primaryPurple : AppColors.divider,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight:
                      isActive ? FontWeight.w800 : FontWeight.w700,
                  color: fg,
                  letterSpacing: 0.2,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.white.withValues(alpha: 0.25)
                        : AppColors.primaryPurple
                            .withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: isActive
                          ? Colors.white
                          : AppColors.primaryPurple,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
