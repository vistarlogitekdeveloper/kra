import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/api/dio_client.dart';
import '../../../../core/constants/app_strings.dart';
import '../../data/models/previous_review.dart';
import '../../data/repositories/api_team_history_repository.dart';
import '../../data/repositories/team_history_repository.dart';

final teamHistoryRepositoryProvider =
    Provider<TeamHistoryRepository>((ref) {
  return ApiTeamHistoryRepository(dio: ref.read(dioProvider));
});

// ────────────────────────────────────────────────────────────────────────
// Filter — combined view filters by cycle; per-member filters by id
// ────────────────────────────────────────────────────────────────────────

class TeamHistoryFilter {
  final String? employeeId;
  final String? cycleId;
  const TeamHistoryFilter({this.employeeId, this.cycleId});

  TeamHistoryFilter copyWith({
    Object? employeeId = _sentinel,
    Object? cycleId = _sentinel,
  }) {
    return TeamHistoryFilter(
      employeeId: identical(employeeId, _sentinel)
          ? this.employeeId
          : employeeId as String?,
      cycleId: identical(cycleId, _sentinel)
          ? this.cycleId
          : cycleId as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TeamHistoryFilter &&
      other.employeeId == employeeId &&
      other.cycleId == cycleId;

  @override
  int get hashCode => Object.hash(employeeId, cycleId);

  static const _sentinel = Object();
}

class TeamHistoryFilterNotifier extends StateNotifier<TeamHistoryFilter> {
  TeamHistoryFilterNotifier() : super(const TeamHistoryFilter());
  void setEmployee(String? employeeId) =>
      state = state.copyWith(employeeId: employeeId);
  void setCycle(String? cycleId) =>
      state = state.copyWith(cycleId: cycleId);
  void reset() => state = const TeamHistoryFilter();
}

final teamHistoryFilterProvider =
    StateNotifierProvider<TeamHistoryFilterNotifier, TeamHistoryFilter>(
  (ref) => TeamHistoryFilterNotifier(),
);

// ────────────────────────────────────────────────────────────────────────
// Paginated controller (mirrors the team list shape)
// ────────────────────────────────────────────────────────────────────────

class TeamHistoryListState {
  final List<PreviousReview> reviews;
  final int page;
  final int total;
  final bool hasMore;
  final bool isInitialLoading;
  final bool isLoadingMore;
  final String? error;

  const TeamHistoryListState({
    this.reviews = const [],
    this.page = 0,
    this.total = 0,
    this.hasMore = false,
    this.isInitialLoading = true,
    this.isLoadingMore = false,
    this.error,
  });

  TeamHistoryListState copyWith({
    List<PreviousReview>? reviews,
    int? page,
    int? total,
    bool? hasMore,
    bool? isInitialLoading,
    bool? isLoadingMore,
    Object? error = _sentinel,
  }) {
    return TeamHistoryListState(
      reviews: reviews ?? this.reviews,
      page: page ?? this.page,
      total: total ?? this.total,
      hasMore: hasMore ?? this.hasMore,
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }

  static const _sentinel = Object();
}

class TeamHistoryListController extends StateNotifier<TeamHistoryListState> {
  final TeamHistoryRepository _repo;
  final TeamHistoryFilter _filter;
  static const int _pageSize = 20;

  TeamHistoryListController({
    required TeamHistoryRepository repo,
    required TeamHistoryFilter filter,
  })  : _repo = repo,
        _filter = filter,
        super(const TeamHistoryListState()) {
    refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(
      isInitialLoading: true,
      reviews: const [],
      page: 0,
      error: null,
    );
    try {
      final page = await _repo.listHistory(
        employeeId: _filter.employeeId,
        cycleId: _filter.cycleId,
        page: 1,
        pageSize: _pageSize,
      );
      state = state.copyWith(
        reviews: page.reviews,
        page: 1,
        total: page.total,
        hasMore: page.hasMore,
        isInitialLoading: false,
      );
    } on ApiError catch (e) {
      state = state.copyWith(isInitialLoading: false, error: e.message);
    } catch (e, st) {
      assert(() {
        debugPrint('team history parse failed: $e\n$st');
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
      final page = await _repo.listHistory(
        employeeId: _filter.employeeId,
        cycleId: _filter.cycleId,
        page: next,
        pageSize: _pageSize,
      );
      final combined = [...state.reviews, ...page.reviews];
      state = state.copyWith(
        reviews: combined,
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
}

final teamHistoryListProvider = StateNotifierProvider.autoDispose<
    TeamHistoryListController, TeamHistoryListState>((ref) {
  final filter = ref.watch(teamHistoryFilterProvider);
  return TeamHistoryListController(
    repo: ref.watch(teamHistoryRepositoryProvider),
    filter: filter,
  );
});
