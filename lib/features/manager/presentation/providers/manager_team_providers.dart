import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/api/dio_client.dart';
import '../../../../core/constants/app_strings.dart';
import '../../data/models/enums.dart';
import '../../data/models/team_member.dart';
import '../../data/models/team_member_profile.dart';
import '../../data/repositories/api_manager_team_repository.dart';
import '../../data/repositories/manager_team_repository.dart';

final managerTeamRepositoryProvider =
    Provider<ManagerTeamRepository>((ref) {
  return ApiManagerTeamRepository(dio: ref.read(dioProvider));
});

// ────────────────────────────────────────────────────────────────────────
// Filter + search state (debounced)
// ────────────────────────────────────────────────────────────────────────

/// User-facing filter inputs for the team list. `search` is debounced
/// inside the controller; the chip filter applies synchronously.
class ManagerTeamFilterState {
  final String? cycleId;
  final String search;
  final ManagerTeamFilter filter;

  const ManagerTeamFilterState({
    this.cycleId,
    this.search = '',
    this.filter = ManagerTeamFilter.all,
  });

  ManagerTeamFilterState copyWith({
    Object? cycleId = _sentinel,
    String? search,
    ManagerTeamFilter? filter,
  }) {
    return ManagerTeamFilterState(
      cycleId: identical(cycleId, _sentinel)
          ? this.cycleId
          : cycleId as String?,
      search: search ?? this.search,
      filter: filter ?? this.filter,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ManagerTeamFilterState &&
      other.cycleId == cycleId &&
      other.search == search &&
      other.filter == filter;

  @override
  int get hashCode => Object.hash(cycleId, search, filter);

  static const _sentinel = Object();
}

class ManagerTeamFilterNotifier extends StateNotifier<ManagerTeamFilterState> {
  ManagerTeamFilterNotifier() : super(const ManagerTeamFilterState());

  Timer? _debounce;
  static const _debounceDelay = Duration(milliseconds: 300);

  void setSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () {
      state = state.copyWith(search: value);
    });
  }

  void setFilter(ManagerTeamFilter filter) {
    _debounce?.cancel();
    state = state.copyWith(filter: filter);
  }

  void setCycle(String? cycleId) {
    _debounce?.cancel();
    state = state.copyWith(cycleId: cycleId);
  }

