import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../../../core/api/api_error.dart';
import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../../../../core/widgets/shimmer_box.dart';
import '../../../../../../core/widgets/shimmer_skeletons.dart';
import '../../../../../employee/presentation/widgets/deadline_chip.dart';
import '../../../../data/models/manager_dashboard.dart';
import '../../../providers/manager_dashboard_providers.dart';
import 'widgets/manager_greeting_card.dart';
import 'widgets/manager_stats_grid.dart';
import 'widgets/no_reports_empty_state.dart';
import 'widgets/pending_actions_list.dart';
import 'widgets/team_trend_card.dart';

/// Manager-mode home tab. Pull-to-refresh + single-fetch dashboard.
///
/// The `NO_DIRECT_REPORTS` error is treated as a *data state*, not a
/// failure — when the manager has no assignments yet, swap the whole
/// body for [NoReportsEmptyState] with a CTA to switch to "My Review".
class ManagerDashboardScreen extends ConsumerWidget {
  const ManagerDashboardScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(managerDashboardProvider);
    try {
      await ref.read(managerDashboardProvider.future);
    } catch (_) {
      // Error surfaces via the .when branch.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(managerDashboardProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        color: AppColors.primaryPurple,
        onRefresh: () => _refresh(ref),
        child: async.when(
          loading: () => const _DashboardLoading(),
          error: (e, _) {
            // `NO_DIRECT_REPORTS` is a structured "you don't have a
            // team yet" — render the empty-state, not the error view.
            if (e is ApiError && e.code == 'NO_DIRECT_REPORTS') {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [NoReportsEmptyState()],
              );
            }
            return _DashboardError(
              message: e.toString(),
              onRetry: () => ref.invalidate(managerDashboardProvider),
            );
          },
          data: (dashboard) => _DashboardBody(dashboard: dashboard),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Body
// ─────────────────────────────────────────────────────────────────────

class _DashboardBody extends StatelessWidget {
  final ManagerDashboard dashboard;
  const _DashboardBody({required this.dashboard});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 4, bottom: 28),
      children: [
        ManagerGreetingCard(manager: dashboard.manager),
        ManagerStatsGrid(stats: dashboard.stats),
        if (dashboard.activeCycle != null)
          _ActiveCycleCard(cycle: dashboard.activeCycle!),
        PendingActionsList(actions: dashboard.pendingActions),
        if (dashboard.lastCycleTrend != null)
          TeamTrendCard(trend: dashboard.lastCycleTrend!),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Active-cycle card (inline — small enough not to warrant its own file)
// ─────────────────────────────────────────────────────────────────────

class _ActiveCycleCard extends StatelessWidget {
  final ManagerActiveCycle cycle;
  const _ActiveCycleCard({required this.cycle});

  @override
  Widget build(BuildContext context) {
    final deadline = cycle.managerReviewDeadline;
    final deadlineText = deadline == null
        ? ''
        : DateFormat('d MMM yyyy').format(deadline);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryPurpleSurface,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.event_available_rounded,
                color: AppColors.primaryPurple,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    cycle.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    deadlineText.isEmpty
                        ? AppStrings.managerDashboardActiveCycle
                        : '${AppStrings.managerDashboardManagerDeadline}: '
                            '$deadlineText',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (cycle.deadlineRemaining != null)
              DeadlineChip(
                daysRemaining: cycle.deadlineRemaining!,
                isOverdue: cycle.deadlineRemaining! < 0,
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Loading / error placeholders
// ─────────────────────────────────────────────────────────────────────

class _DashboardLoading extends StatelessWidget {
  const _DashboardLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: const [
        ShimmerBox(height: 130, borderRadius: 20),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: DashboardCardSkeleton()),
            SizedBox(width: 12),
            Expanded(child: DashboardCardSkeleton()),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: DashboardCardSkeleton()),
            SizedBox(width: 12),
            Expanded(child: DashboardCardSkeleton()),
          ],
        ),
        SizedBox(height: 16),
        ShimmerBox(height: 78, borderRadius: 16),
        SizedBox(height: 22),
        ShimmerBox(height: 80, borderRadius: 16),
        SizedBox(height: 14),
        ShimmerBox(height: 80, borderRadius: 16),
      ],
    );
  }
}

class _DashboardError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _DashboardError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      children: [
        const Icon(
          Icons.error_outline_rounded,
          size: 48,
          color: AppColors.error,
        ),
        const SizedBox(height: 14),
        const Text(
          AppStrings.errorGeneric,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 22),
        Center(
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(AppStrings.commonRetry),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryPurple,
            ),
          ),
        ),
      ],
    );
  }
}
