import 'package:flutter/material.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/models/my_review_detail.dart';

/// Horizontal chip strip for choosing which month to rate. Most users
/// only ever see the active month — the strip lets them peek at past
/// months (read-only) and confirms which one they're editing.
class MonthPickerChip extends StatelessWidget {
  final List<ReviewMonthRef> months;
  final String? activeMonthId;
  final ValueChanged<String> onSelect;

  const MonthPickerChip({
    super.key,
    required this.months,
    required this.activeMonthId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (months.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: months.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final month = months[i];
          final isActive = month.id == activeMonthId;
          final isLocked = month.status == ReviewMonthStatus.locked;
          return _Chip(
            label: month.monthLabel,
            isActive: isActive,
            isLocked: isLocked,
            onTap: isLocked ? null : () => onSelect(month.id),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isLocked;
  final VoidCallback? onTap;
  const _Chip({
    required this.label,
    required this.isActive,
    required this.isLocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg = isActive
        ? Colors.white
        : (isLocked ? AppColors.textMuted : AppColors.textPrimary);
    final Color bg = isActive
        ? AppColors.primaryPurple
        : (isLocked
            ? AppColors.divider.withValues(alpha: 0.4)
            : AppColors.surface);
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: isActive
              ? AppColors.primaryPurple
              : AppColors.divider,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLocked)
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Icon(Icons.lock_rounded, size: 12, color: fg),
                ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight:
                      isActive ? FontWeight.w800 : FontWeight.w700,
                  letterSpacing: 0.2,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
