import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/api/dio_client.dart';
import '../../../../core/constants/app_strings.dart';
import '../../data/models/manager_review_detail.dart';
import '../../data/repositories/api_manager_review_repository.dart';
import '../../data/repositories/manager_review_repository.dart';

final managerReviewRepositoryProvider =
    Provider<ManagerReviewRepository>((ref) {
  return ApiManagerReviewRepository(dio: ref.read(dioProvider));
});

/// One review's full payload — used by the detail screen, the rate
/// screen (initial load), and the readonly screen. autoDispose with
/// the family means each review id caches independently and falls
/// off when navigated away from.
final managerReviewDetailProvider = FutureProvider.autoDispose
    .family<ManagerReviewDetail, String>((ref, reviewId) async {
  final repo = ref.watch(managerReviewRepositoryProvider);
  return repo.getReviewDetail(reviewId);
});

// ────────────────────────────────────────────────────────────────────────
// Inline manager-comment editor
// ────────────────────────────────────────────────────────────────────────

class ManagerCommentState {
  final bool isSubmitting;
  final String? error;
  const ManagerCommentState({this.isSubmitting = false, this.error});

  ManagerCommentState copyWith({
    bool? isSubmitting,
    Object? error = _sentinel,
  }) {
    return ManagerCommentState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }

  static const _sentinel = Object();
}

class ManagerCommentController extends StateNotifier<ManagerCommentState> {
  final ManagerReviewRepository _repo;
  final Ref _ref;
  ManagerCommentController(this._ref, this._repo)
      : super(const ManagerCommentState());

  /// Posts a managerComment update for [reviewId]. On success the
  /// review-detail provider is invalidated so the detail screen
  /// refetches with the new copy.
  Future<bool> save({
    required String reviewId,
    required String comment,
  }) async {
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      await _repo.setManagerComment(
        reviewId: reviewId,
        comment: comment,
      );
      _ref.invalidate(managerReviewDetailProvider(reviewId));
      state = state.copyWith(isSubmitting: false);
      return true;
    } on ApiError catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        error: AppStrings.errorGeneric,
      );
      return false;
    }
  }

  void clearError() => state = state.copyWith(error: null);
}

final managerCommentProvider = StateNotifierProvider.autoDispose<
    ManagerCommentController, ManagerCommentState>((ref) {
  return ManagerCommentController(
    ref,
    ref.watch(managerReviewRepositoryProvider),
  );
});
