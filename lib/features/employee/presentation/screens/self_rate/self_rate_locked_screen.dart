import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/router/app_router.dart';
import '../../../data/models/my_review_detail.dart';
import '../../providers/employee_dashboard_providers.dart';
import '../../providers/self_rate_providers.dart';
import '../../widgets/_formatters.dart';
import '../../widgets/review_state_badge.dart';

/// Read-only screen shown when the user can no longer edit their
/// self-rating — either because they already submitted everything for
/// the month or because the cycle deadline has passed.
///
/// The screen surfaces two pieces of context that help orient the user:
///   1. *Why* they're locked out (submitted vs. deadline-closed)
///   2. *When* — the submission date if known, otherwise the deadline
///
/// CTA routes to the review detail so they can still see what they
/// submitted, plus a "Back to home" escape hatch.
class SelfRateLockedScreen extends ConsumerWidget {
  const SelfRateLockedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(selfRateProvider);
    final review = state.review;

    // Decide which "reason" line to show.
    final cycle = review?.reviewCycle;
    final deadlinePassed = cycle?.selfRatingDeadline != null &&
        cycle!.selfRatingDeadline!.isBefore(DateTime.now());
    final submittedAt =
        _firstSubmittedAt(review?.rows.expand((r) => r.monthlyScores));

    final reasonLine = deadlinePassed && submittedAt == null
        ? AppStrings.selfRateLockedPeriodClosed
        : AppStrings.selfRateLockedAwaitingManager;
    final dateLine = submittedAt != null
        ? '${AppStrings.selfRateLockedSubmittedOn} '
            '${EmployeeFormatters.date(submittedAt)}'
        : (cycle?.selfRatingDeadline != null
            ? '${AppStrings.selfRateLockedClosedOn} '
                '${EmployeeFormatters.date(cycle!.selfRatingDeadline!)}'
            : null);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          AppStrings.selfRateLockedTitle,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go(AppRoutes.employeeHome),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 1),
              const _LockIcon(),
              const SizedBox(height: 24),
              Text(
                reasonLine,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              if (dateLine != null) ...[
                const SizedBox(height: 8),
                Text(
                  dateLine,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
              if (review != null) ...[
                const SizedBox(height: 18),
                Center(child: ReviewStateBadge(state: review.state)),
              ],
              const Spacer(flex: 2),
              if (review != null)
                ElevatedButton(
                  onPressed: () =>
                      context.go(AppRoutes.employeeReviewDetail(review.id)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    AppStrings.selfRateViewSubmission,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () {
                  ref.invalidate(employeeDashboardProvider);
                  context.go(AppRoutes.employeeHome);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.divider),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  AppStrings.selfRateBackToHome,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Earliest self-submit timestamp across all the review's cells. Used
  /// to show "Submitted on …" rather than "Submitted in the abstract."
  static DateTime? _firstSubmittedAt(Iterable<MonthlyScore>? cells) {
    if (cells == null) return null;
    DateTime? earliest;
    for (final c in cells) {
      final t = c.selfSubmittedAt;
      if (t == null) continue;
      if (earliest == null || t.isBefore(earliest)) earliest = t;
    }
    return earliest;
  }
}

class _LockIcon extends StatelessWidget {
  const _LockIcon();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primaryPurple.withValues(alpha: 0.10),
        ),
        child: const Icon(
          Icons.lock_outline_rounded,
          color: AppColors.primaryPurple,
          size: 40,
        ),
      ),
    );
  }
}
