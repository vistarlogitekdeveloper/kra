import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../../../core/widgets/workspace_drawer.dart';
import '../../../auth/data/models/user.dart';
import '../../../manager/presentation/screens/my_team/dashboard/widgets/no_reports_empty_state.dart';
import '../../../employee/presentation/widgets/_formatters.dart';
import '../../data/models/monthly_review.dart';
import '../../data/models/monthly_review_summary.dart';
import '../../data/models/stage_status.dart';
import '../providers/monthly_review_providers.dart';
import '../widgets/monthly_review_widgets.dart';

/// Role-adaptive monthly review dashboard. The list is scoped by the
/// provider (employee → own, manager → team, HR/finance/admin → all);
/// this screen renders it with a month selector and routes into each
/// review's stage screen.
class MonthlyReviewDashboardScreen extends ConsumerWidget {
  const MonthlyReviewDashboardScreen({super.key});

  String _title(UserRole? role) {
    switch (role) {
      case UserRole.employee:
      case UserRole.ops:
        return AppStrings.monthlyReviewsTitleSelf;
      case UserRole.manager:
      case UserRole.bdManager:
      case UserRole.warehouseMgr:
        return AppStrings.monthlyReviewsTitleTeam;
      default:
        return AppStrings.monthlyReviewsTitleAll;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentReviewScopeProvider)?.role;
    final periods = ref.watch(availablePeriodsProvider);
    final selected = ref.watch(selectedPeriodProvider) ?? periods.first;

    return Scaffold(
      backgroundColor: AppColors.background,
      // Left "☰" workspace menu — auto-rendered by the AppBar when a drawer is
      // present. Null (no menu) for plain employees who have only My KRA.
      drawer: workspaceDrawerFor(ref),
      appBar: AppBar(
        title: Text(_title(role)),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Column(
        children: [
          PeriodSelector(
            periods: periods,
            selected: selected,
            onSelect: (p) =>
                ref.read(selectedPeriodProvider.notifier).state = p,
          ),
          const Divider(height: 1, color: AppColors.divider),
          Expanded(child: _ReviewList(period: selected, role: role)),
        ],
      ),
    );
  }
}

class _ReviewList extends ConsumerWidget {
  final ReviewPeriod period;
  final UserRole? role;
  const _ReviewList({required this.period, required this.role});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(monthlyReviewListProvider(period));
    return RefreshIndicator(
      color: AppColors.primaryPurple,
      onRefresh: () async =>
          ref.invalidate(monthlyReviewListProvider(period)),
      child: listAsync.when(
        loading: () => const _DashboardSkeleton(),
        error: (e, _) {
          // A manager with zero direct reports (the roster load 403s) gets
          // the friendly no-team empty state with a jump into their own KRA
          // — never a raw 403 on the dashboard they land next to.
          if (e is ApiError && e.isNoDirectReports) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [NoReportsEmptyState()],
            );
          }
          // Everything else (cold-start timeout, roster failure, …) gets a
          // friendly message + retry — never a raw `ApiError(...)` dump.
          return _ReviewListError(
            message: e is ApiError ? e.message : AppStrings.errorGeneric,
            onRetry: () => ref.invalidate(monthlyReviewListProvider(period)),
          );
        },
        data: (items) {
          if (items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 80),
                Center(child: Text(AppStrings.monthlyReviewsEmpty)),
              ],
            );
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _ReviewTile(summary: items[i], role: role),
          );
        },
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final MonthlyReviewSummary summary;
  final UserRole? role;
  const _ReviewTile({required this.summary, required this.role});

  @override
  Widget build(BuildContext context) {
    final needsYou = role != null && summary.needsActionBy(role!);
    final completed = summary.currentStage.isTerminal;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(
          summary.opensReviewDetail
              ? AppRoutes.monthlyReviewDetail(summary.id)
              : AppRoutes.reviewsQuarterlyFor(summary.employeeId),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: needsYou
                  ? AppColors.accentOrange.withValues(alpha: 0.5)
                  : AppColors.divider,
              width: needsYou ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.employeeName,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        StagePill(
                          stage: summary.currentStage,
                          status: completed
                              ? StageStatus.submitted
                              : summary.currentStageStatus,
                        ),
                        if (needsYou) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.accentOrange,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              AppStrings.monthlyReviewsNeedsYou,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    EmployeeFormatters.percent(summary.finalScorePct),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryPurple,
                    ),
                  ),
                  if (summary.employeeCode.isNotEmpty)
                    Text(
                      summary.employeeCode,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        ShimmerBox(height: 44, borderRadius: 20),
        SizedBox(height: 16),
        ShimmerBox(height: 78, borderRadius: 16),
        SizedBox(height: 12),
        ShimmerBox(height: 78, borderRadius: 16),
        SizedBox(height: 12),
        ShimmerBox(height: 78, borderRadius: 16),
      ],
    );
  }
}

/// Friendly, retryable error for the monthly-review list — replaces a raw
/// `e.toString()` dump so a Render cold-start timeout reads as a message, not
/// a technical class name. Scrollable so pull-to-refresh still works.
class _ReviewListError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ReviewListError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
      children: [
        const Icon(Icons.error_outline_rounded,
            size: 44, color: AppColors.error),
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
        const SizedBox(height: 20),
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
