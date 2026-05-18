import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/api/dio_client.dart';
import '../../data/models/employee_profile.dart';
import '../../data/repositories/api_my_profile_repository.dart';
import '../../data/repositories/my_profile_repository.dart';

final myProfileRepositoryProvider = Provider<MyProfileRepository>((ref) {
  return ApiMyProfileRepository(dio: ref.read(dioProvider));
});

/// The logged-in user's own profile. autoDispose so a fresh fetch
/// happens when the user re-enters the profile tab — guards against
/// stale data after edits made on another device.
final myProfileProvider =
    FutureProvider.autoDispose<EmployeeProfile>((ref) async {
  final repo = ref.watch(myProfileRepositoryProvider);
  return repo.fetchMyProfile();
});

// ────────────────────────────────────────────────────────────────────
// Edit-profile actions (optimistic locally, refetch as truth)
// ────────────────────────────────────────────────────────────────────

class MyProfileEditController extends StateNotifier<MyProfileEditState> {
  final MyProfileRepository _repository;
  final Ref _ref;

  MyProfileEditController(this._ref, this._repository)
      : super(const MyProfileEditState());

  /// Patches the editable subset of profile fields. The PATCH endpoint
  /// returns the full updated profile — we invalidate the cache so the
  /// next read picks up the server's truth (including any normalisation
  /// the backend may apply, e.g. phone-number formatting).
  ///
  /// True optimistic UI for `phone` is possible with [EmployeeProfile]
  /// (which carries the field) — Stage 4 wires it in once the edit
  /// screen lands. For now this implementation is invalidate-on-success.
  Future<bool> save(Map<String, dynamic> changes) async {
    if (changes.isEmpty) return true;
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      await _repository.updateMyProfile(changes);
      _ref.invalidate(myProfileProvider);
      state = state.copyWith(isSubmitting: false);
      return true;
    } on ApiError catch (e) {
      _ref.invalidate(myProfileProvider);
      state = state.copyWith(isSubmitting: false, error: e.message);
      return false;
    } catch (_) {
      _ref.invalidate(myProfileProvider);
      state = state.copyWith(
        isSubmitting: false,
        error: 'Something went wrong. Please try again.',
      );
      return false;
    }
  }

  void clearError() => state = state.copyWith(error: null);
}

class MyProfileEditState {
  final bool isSubmitting;
  final String? error;

  const MyProfileEditState({this.isSubmitting = false, this.error});

  MyProfileEditState copyWith({
    bool? isSubmitting,
    Object? error = _sentinel,
  }) {
    return MyProfileEditState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }

  static const _sentinel = Object();
}

final myProfileEditProvider = StateNotifierProvider.autoDispose<
    MyProfileEditController, MyProfileEditState>((ref) {
  return MyProfileEditController(
    ref,
    ref.watch(myProfileRepositoryProvider),
  );
});
