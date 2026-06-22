import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../../../../core/router/app_router.dart';
import '../../../../../../core/widgets/paged_list_view.dart';
import '../../../providers/team_history_providers.dart';
import 'widgets/history_review_tile.dart';

/// Per-employee history list. Owns the filter — sets `employeeId` on
/// mount and clears it on dispose so navigating back to the combined
/// "Team history" tab shows the unfiltered list again.
class TeamMemberHistoryScreen extends ConsumerStatefulWidget {
  final String employeeId;
  const TeamMemberHistoryScreen({super.key, required this.employeeId});

  @override
  ConsumerState<TeamMemberHistoryScreen> createState() =>
      _TeamMemberHistoryScreenState();
}

class _TeamMemberHistoryScreenState
    extends ConsumerState<TeamMemberHistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(teamHistoryFilterProvider.notifier)
          .setEmployee(widget.employeeId);
    });
  }

  @override
  void dispose() {
    // Capture the notifier synchronously — `ref` is unusable once
    // super.dispose() runs, so reading it inside the deferred microtask
    // would throw and the filter would never reset. The filter provider
    // is not autoDispose, so the captured notifier stays alive.
    final filter = ref.read(teamHistoryFilterProvider.notifier);
    // Defer the reset to the next microtask so we don't mutate a
    // provider during widget disposal.
    Future.microtask(() => filter.setEmployee(null));
    super.dispose();
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () =>
              context.go(AppRoutes.managerTeamMember(widget.employeeId)),
        ),
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
            onTap: () =>
                context.push(AppRoutes.managerReviewDetail(review.reviewId)),
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
