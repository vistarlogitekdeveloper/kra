import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/router/app_router.dart';
import '../../../../../core/widgets/shimmer_skeletons.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';
import '../../../data/models/employee_dashboard.dart';
import '../../providers/employee_dashboard_providers.dart';
import '../../providers/my_profile_providers.dart';
import 'widgets/current_month_card.dart';
import 'widgets/deadline_banner.dart';
import 'widgets/greeting_header.dart';
import 'widgets/history_strip.dart';
import 'widgets/incentive_snapshot_card.dart';
import 'widgets/my_kras_summary_card.dart';

/// The employee's personal home screen — six stacked sections, each
/// with its own loading / error story so a single slow query doesn't
/// blank out the whole tab.
///
/// User identity (name, employee code, role) comes from the auth
/// provider — the dashboard endpoint doesn't carry a `user` block on
/// the new contract, and refetching what's already in memory would
/// just be wasteful.
///
/// Composition: the dashboard-driven sections (deadline banner, current
/// month card, incentive snapshot) each watch
/// [employeeDashboardProvider] and render their own loading skeleton
/// independently. The KRA summary and history strip already own their
/// own providers, so they continue to render in parallel even while
/// the dashboard call is in flight.
class EmployeeHomeScreen extends ConsumerWidget {
  const EmployeeHomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(employeeDashboardProvider);
    try {
      await ref.read(employeeDashboardProvider.future);
    } catch (_) {
      // Each section surfaces its own error via the listenable.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final user = authState is AuthAuthenticated ? authState.user : null;
    final fullName = user?.fullName ?? 'there';
    // Auth's User model doesn't carry employeeCode (the dashboard
    // contract dropped its `user` block, and /auth/me doesn't expose
    // the code either). Pull it from the profile provider when
    // available; fall back to empty so the greeting renders cleanly
    // during the first-paint window before the profile call lands.
    final employeeCode = ref.watch(
      myProfileProvider.select(
        (a) => a.maybeWhen(
          data: (p) => p.employeeCode,
          orElse: () => '',
        ),
      ),
    );
    final roleLabel = user?.role.displayName ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primaryPurple,
          onRefresh: () => _refresh(ref),
          child: ListView(
            // Always-scrollable so RefreshIndicator works even when the
            // body would otherwise be too short to overscroll.
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              GreetingHeader(
                name: _firstName(fullName),
                employeeCode: employeeCode,
                roleLabel: roleLabel,
              ),
              const _DeadlineBannerSection(),
              const _CurrentMonthSection(),
              const _MyKrasSection(),
              const _HistoryStripSection(),
              const _IncentiveSection(),
            ],
          ),
        ),
      ),
    );
  }

  String _firstName(String fullName) {
    if (fullName.trim().isEmpty) return 'there';
    return fullName.trim().split(' ').first;
  }
}

// ─────────────────────────────────────────────────────────────────────
// Section 1: Deadline banner (dashboard-driven, conditional)
// ─────────────────────────────────────────────────────────────────────

class _DeadlineBannerSection extends ConsumerWidget {
  static const int _bannerThresholdDays = 3;

  const _DeadlineBannerSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(employeeDashboardProvider);
    return dashboardAsync.maybeWhen(
      data: (dashboard) {
        // Don't nag once the employee has already submitted everything for
        // the cycle — the monthly deadline only matters while work is open.
        final submittedAll =
            dashboard.scorecard?.state.hasSubmittedAll ?? false;
        final days = dashboard.selfRatingDaysRemaining;
        final showBanner = !submittedAll &&
            days != null &&
            (dashboard.isSelfRatingOverdue || days <= _bannerThresholdDays);
        if (!showBanner) return const SizedBox.shrink();
        return DeadlineBanner(
          daysRemaining: days,
          isOverdue: dashboard.isSelfRatingOverdue,
          onTap: () => context.go(AppRoutes.employeeSelfRate),
        );
      },
      // Loading / error states for the banner don't add value — the
      // banner is conditional anyway, so an absence is the same UX as
      // a shimmer. Keep it quiet.
      orElse: () => const SizedBox.shrink(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Section 2: Current month card (dashboard-driven, always rendered)
// ─────────────────────────────────────────────────────────────────────

class _CurrentMonthSection extends ConsumerWidget {
  const _CurrentMonthSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(employeeDashboardProvider);
    return dashboardAsync.when(
      loading: () => const _SectionLoading(),
      error: (e, _) => _SectionError(
        message: e.toString(),
        onRetry: () => ref.invalidate(employeeDashboardProvider),
      ),
      data: (dashboard) => CurrentMonthCard(
        cycle: dashboard.cycle,
        currentMonth: dashboard.currentMonth,
        scorecard: dashboard.scorecard,
        onPrimaryAction: () => _onCurrentMonthAction(context, dashboard),
      ),
    );
  }

  /// Routes the current-month CTA to whichever screen makes sense for
  /// the active state.
  void _onCurrentMonthAction(
      BuildContext context, EmployeeDashboard dashboard) {
    final scorecard = dashboard.scorecard;
    if (scorecard == null) {
      context.go(AppRoutes.employeeSelfRate);
      return;
    }
    if (!scorecard.state.hasSubmittedAll) {
      context.go(AppRoutes.employeeSelfRate);
      return;
    }
    if (scorecard.reviewId.isEmpty) {
      context.go(AppRoutes.employeeHistory);
      return;
    }
    context.go(AppRoutes.employeeReviewDetail(scorecard.reviewId));
  }
}

// ─────────────────────────────────────────────────────────────────────
// Section 3: My KRAs (independent provider — renders without dashboard)
// ─────────────────────────────────────────────────────────────────────

class _MyKrasSection extends ConsumerWidget {
  const _MyKrasSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Pull the cycle id from the dashboard payload when it lands —
    // otherwise pass `null` and let MyKrasSummaryCard fall back to a
    // shimmer. The KRA list does its own loading state once it has an id.
    final cycleId = ref.watch(
      employeeDashboardProvider.select(
        (a) => a.maybeWhen(data: (d) => d.cycle?.id, orElse: () => null),
      ),
    );
    return MyKrasSummaryCard(cycleId: cycleId);
  }
}

// ─────────────────────────────────────────────────────────────────────
// Section 4: History strip (independent provider)
// ─────────────────────────────────────────────────────────────────────

class _HistoryStripSection extends ConsumerWidget {
  const _HistoryStripSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return HistoryStrip(
      onTapReview: (id) => context.go(AppRoutes.employeeReviewDetail(id)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Section 5: Incentive snapshot (dashboard-driven, conditional)
// ─────────────────────────────────────────────────────────────────────

class _IncentiveSection extends ConsumerWidget {
  const _IncentiveSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(employeeDashboardProvider);
    return dashboardAsync.when(
      loading: () => const _SectionLoading(),
      // The incentive section's failure is non-fatal — silently hide
      // rather than block the rest of the home screen.
      error: (_, __) => const SizedBox.shrink(),
      data: (dashboard) {
        if (dashboard.incentive == null) return const SizedBox.shrink();
        return IncentiveSnapshotCard(
          incentive: dashboard.incentive!,
          onTap: () => context.go(AppRoutes.employeeHistory),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Shared per-section placeholders
// ─────────────────────────────────────────────────────────────────────

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: DashboardCardSkeleton(),
    );
  }
}

class _SectionError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _SectionError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.error,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    AppStrings.errorGeneric,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: const Text(
                AppStrings.commonRetry,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
