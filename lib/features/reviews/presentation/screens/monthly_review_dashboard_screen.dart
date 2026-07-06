import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../../auth/data/models/user.dart';
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
        error: (e, _) => ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(e.toString(),
                  style: const TextStyle(color: AppColors.error)),
            ),
          ],
        ),
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
        onTap: () =>
            context.push(AppRoutes.reviewsQuarterlyFor(summary.employeeId)),
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
