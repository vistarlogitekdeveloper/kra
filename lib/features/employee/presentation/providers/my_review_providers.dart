import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/api/dio_client.dart';
import '../../data/models/enums.dart';
import '../../data/models/my_review_detail.dart';
import '../../data/repositories/api_my_review_repository.dart';
import '../../data/repositories/my_review_repository.dart';

final myReviewRepositoryProvider = Provider<MyReviewRepository>((ref) {
  return ApiMyReviewRepository(dio: ref.read(dioProvider));
});

// ────────────────────────────────────────────────────────────────────
// History list — paginated, filterable
// ────────────────────────────────────────────────────────────────────

class MyReviewListFilter {
  /// `null` = all cycles. Used by the cycle dropdown on the history tab.
  final String? cycleId;

  /// `null` = all states. Drives the All / Pending / Finalized chips.
  /// "Pending" maps to anything not yet finalized; "Finalized" includes
  /// both FINALIZED and ACKNOWLEDGED so the user sees their fully-
  /// completed reviews regardless of acknowledgement status.
  final MyReviewListBucket bucket;

  const MyReviewListFilter({
    this.cycleId,
    this.bucket = MyReviewListBucket.all,
  });

  MyReviewListFilter copyWith({
    Object? cycleId = _sentinel,
    MyReviewListBucket? bucket,
  }) {
    return MyReviewListFilter(
      cycleId:
          identical(cycleId, _sentinel) ? this.cycleId : cycleId as String?,
      bucket: bucket ?? this.bucket,
    );
  }

  static const _sentinel = Object();

  @override
  bool operator ==(Object other) =>
      other is MyReviewListFilter &&
      other.cycleId == cycleId &&
      other.bucket == bucket;

  @override
  int get hashCode => Object.hash(cycleId, bucket);
}

enum MyReviewListBucket { all, pending, finalized }

class MyReviewListController extends StateNotifier<MyReviewListState> {
  final MyReviewRepository _repository;
  final MyReviewListFilter _filter;
  static const int _pageSize = 20;

  MyReviewListController({
    required MyReviewRepository repository,
    required MyReviewListFilter filter,
  })  : _repository = repository,
        _filter = filter,
        super(const MyReviewListState()) {
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
      final pageData = await _repository.listMyReviews(
        cycleId: _filter.cycleId,
        page: 1,
        pageSize: _pageSize,
      );
      state = MyReviewListState(
        reviews: _applyBucket(pageData.reviews),
        page: 1,
        total: pageData.total,
        hasMore: pageData.hasMore,
        isInitialLoading: false,
      );
    } on ApiError catch (e) {
      state = state.copyWith(isInitialLoading: false, error: e.message);
    } catch (e, st) {
      assert(() {
        debugPrint('my-reviews list parse failed: $e\n$st');
        return true;
      }());
      state = state.copyWith(
        isInitialLoading: false,
        error: 'Something went wrong. Please try again.',
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
      final pageData = await _repository.listMyReviews(
        cycleId: _filter.cycleId,
        page: next,
        pageSize: _pageSize,
      );
      final combined = [
        ...state.reviews,
        ..._applyBucket(pageData.reviews),
      ];
      state = state.copyWith(
        reviews: combined,
        page: next,
        total: pageData.total,
        hasMore: combined.length < pageData.total,
        isLoadingMore: false,
      );
    } on ApiError {
      state = state.copyWith(isLoadingMore: false);
      rethrow;
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
      rethrow;
    }
  }

  /// Decides "is this review finalized?" purely off [ReviewState],
  /// since the per-cycle review record doesn't carry a `finalizedAt`
  /// field at the top level.
  static bool _isFinalized(MyReview r) =>
      r.state == ReviewState.finalized ||
      r.state == ReviewState.acknowledged;

  List<MyReview> _applyBucket(List<MyReview> input) {
    switch (_filter.bucket) {
      case MyReviewListBucket.all:
        return input;
      case MyReviewListBucket.pending:
        return input.where((r) => !_isFinalized(r)).toList();
      case MyReviewListBucket.finalized:
        return input.where(_isFinalized).toList();
    }
  }
}

class MyReviewListState {
  final List<MyReview> reviews;
  final int page;
  final int total;
  final bool hasMore;
  final bool isInitialLoading;
  final bool isLoadingMore;
  final String? error;

  const MyReviewListState({
    this.reviews = const [],
    this.page = 0,
    this.total = 0,
    this.hasMore = false,
    this.isInitialLoading = true,
    this.isLoadingMore = false,
    this.error,
  });

  MyReviewListState copyWith({
    List<MyReview>? reviews,
    int? page,
    int? total,
    bool? hasMore,
    bool? isInitialLoading,
    bool? isLoadingMore,
    Object? error = _sentinel,
  }) {
    return MyReviewListState(
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

class MyReviewListFilterController extends StateNotifier<MyReviewListFilter> {
  MyReviewListFilterController() : super(const MyReviewListFilter());
  void setCycle(String? cycleId) =>
      state = state.copyWith(cycleId: cycleId);
  void setBucket(MyReviewListBucket bucket) =>
      state = state.copyWith(bucket: bucket);
  void reset() => state = const MyReviewListFilter();
}

final myReviewListFilterProvider = StateNotifierProvider<
    MyReviewListFilterController, MyReviewListFilter>(
  (ref) => MyReviewListFilterController(),
);

final myReviewListProvider = StateNotifierProvider.autoDispose<
    MyReviewListController, MyReviewListState>((ref) {
  final filter = ref.watch(myReviewListFilterProvider);
  // Keep alive briefly across rapid filter toggles.
  final keepAlive = ref.keepAlive();
  Timer? timer;
  ref.onDispose(() => timer?.cancel());
  ref.onCancel(() {
    timer = Timer(const Duration(seconds: 1), keepAlive.close);
  });
  ref.onResume(() => timer?.cancel());
  return MyReviewListController(
    repository: ref.watch(myReviewRepositoryProvider),
    filter: filter,
  );
});

// ────────────────────────────────────────────────────────────────────
// Single review detail
// ────────────────────────────────────────────────────────────────────

final myReviewDetailProvider = FutureProvider.autoDispose
    .family<MyReviewDetail, String>((ref, reviewId) async {
  final repo = ref.watch(myReviewRepositoryProvider);
  return repo.getReviewDetail(reviewId);
});
