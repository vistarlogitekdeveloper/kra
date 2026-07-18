import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/router/app_router.dart';
import '../../../../../core/widgets/adaptive_leading.dart';
import '../../../../../core/widgets/paged_list_view.dart';
import '../../../../../core/widgets/workspace_drawer.dart';
import '../../providers/my_review_providers.dart';
import 'widgets/review_history_card.dart';

/// Paginated list of the logged-in employee's reviews. Filters by
/// state bucket (All / Pending / Finalized) and falls back to a
/// shimmer skeleton while loading.
///
/// Pagination + load-more + pull-to-refresh + empty/error states are
/// owned by [PagedListView] — this screen only supplies the data
/// snapshot, callbacks, and the row builder.
class MyReviewsHistoryScreen extends ConsumerWidget {
  const MyReviewsHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(myReviewListProvider);
    final filter = ref.watch(myReviewListFilterProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: workspaceDrawerFor(ref),
      appBar: AppBar(
        leading: adaptiveLeading(context),
        title: const Text(
          AppStrings.historyTitle,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _FilterChipsRow(
              bucket: filter.bucket,
              onPick: (b) => ref
                  .read(myReviewListFilterProvider.notifier)
                  .setBucket(b),
            ),
            Expanded(
              child: PagedListView(
                items: state.reviews,
                isInitialLoading: state.isInitialLoading,
                isLoadingMore: state.isLoadingMore,
                hasMore: state.hasMore,
                initialError: state.error,
                onLoadMore: () =>
                    ref.read(myReviewListProvider.notifier).loadMore(),
                onRefresh: () async => ref
                    .read(myReviewListProvider.notifier)
                    .refresh(),
                emptyBuilder: (_) => const _EmptyHistory(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                itemBuilder: (_, __, review) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: ReviewHistoryCard(
                    review: review,
                    onTap: () => context
                        .go(AppRoutes.employeeReviewDetail(review.id)),
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

// ─────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────

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
                AppStrings.historyEmptyTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 6),
              Text(
                AppStrings.historyEmptyMessage,
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

// ─────────────────────────────────────────────────────────────────────
// Filter chips row
// ─────────────────────────────────────────────────────────────────────

class _FilterChipsRow extends StatelessWidget {
  final MyReviewListBucket bucket;
  final ValueChanged<MyReviewListBucket> onPick;
  const _FilterChipsRow({required this.bucket, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          _Chip(
            label: AppStrings.historyFilterAll,
            selected: bucket == MyReviewListBucket.all,
            onTap: () => onPick(MyReviewListBucket.all),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: AppStrings.historyFilterPending,
            selected: bucket == MyReviewListBucket.pending,
            onTap: () => onPick(MyReviewListBucket.pending),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: AppStrings.historyFilterFinalized,
            selected: bucket == MyReviewListBucket.finalized,
            onTap: () => onPick(MyReviewListBucket.finalized),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.textPrimary;
    final bg = selected ? AppColors.primaryPurple : AppColors.surface;
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: selected ? AppColors.primaryPurple : AppColors.divider,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
              color: fg,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}
