import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../data/models/enums.dart';
import '../providers/manager_dashboard_providers.dart';
import '../providers/manager_mode_provider.dart';
import 'mode_badge.dart';

/// Two-pill segmented control that sits directly below the
/// ManagerShellScreen's AppBar. Tap an inactive pill to switch modes.
///
/// Each pill carries an optional notification badge for "work pending
/// in the other mode" cues:
///   - "My Review" pill: shows a badge when the manager's own review
///     is due (selfRatingDaysRemaining ≤ 3 OR state=DRAFT/IN_PROGRESS).
///     Stage-4 we only have the dashboard's `stats` to reason about;
///     the review-mode badge is wired via the employee dashboard
///     provider inside the actual badge widget — done in Stage 5.
///   - "My Team" pill: shows a badge when stats.pendingMyReview > 0
///     OR stats.overdueReviews > 0.
class ModeSegmentedSwitcher extends ConsumerWidget {
  const ModeSegmentedSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(managerModeProvider);
    final dashboardAsync = ref.watch(managerDashboardProvider);
    final teamBadgeCount = dashboardAsync.maybeWhen(
      data: (d) => d.stats.pendingMyReview + d.stats.overdueReviews,
      orElse: () => 0,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider, width: 1.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: _ModePill(
                label: AppStrings.managerModeMyTeam,
                isActive: mode == ManagerMode.myTeam,
                activeColor: AppColors.primaryPurple,
                badge: mode == ManagerMode.myReview && teamBadgeCount > 0
                    ? ModeBadge(count: teamBadgeCount)
                    : null,
                onTap: () =>
                    ref.read(managerModeProvider.notifier).toMyTeam(),
              ),
            ),
            Expanded(
              child: _ModePill(
                label: AppStrings.managerModeMyReview,
                isActive: mode == ManagerMode.myReview,
                activeColor: AppColors.accentOrange,
                // The review-mode badge would read the employee
                // dashboard provider — wire it via a small consumer
                // inside the pill once both flows exercise the same
                // signals. Hidden in Stage 4 to avoid double-fetch.
                badge: null,
                onTap: () =>
                    ref.read(managerModeProvider.notifier).toMyReview(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color activeColor;
  final Widget? badge;
  final VoidCallback onTap;

  const _ModePill({
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 11),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isActive ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight:
                      isActive ? FontWeight.w800 : FontWeight.w600,
                  color: isActive
                      ? Colors.white
                      : AppColors.textSecondary,
                  letterSpacing: 0.2,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                badge!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
