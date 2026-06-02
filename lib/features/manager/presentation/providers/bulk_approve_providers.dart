import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/api/dio_client.dart';
import '../../../../core/constants/app_strings.dart';
import '../../data/models/bulk_approve_request.dart';
import '../../data/models/bulk_approve_response.dart';
import '../../data/repositories/api_bulk_approve_repository.dart';
import '../../data/repositories/bulk_approve_repository.dart';
import 'manager_dashboard_providers.dart';
import 'manager_team_providers.dart';

final bulkApproveRepositoryProvider =
    Provider<BulkApproveRepository>((ref) {
  return ApiBulkApproveRepository(dio: ref.read(dioProvider));
});

// ────────────────────────────────────────────────────────────────────────
// Flow state — confirm screen + result screen pull from the same source
// ────────────────────────────────────────────────────────────────────────

class BulkApproveState {
  final bool isSubmitting;
  final String? error;
  final BulkApproveResponse? result;

  const BulkApproveState({
    this.isSubmitting = false,
    this.error,
    this.result,
  });

  BulkApproveState copyWith({
    bool? isSubmitting,
    Object? error = _sentinel,
    Object? result = _sentinel,
  }) {
    return BulkApproveState(
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: identical(error, _sentinel) ? this.error : error as String?,
      result: identical(result, _sentinel)
          ? this.result
          : result as BulkApproveResponse?,
    );
  }

  static const _sentinel = Object();
}

class BulkApproveController extends StateNotifier<BulkApproveState> {
  final Ref _ref;
  final BulkApproveRepository _repo;
  BulkApproveController(this._ref, this._repo)
      : super(const BulkApproveState());

  /// Submits the bulk-approve request and stores the response so the
  /// result screen can render approved/skipped sections from it.
  /// Invalidates the dashboard + team list on success so badges and
  /// counts refresh.
  Future<BulkApproveResponse?> submit({
    required List<String> reviewIds,
    String? comment,
  }) async {
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final result = await _repo.bulkApprove(
        BulkApproveRequest(reviewIds: reviewIds, comment: comment),
      );
      _ref.invalidate(managerDashboardProvider);
      _ref.read(managerTeamListProvider.notifier).clearSelection();
      _ref.read(managerTeamListProvider.notifier).refresh();
      state = state.copyWith(isSubmitting: false, result: result);
      return result;
    } on ApiError catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.message);
      return null;
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        error: AppStrings.errorGeneric,
      );
      return null;
    }
  }

  void reset() => state = const BulkApproveState();
}

/// `Provider` (not autoDispose) so the result survives the navigation
/// from confirm → result screen.
final bulkApproveProvider =
    StateNotifierProvider<BulkApproveController, BulkApproveState>((ref) {
  return BulkApproveController(
    ref,
    ref.watch(bulkApproveRepositoryProvider),
  );
});
