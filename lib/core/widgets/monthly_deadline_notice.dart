import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/app_colors.dart';
import '../utils/monthly_deadlines.dart';

/// Always-visible deadline cue for a monthly rating window.
///
/// Shows the due date (e.g. "Self-rating deadline — due 7 Jun") plus a
/// countdown tail ("3 days left" / "Due today" / "Overdue"), tinted by
/// urgency: purple when comfortable, orange within 3 days, red once past.
///
/// Reminder only — it never blocks submission (the backend governs that).
/// Build the [deadline] from [MonthlyDeadlines] so every surface counts
/// down to the same dates.
class MonthlyDeadlineNotice extends StatelessWidget {
  final String title;
  final DateTime deadline;

  const MonthlyDeadlineNotice({
    super.key,
    required this.title,
    required this.deadline,
  });

  @override
  Widget build(BuildContext context) {
    final days = MonthlyDeadlines.daysRemaining(deadline);
    final overdue = days < 0;
    final urgent = !overdue && days <= 3;
    final color = overdue
        ? AppColors.error
        : (urgent ? AppColors.accentOrange : AppColors.primaryPurple);

    final dateLabel = DateFormat('d MMM').format(deadline);
    final tail = overdue
        ? 'Overdue'
        : days == 0
            ? 'Due today'
            : '$days ${days == 1 ? 'day' : 'days'} left';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(
            overdue ? Icons.warning_amber_rounded : Icons.event_outlined,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$title — due $dateLabel',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  TextSpan(
                    text: '  ·  $tail',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