  void reset() {
    _debounce?.cancel();
    state = const ManagerTeamFilterState();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final managerTeamFilterProvider = StateNotifierProvider<
    ManagerTeamFilterNotifier, ManagerTeamFilterState>(
  (ref) => ManagerTeamFilterNotifier(),
);

// ────────────────────────────────────────────────────────────────────────
// Paginated list controller
// ────────────────────────────────────────────────────────────────────────

class ManagerTeamListState {
  final List<TeamMember> members;
  final int page;
  final int total;
  final Map<String, int> filterCounts;
  final bool hasMore;
  final bool isInitialLoading;
  final bool isLoadingMore;
  final String? error;

  /// True when the backend answered a manager-scoped call with the
  /// "you manage no one" 403 (see [ApiError.isNoDirectReports]). This is a
  /// normal state, not a failure — the Team tab shows the no-reports empty
  /// state (with a jump to the self-view) instead of a raw error.
  final bool noReports;

  /// Multi-select state for bulk-approve. Holds review ids (not
  /// employee ids) because the bulk-approve endpoint takes reviewIds.
  final Set<String> selectedReviewIds;
  final bool isSelectionMode;

  const ManagerTeamListState({
    this.members = const [],
    this.page = 0,
    this.total = 0,
    this.filterCounts = const {},
    this.hasMore = false,
    this.isInitialLoading = true,
    this.isLoadingMore = false,
    this.error,
    this.noReports = false,
    this.selectedReviewIds = const {},
    this.isSelectionMode = false,
  });

  ManagerTeamListState copyWith({
    List<TeamMember>? members,
    int? page,
    int? total,
    Map<String, int>? filterCounts,
    bool? hasMore,
    bool? isInitialLoading,
    bool? isLoadingMore,
    Object? error = _sentinel,
    bool? noReports,
    Set<String>? selectedReviewIds,
    bool? isSelectionMode,
  }) {
    return ManagerTeamListState(
      members: members ?? this.members,
      page: page ?? this.page,
      total: total ?? this.total,
      filterCounts: filterCounts ?? this.filterCounts,
      hasMore: hasMore ?? this.hasMore,
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: identical(error, _sentinel) ? this.error : error as String?,
      noReports: noReports ?? this.noReports,
      selectedReviewIds: selectedReviewIds ?? this.selectedReviewIds,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
    );
  }

  static const _sentinel = Object();
}

class ManagerTeamListController extends StateNotifier<ManagerTeamListState> {
  final ManagerTeamRepository _repo;
  final ManagerTeamFilterState _filter;
  static const int _pageSize = 20;

  ManagerTeamListController({
    required ManagerTeamRepository repo,
    required ManagerTeamFilterState filter,
  })  : _repo = repo,
        _filter = filter,
        super(const ManagerTeamListState()) {
    refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(
      isInitialLoading: true,
      members: const [],
      page: 0,
      error: null,
      noReports: false,
    );
    try {
      final page = await _repo.listTeam(
        cycleId: _filter.cycleId,
        page: 1,
        pageSize: _pageSize,
        search: _filter.search,
        filter: _filter.filter,
      );
      state = state.copyWith(
        members: page.members,
        page: 1,
        total: page.total,
        filterCounts: page.filterCounts,
        hasMore: page.hasMore,
        isInitialLoading: false,
      );
    } on ApiError catch (e) {
      // "You manage no one" is a data state, not an error — the Team tab
      // empty-states it (with a jump to the self-view) rather than showing
      // a raw 403.
      if (e.isNoDirectReports) {
        state = state.copyWith(isInitialLoading: false, noReports: true);
      } else {
        state = state.copyWith(isInitialLoading: false, error: e.message);
      }
    } catch (e, st) {
      assert(() {
        debugPrint('team list parse failed: $e\n$st');
        return true;
      }());
      state = state.copyWith(
        isInitialLoading: false,
        error: AppStrings.errorGeneric,
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.isInitialLoading) {
      return;
    }
    state = state.copyWith(isLoadingMore: true);
    try {
      final next = state.page + 1;
      final page = await _repo.listTeam(
        cycleId: _filter.cycleId,
        page: next,
        pageSize: _pageSize,
        search: _filter.search,
        filter: _filter.filter,
      );
      final combined = [...state.members, ...page.members];
      state = state.copyWith(
        members: combined,
        page: next,
        total: page.total,
        hasMore: combined.length < page.total,
        isLoadingMore: false,
      );
    } on ApiError {
      state = state.copyWith(isLoadingMore: false);
      rethrow;
    }
  }

  // ── Multi-select ──

  void toggleSelectionMode() {
    state = state.copyWith(
      isSelectionMode: !state.isSelectionMode,
      selectedReviewIds: const {},
    );
  }

  void toggleSelected(String reviewId) {
    final next = {...state.selectedReviewIds};
    if (next.contains(reviewId)) {
      next.remove(reviewId);
    } else {
      next.add(reviewId);
    }
    state = state.copyWith(selectedReviewIds: next);
  }

  void clearSelection() {
    state = state.copyWith(
      selectedReviewIds: const {},
      isSelectionMode: false,
    );
  }
}

final managerTeamListProvider = StateNotifierProvider.autoDispose<
    ManagerTeamListController, ManagerTeamListState>((ref) {
  final filter = ref.watch(managerTeamFilterProvider);
  return ManagerTeamListController(
    repo: ref.watch(managerTeamRepositoryProvider),
    filter: filter,
  );
});

// ────────────────────────────────────────────────────────────────────────
// Per-member profile (detail)
// ────────────────────────────────────────────────────────────────────────

final managerTeamMemberProfileProvider = FutureProvider.autoDispose
    .family<TeamMemberProfile, String>((ref, employeeId) async {
  final repo = ref.watch(managerTeamRepositoryProvider);
  return repo.getMemberProfile(employeeId);
});
