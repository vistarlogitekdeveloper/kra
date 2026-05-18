import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../../../../core/router/app_router.dart';
import '../../../../../../core/widgets/paged_list_view.dart';
import '../../../../../employee/data/models/enums.dart' as employee_enums;
import '../../../../../hr/presentation/widgets/search_bar_filter.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/models/team_member.dart';
import '../../../providers/manager_team_providers.dart';
import 'widgets/bulk_select_app_bar.dart';
import 'widgets/team_filter_chips.dart';
import 'widgets/team_member_tile.dart';

/// "Team" tab — paginated, filterable, searchable list of direct
/// reports. Supports a multi-select mode for bulk approve.
class TeamListScreen extends ConsumerWidget {
  const TeamListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(managerTeamFilterProvider);
    final list = ref.watch(managerTeamListProvider);

    final approveTargets = list.selectedReviewIds.toList();

    // Both branches return a PreferredSizeWidget; the conditional
    // expression's inferred type widens to `Widget`, so we build the
    // two AppBars explicitly and pick one.
    PreferredSizeWidget appBar;
    if (list.isSelectionMode) {
      appBar = BulkSelectAppBar(
        selectedCount: list.selectedReviewIds.length,
        onCancel: () => ref
            .read(managerTeamListProvider.notifier)
            .clearSelection(),
        onApprove: list.selectedReviewIds.isEmpty
            ? null
            : () => _openBulkApprove(context, approveTargets),
      );
    } else {
      appBar = _NormalAppBar(
        onToggleSelect: () => ref
            .read(managerTeamListProvider.notifier)
            .toggleSelectionMode(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: appBar,
      body: Column(
        children: [
          if (!list.isSelectionMode)
            SearchBarFilter(
              hint: AppStrings.managerTeamSearchHint,
              initialValue: filter.search,
              onChanged: (v) => ref
                  .read(managerTeamFilterProvider.notifier)
                  .setSearch(v),
            ),
          TeamFilterChips(
            active: filter.filter,
            counts: list.filterCounts,
            onPick: (f) => ref
                .read(managerTeamFilterProvider.notifier)
                .setFilter(f),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: PagedListView(
              items: list.members,
              isInitialLoading: list.isInitialLoading,
              isLoadingMore: list.isLoadingMore,
              hasMore: list.hasMore,
              initialError: list.error,
              onLoadMore: () => ref
                  .read(managerTeamListProvider.notifier)
                  .loadMore(),
              onRefresh: () async => ref
                  .read(managerTeamListProvider.notifier)
                  .refresh(),
              emptyBuilder: (_) => _EmptyForFilter(filter: filter.filter),
              padding:
                  const EdgeInsets.fromLTRB(16, 6, 16, 28),
              itemBuilder: (_, __, member) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: TeamMemberTile(
                  member: member,
                  isSelectionMode: list.isSelectionMode,
                  isSelected: member.reviewId != null &&
                      list.selectedReviewIds.contains(member.reviewId),
                  isSelectable: _isSelectable(member),
                  onTap: () =>
                      _onTileTap(context, ref, member, list.isSelectionMode),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isSelectable(TeamMember m) =>
      m.reviewState == employee_enums.ReviewState.employeeSubmittedAll &&
      m.reviewId != null;

  void _onTileTap(BuildContext context, WidgetRef ref, TeamMember m,
      bool isSelectionMode) {
    if (isSelectionMode) {
      if (!_isSelectable(m) || m.reviewId == null) return;
      ref
          .read(managerTeamListProvider.notifier)
          .toggleSelected(m.reviewId!);
      return;
    }
    context.go(AppRoutes.managerTeamMember(m.employeeId));
  }

  void _openBulkApprove(BuildContext context, List<String> reviewIds) {
    context.go(
      Uri(
        path: AppRoutes.managerTeamBulkApprove,
        queryParameters: {'ids': reviewIds.join(',')},
      ).toString(),
    );
  }
}

class _NormalAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onToggleSelect;
  const _NormalAppBar({required this.onToggleSelect});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      title: const Text(
        AppStrings.managerTeamTitle,
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.checklist_rounded),
          tooltip: AppStrings.managerTeamBulkSelectMode,
          onPressed: onToggleSelect,
        ),
      ],
    );
  }
}

class _EmptyForFilter extends StatelessWidget {
  final ManagerTeamFilter filter;
  const _EmptyForFilter({required this.filter});

  String _message() {
    switch (filter) {
      case ManagerTeamFilter.all:
        return AppStrings.managerTeamEmptyAll;
      case ManagerTeamFilter.pendingMyReview:
        return AppStrings.managerTeamEmptyPending;
      case ManagerTeamFilter.completed:
        return AppStrings.managerTeamEmptyCompleted;
      case ManagerTeamFilter.notSubmitted:
        return AppStrings.managerTeamEmptyNotSubmitted;
      case ManagerTeamFilter.overdue:
        return AppStrings.managerTeamEmptyOverdue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.groups_outlined,
                size: 56,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: 14),
              Text(
                _message(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
