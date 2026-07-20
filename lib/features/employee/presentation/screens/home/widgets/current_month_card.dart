import 'package:flutter/material.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../../data/models/employee_dashboard.dart';
import '../../../../data/models/enums.dart';
import '../../../widgets/_formatters.dart';

/// The big anchor card on the home screen — surfaces the current
/// month's review state with the most useful action attached.
///
/// Five visual variants, all driven from the same payload:
///   1. No active cycle  → muted "no active cycle" card
///   2. DRAFT / IN_PROGRESS  → brand-gradient hero + "Start rating →"
///   3. EMPLOYEE_SUBMITTED_ALL  → surface card + "View my submission"
///   4. MANAGER_RATED_ALL  → surface card with manager total + "View details"
///   5. FINALIZED / ACKNOWLEDGED → success accent + final total / incentive
class CurrentMonthCard extends StatelessWidget {
  final DashboardCycle? cycle;
  final DashboardCurrentMonth? currentMonth;
  final DashboardScorecard? scorecard;

  /// Tapped when the primary CTA is pressed (varies per variant —
  /// kicks off self-rate, opens submission, opens detail).
  final VoidCallback onPrimaryAction;

  /// Wins over [scorecard]'s state when supplied.
  ///
  /// [scorecard] comes from `/employee/dashboard`, which derives its state from
  /// the LEGACY `kra.reviews` table — but self-ratings are written to
  /// `kra.monthly_reviews`, which never updates it. So a completed self-rating
  /// still reported DRAFT and this card sat on "Self-rating pending". The home
  /// screen passes the state derived from the monthly review here instead.
  final ReviewState? stateOverride;

  const CurrentMonthCard({
    super.key,
    required this.cycle,
    required this.currentMonth,
    required this.scorecard,
    required this.onPrimaryAction,
    this.stateOverride,
  });

  @override
  Widget build(BuildContext context) {
    if (cycle == null) return const _NoActiveCycle();

    final state = stateOverride ?? scorecard?.state ?? ReviewState.draft;
    final monthLabel = currentMonth?.monthLabel ??
        EmployeeFormatters.monthYear(
          currentMonth?.monthDate ?? DateTime.now(),
        );

    switch (state) {
      case ReviewState.draft:
      case ReviewState.inProgress:
        return _DraftHero(
          monthLabel: monthLabel,
          onStartRating: onPrimaryAction,
        );
      case ReviewState.employeeSubmittedAll:
        return _SubmittedCard(
          monthLabel: monthLabel,
          selfAvgPct: scorecard?.selfAvgPct,
          onView: onPrimaryAction,
        );
      case ReviewState.managerRatedAll:
        return _ManagerRatedCard(
          monthLabel: monthLabel,
          managerAvgPct: scorecard?.managerAvgPct,
          onView: onPrimaryAction,
        );
      case ReviewState.finalized:
      case ReviewState.acknowledged:
        return _FinalizedCard(
          monthLabel: monthLabel,
          finalAvgPct: scorecard?.managerAvgPct ?? scorecard?.selfAvgPct,
          onView: onPrimaryAction,
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────
// Variants
// ─────────────────────────────────────────────────────────────────────

class _DraftHero extends StatelessWidget {
  final String monthLabel;
  final VoidCallback onStartRating;
  const _DraftHero({required this.monthLabel, required this.onStartRating});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primaryPurple,
              AppColors.primaryPurpleLight,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryPurple.withValues(alpha: 0.30),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              monthLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              AppStrings.homeCurrentMonthSelfPending,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onStartRating,
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text(
                  AppStrings.homeCurrentMonthStartRating,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primaryPurple,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubmittedCard extends StatelessWidget {
  final String monthLabel;
  final double? selfAvgPct;
  final VoidCallback onView;
  const _SubmittedCard({
    required this.monthLabel,
    required this.selfAvgPct,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final title = selfAvgPct == null
        ? AppStrings.homeCurrentMonthSelfRated
        : '${AppStrings.homeCurrentMonthSelfRated} • '
            '${EmployeeFormatters.percent(selfAvgPct!)} self-avg';
    return _SurfaceCard(
      monthLabel: monthLabel,
      title: title,
      titleColor: AppColors.textPrimary,
      icon: Icons.hourglass_top_rounded,
      iconColor: AppColors.accentOrange,
      ctaLabel: AppStrings.homeCurrentMonthViewSubmission,
      onCta: onView,
    );
  }
}

class _ManagerRatedCard extends StatelessWidget {
  final String monthLabel;
  final double? managerAvgPct;
  final VoidCallback onView;
  const _ManagerRatedCard({
    required this.monthLabel,
    required this.managerAvgPct,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final scoreLine = managerAvgPct == null
        ? AppStrings.homeCurrentMonthManagerReviewed
        : '${AppStrings.homeCurrentMonthManagerReviewed}: '
            '${EmployeeFormatters.percent(managerAvgPct!)}';
    return _SurfaceCard(
      monthLabel: monthLabel,
      title: scoreLine,
      titleColor: AppColors.textPrimary,
      icon: Icons.assignment_turned_in_rounded,
      iconColor: AppColors.primaryPurple,
      ctaLabel: AppStrings.homeCurrentMonthViewDetails,
      onCta: onView,
    );
  }
}

class _FinalizedCard extends StatelessWidget {
  final String monthLabel;
  final double? finalAvgPct;
  final VoidCallback onView;
  const _FinalizedCard({
    required this.monthLabel,
    required this.finalAvgPct,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final title = finalAvgPct == null
        ? AppStrings.homeCurrentMonthFinalized
        : '${AppStrings.homeCurrentMonthFinalized}: '
            '${EmployeeFormatters.percent(finalAvgPct!)}';
    return _SurfaceCard(
      monthLabel: monthLabel,
      title: title,
      titleColor: AppColors.success,
      icon: Icons.check_circle_rounded,
      iconColor: AppColors.success,
      ctaLabel: AppStrings.homeCurrentMonthViewDetails,
      onCta: onView,
    );
  }
}

class _NoActiveCycle extends StatelessWidget {
  const _NoActiveCycle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryPurple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.event_busy_rounded,
                color: AppColors.primaryPurple,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.homeNoActiveCycleTitle,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    AppStrings.homeNoActiveCycleMessage,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  final String monthLabel;
  final String title;
  final Color titleColor;
  final IconData icon;
  final Color iconColor;
  final String ctaLabel;
  final VoidCallback onCta;

  const _SurfaceCard({
    required this.monthLabel,
    required this.title,
    required this.titleColor,
    required this.icon,
    required this.iconColor,
    required this.ctaLabel,
    required this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    monthLabel,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                color: titleColor,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onCta,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryPurple,
                  side: BorderSide(
                    color:
                        AppColors.primaryPurple.withValues(alpha: 0.40),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  ctaLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
