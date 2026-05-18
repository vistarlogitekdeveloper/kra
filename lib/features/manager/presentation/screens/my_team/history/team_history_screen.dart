import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../../../../core/router/app_router.dart';
import '../../../../../../core/widgets/paged_list_view.dart';
import '../../../providers/team_history_providers.dart';
import 'widgets/history_review_tile.dart';

/// Combined "all my team's quarterly reviews" history. This is the
/// History tab shown inside the Manager shell. Differs from
/// [TeamMemberHistoryScreen] because no employeeId filter is set —
/// the tile shows the employee name alongside the cycle.
class TeamHistoryScreen extends ConsumerStatefulWidget {
  const TeamHistoryScreen({super.key});

  @override
  ConsumerState<TeamHistoryScreen> createState() =>
      _TeamHistoryScreenState();
}

class _TeamHistoryScreenState extends ConsumerState<TeamHistoryScreen> {
  @override
  void initState() {
    super.initState();
    // Clear any per-employee filter set by the
    // TeamMemberHistoryScreen — combined view doesn't filter on id.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(teamHistoryFilterProvider.notifier).setEmployee(null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(teamHistoryListProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          AppStrings.managerHistoryTitle,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: PagedListView(
        items: list.reviews,
        isInitialLoading: list.isInitialLoading,
        isLoadingMore: list.isLoadingMore,
        hasMore: list.hasMore,
        initialError: list.error,
        onLoadMore: () =>
            ref.read(teamHistoryListProvider.notifier).loadMore(),
        onRefresh: () async =>
            ref.read(teamHistoryListProvider.notifier).refresh(),
        emptyBuilder: (_) => const _EmptyHistory(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        itemBuilder: (_, __, review) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: HistoryReviewTile(
            review: review,
            employeeName: review.employeeName,
            onTap: () =>
                context.go(AppRoutes.managerReviewDetail(review.reviewId)),
          ),
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inbox_rounded,
                size: 56,
                color: AppColors.textMuted,
              ),
              SizedBox(height: 14),
              Text(
                AppStrings.managerHistoryEmptyTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 6),
              Text(
                AppStrings.managerHistoryEmptyMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
