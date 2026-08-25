import 'package:flutter/material.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';

/// Sticky-style banner that surfaces an imminent self-rating deadline.
///
/// Visibility rules (handled by the caller — this widget always renders):
///   - hide entirely when more than 3 days remain
///   - orange variant for 1–3 days
///   - red variant when overdue
///
/// Tapping the banner navigates to the Self-Rate tab (the caller wires
/// [onTap] to context.go(AppRoutes.employeeSelfRate)).
class DeadlineBanner extends StatelessWidget {
  /// Days remaining (negative if past the deadline). The banner uses
  /// this for both the icon variant and the message construction.
  final int daysRemaining;

  /// Server-computed flag — preferred over `daysRemaining < 0` so the
  /// backend can apply business rules (grace period, holiday-skipping
  /// etc.) without the client re-implementing them.
  final bool isOverdue;

  /// Which month is due, e.g. "Aug '26". Named in the message because the KRA
  /// sheet covers a QUARTER: an employee who had rated the quarter's first
  /// month read an unqualified "Self-rating overdue" as a bug rather than as a
  /// different month being outstanding. Null falls back to the old wording.
  final String? monthLabel;

  /// True when the month's Self scores are already entered but the rating was
  /// never submitted. Same deadline, different problem — and telling someone
  /// who filled in the whole column that it is merely "overdue" reads as the
  /// app having lost their work.
  final bool ratedButNotSubmitted;

  final VoidCallback? onTap;

  const DeadlineBanner({
    super.key,
    required this.daysRemaining,
    required this.isOverdue,
    this.monthLabel,
    this.ratedButNotSubmitted = false,
    this.onTap,
  });

  Color get _bg => isOverdue ? AppColors.accentRed : AppColors.accentOrange;
  IconData get _icon =>
      isOverdue ? Icons.error_outline_rounded : Icons.access_time_rounded;

  String _message() {
    final month = monthLabel;
    if (month == null) {
      // No month to name (the caller could not resolve one) — the original
      // wording, so the banner never degrades to a dangling label.
      if (isOverdue) return AppStrings.deadlineOverdue;
      final unit =
          daysRemaining == 1 ? AppStrings.deadlineDay : AppStrings.deadlineDays;
      return '${AppStrings.deadlineSelfRatingClosesIn} $daysRemaining $unit';
    }
    if (ratedButNotSubmitted) return AppStrings.deadlineUnsubmittedFor(month);
    if (isOverdue) return AppStrings.deadlineOverdueFor(month);
    return AppStrings.deadlineClosesInFor(month, daysRemaining);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: _bg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(_icon, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _message(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
