import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/dio_client.dart';
import '../../data/models/review_cycle.dart';
import '../../data/repositories/api_review_cycle_repository.dart';
import '../../data/repositories/review_cycle_repository.dart';

final reviewCycleRepositoryProvider = Provider<ReviewCycleRepository>((ref) {
  return ApiReviewCycleRepository(dio: ref.read(dioProvider));
});

/// Mutable, optimistic list state. Lifecycle hooks like activate/close
/// flip status locally before the network call resolves so the UI feels
/// snappy; on failure we revert + surface a snackbar at the call site.
class ReviewCycleListController extends StateNotifier<AsyncValue<List<ReviewCycle>>> {
  final ReviewCycleRepository _repository;

  ReviewCycleListController(this._repository)
      : super(const AsyncValue.loading()) {
    refresh();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    try {
      final cycles = await _repository.list();
      state = AsyncValue.data(cycles);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<ReviewCycle> create({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    DateTime? selfRatingDeadline,
    DateTime? managerReviewDeadline,
    DateTime? opsScoringDeadline,
    DateTime? financeScoringDeadline,
  }) async {
    final created = await _repository.create(
      name: name,
      startDate: startDate,
      endDate: endDate,
      selfRatingDeadline: selfRatingDeadline,
      managerReviewDeadline: managerReviewDeadline,
      opsScoringDeadline: opsScoringDeadline,
      financeScoringDeadline: financeScoringDeadline,
    );
    state.whenData((cycles) {
      state = AsyncValue.data([created, ...cycles]);
    });
    return created;
  }

  Future<ReviewCycle> update(String id, Map<String, dynamic> changes) async {
    final updated = await _repository.update(id, changes);
    state.whenData((cycles) {
      final idx = cycles.indexWhere((c) => c.id == id);
      if (idx != -1) {
        final next = [...cycles];
        next[idx] = updated;
        state = AsyncValue.data(next);
      }
    });
    return updated;
  }

  /// Optimistically promote DRAFT → ACTIVE, then call server.
  /// Returns true on server confirmation.
  Future<bool> activateOptimistic(String id) async {
    final current = state.value;
    if (current == null) return false;
    final idx = current.indexWhere((c) => c.id == id);
    if (idx == -1) return false;
    final original = current[idx];
    final patched = original.copyWith(status: ReviewCycleStatus.active);
    final next = [...current];
    next[idx] = patched;
    state = AsyncValue.data(next);

    try {
      final confirmed = await _repository.activate(id);
      final after = <ReviewCycle>[...?state.value];
      final aIdx = after.indexWhere((c) => c.id == id);
      if (aIdx != -1) {
        after[aIdx] = confirmed;
        state = AsyncValue.data(after);
      }
      return true;
    } catch (_) {
      final revert = <ReviewCycle>[...?state.value];
      final rIdx = revert.indexWhere((c) => c.id == id);
      if (rIdx != -1) {
        revert[rIdx] = original;
        state = AsyncValue.data(revert);
      }
      return false;
    }
  }

  /// Optimistic close. Same shape as [activateOptimistic].
  Future<bool> closeOptimistic(String id) async {
    final current = state.value;
    if (current == null) return false;
    final idx = current.indexWhere((c) => c.id == id);
    if (idx == -1) return false;
    final original = current[idx];
    final patched = original.copyWith(status: ReviewCycleStatus.closed);
    final next = [...current];
    next[idx] = patched;
    state = AsyncValue.data(next);

    try {
      final confirmed = await _repository.close(id);
      final after = <ReviewCycle>[...?state.value];
      final aIdx = after.indexWhere((c) => c.id == id);
      if (aIdx != -1) {
        after[aIdx] = confirmed;
        state = AsyncValue.data(after);
      }
      return true;
    } catch (_) {
      final revert = <ReviewCycle>[...?state.value];
      final rIdx = revert.indexWhere((c) => c.id == id);
      if (rIdx != -1) {
        revert[rIdx] = original;
        state = AsyncValue.data(revert);
      }
      return false;
    }
  }
}

final reviewCyclesProvider = StateNotifierProvider<
    ReviewCycleListController, AsyncValue<List<ReviewCycle>>>((ref) {
  return ReviewCycleListController(ref.watch(reviewCycleRepositoryProvider));
});

/// Convenience selector — first ACTIVE cycle, or null if none.
final activeReviewCycleProvider = Provider<ReviewCycle?>((ref) {
  final state = ref.watch(reviewCyclesProvider);
  return state.value
      ?.where((c) => c.status == ReviewCycleStatus.active)
      .firstOrNull;
});

final reviewCycleDetailProvider =
    FutureProvider.autoDispose.family<ReviewCycle, String>((ref, id) async {
  final repo = ref.watch(reviewCycleRepositoryProvider);
  return repo.getById(id);
});

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
