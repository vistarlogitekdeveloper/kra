import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/api/dio_client.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../employee/data/models/enums.dart';
import '../../data/models/manager_rate_request.dart';
import '../../data/models/manager_rate_response.dart';
import '../../data/models/manager_review_detail.dart';
import '../../data/models/monthly_score.dart';
import '../../data/models/review_row.dart';
import '../../data/models/transition_error.dart';
import '../../data/repositories/api_manager_rate_repository.dart';
import '../../data/repositories/manager_rate_repository.dart';
import 'manager_dashboard_providers.dart';
import 'manager_review_providers.dart';
import 'manager_team_providers.dart';

final managerRateRepositoryProvider = Provider<ManagerRateRepository>((ref) {
  return ApiManagerRateRepository(dio: ref.read(dioProvider));
});

// ────────────────────────────────────────────────────────────────────────
// State
// ────────────────────────────────────────────────────────────────────────

/// Mode of the rate flow — controls which endpoint the final submit
/// targets. `create` = first-time submit (POST). `edit` = re-rate
/// after MANAGER_RATED_ALL (PATCH).
enum ManagerRateMode { create, edit }

class ManagerRateState {
  /// Working copy of the review. Mutating cells / comment goes through
  /// the notifier's setters which update this in-place; the actual
  /// network save happens on the auto-save tick.
  final ManagerReviewDetail? review;
  final String? reviewId;
  final ManagerRateMode mode;

  /// Latest editable comment. Held separately so the auto-save can
  /// detect changes without diffing the whole review object.
  final String managerComment;

  /// Initial-fetch state.
  final bool isLoading;
  final String? loadError;

  /// Auto-save state. `lastSavedAt` powers the "Saved 3s ago" pill.
  final bool isAutoSaving;
  final DateTime? lastSavedAt;
  final String? autoSaveError;

  /// Submit flight.
  final bool isSubmitting;
  final String? submitError;

  /// Returned by the most-recent submit — drives navigation to either
  /// the clean-success or partial-success screen.
  final ManagerRateResponse? lastSubmitResponse;

  /// Pulled from response.transitionError on partial-success.
  TransitionError? get lastTransitionError =>
      lastSubmitResponse?.transitionError;

  const ManagerRateState({
    this.review,
    this.reviewId,
    this.mode = ManagerRateMode.create,
    this.managerComment = '',
    this.isLoading = true,
    this.loadError,
    this.isAutoSaving = false,
    this.lastSavedAt,
    this.autoSaveError,
    this.isSubmitting = false,
    this.submitError,
    this.lastSubmitResponse,
  });

  /// True iff every MANAGER-editable cell has a rating. Submit
  /// disables until this is true — server enforces the same gate.
  bool get isComplete {
    final r = review;
    if (r == null) return false;
    for (final row in r.rows) {
      if (row.scoreSource == ScoreSource.feed) continue;
      for (final cell in row.monthlyScores) {
        if (cell.isNotApplicable) continue;
        if (cell.monthStatus != ReviewMonthStatus.open) continue;
        if (cell.managerRating == null) return false;
      }
    }
    return true;
  }

  /// Live weighted-total estimate (0–100). Server is authoritative —
  /// this is purely visual until submit lands.
  double get weightedTotalPct {
    final r = review;
    if (r == null) return 0;
    double weightedSum = 0;
    double remainingWeight = 0;
    for (final row in r.rows) {
      for (final cell in row.monthlyScores) {
        if (cell.isNotApplicable) continue;
        final score = cell.managerRating;
        if (score == null) continue;
        final pct = row.weightagePercent / row.monthlyScores.length;
        weightedSum += (score / row.maxScore) * pct;
        remainingWeight += pct;
      }
    }
    if (remainingWeight <= 0) return 0;
    return (weightedSum * 100 / remainingWeight).clamp(0.0, 100.0);
  }

  ManagerRateState copyWith({
    ManagerReviewDetail? review,
    String? reviewId,
    ManagerRateMode? mode,
    String? managerComment,
    bool? isLoading,
    Object? loadError = _sentinel,
    bool? isAutoSaving,
    Object? lastSavedAt = _sentinel,
    Object? autoSaveError = _sentinel,
    bool? isSubmitting,
    Object? submitError = _sentinel,
    Object? lastSubmitResponse = _sentinel,
  }) {
    return ManagerRateState(
      review: review ?? this.review,
      reviewId: reviewId ?? this.reviewId,
      mode: mode ?? this.mode,
      managerComment: managerComment ?? this.managerComment,
      isLoading: isLoading ?? this.isLoading,
      loadError: identical(loadError, _sentinel)
          ? this.loadError
          : loadError as String?,
      isAutoSaving: isAutoSaving ?? this.isAutoSaving,
      lastSavedAt: identical(lastSavedAt, _sentinel)
          ? this.lastSavedAt
          : lastSavedAt as DateTime?,
      autoSaveError: identical(autoSaveError, _sentinel)
          ? this.autoSaveError
          : autoSaveError as String?,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      submitError: identical(submitError, _sentinel)
          ? this.submitError
          : submitError as String?,
      lastSubmitResponse: identical(lastSubmitResponse, _sentinel)
          ? this.lastSubmitResponse
          : lastSubmitResponse as ManagerRateResponse?,
    );
  }

  static const _sentinel = Object();
}

// ────────────────────────────────────────────────────────────────────────
// Notifier
// ────────────────────────────────────────────────────────────────────────

/// Drives the manager-rate matrix screen end-to-end:
///   1. Loads the review (via [managerReviewDetailProvider])
///   2. Holds the working copy of scores + comment
///   3. Auto-saves every 5s through POST /reviews/:id/scores
///      (no state transition — purely a draft)
///   4. Submits via POST or PATCH /manager-rate depending on [mode],
///      parses the `transitioned` flag, and routes to success or
///      partial-success screens via the response field
///   5. Invalidates downstream providers (dashboard, team list,
///      review detail) so the rest of the app picks up the new state
class ManagerRateNotifier extends StateNotifier<ManagerRateState> {
  final Ref _ref;
  final ManagerRateRepository _repo;
  static const Duration _autoSaveInterval = Duration(seconds: 5);

  Timer? _autoSaveTimer;
  bool _hasDirtyChangesSinceSave = false;

  /// Tracks the cells that have been touched this session so the
  /// auto-save call body only carries cells the user has edited —
  /// keeps the payload small and avoids races with concurrent saves.
  final Set<String> _dirtyCellIds = {};

  ManagerRateNotifier(this._ref, this._repo)
      : super(const ManagerRateState());

  // ───── Load ─────

  Future<void> load(String reviewId, {ManagerRateMode? mode}) async {
    state = state.copyWith(
      reviewId: reviewId,
      isLoading: true,
      loadError: null,
    );
    try {
      final review =
          await _ref.read(managerReviewDetailProvider(reviewId).future);
      // Auto-pick edit vs create mode from the loaded state. Caller
      // can override (e.g. "Edit My Rating" CTA forces edit).
      final resolvedMode = mode ??
          (review.state == ReviewState.managerRatedAll
              ? ManagerRateMode.edit
              : ManagerRateMode.create);
      state = state.copyWith(
        review: review,
        mode: resolvedMode,
        managerComment: review.managerComment ?? '',
        isLoading: false,
        autoSaveError: null,
      );
    } on ApiError catch (e) {
      state = state.copyWith(isLoading: false, loadError: e.message);
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        loadError: AppStrings.errorGeneric,
      );
    }
  }

  // ───── Mutations ─────

  void setCellRating(String monthlyScoreId, double? rating) {
    _updateCell(monthlyScoreId, (c) => c.copyWith(managerRating: rating));
  }

  void setCellRemark(String monthlyScoreId, String? remark) {
    _updateCell(monthlyScoreId, (c) => c.copyWith(managerRemark: remark));
  }

  void setManagerComment(String value) {
    state = state.copyWith(managerComment: value);
    _hasDirtyChangesSinceSave = true;
    _scheduleAutoSave();
  }

  void _updateCell(
      String cellId, MonthlyScore Function(MonthlyScore c) edit) {
    final review = state.review;
    if (review == null) return;
    ReviewRow? touchedRow;
    MonthlyScore? touchedCell;
    for (final row in review.rows) {
      for (final c in row.monthlyScores) {
        if (c.monthlyScoreId == cellId) {
          touchedRow = row;
          touchedCell = c;
          break;
        }
      }
      if (touchedRow != null) break;
    }
    if (touchedRow == null || touchedCell == null) return;
    final updatedCell = edit(touchedCell);
    final updatedRow = touchedRow.withUpdatedCell(updatedCell);
    state = state.copyWith(review: review.withUpdatedRow(updatedRow));
    _dirtyCellIds.add(cellId);
    _hasDirtyChangesSinceSave = true;
    _scheduleAutoSave();
  }

  // ───── Auto-save ─────

  void _scheduleAutoSave() {
    _autoSaveTimer ??= Timer.periodic(
      _autoSaveInterval,
      (_) => _maybeFlushAutoSave(),
    );
  }

  Future<void> _maybeFlushAutoSave() async {
    if (!_hasDirtyChangesSinceSave) return;
    final reviewId = state.reviewId;
    final review = state.review;
    if (reviewId == null || review == null) return;
    final dirtyIds = Set<String>.from(_dirtyCellIds);
    _hasDirtyChangesSinceSave = false;
    _dirtyCellIds.clear();
    state = state.copyWith(isAutoSaving: true);
    try {
      final scores = <ManagerRateScore>[];
      for (final row in review.rows) {
        for (final cell in row.monthlyScores) {
          if (!dirtyIds.contains(cell.monthlyScoreId)) continue;
          scores.add(ManagerRateScore(
            monthlyScoreId: cell.monthlyScoreId,
            managerRating: cell.managerRating,
            managerRemark: cell.managerRemark,
          ));
        }
      }
      if (scores.isEmpty && state.managerComment.isEmpty) {
        state = state.copyWith(isAutoSaving: false);
        return;
      }
      await _repo.autoSaveScores(
        reviewId: reviewId,
        scores: ManagerRateRequest(
          scores: scores,
          managerComment: state.managerComment.isEmpty
              ? null
              : state.managerComment,
          autoSubmit: false,
        ),
      );
      state = state.copyWith(
        isAutoSaving: false,
        lastSavedAt: DateTime.now(),
        autoSaveError: null,
      );
    } catch (e, st) {
      assert(() {
        debugPrint('manager auto-save failed: $e\n$st');
        return true;
      }());
      // Mark the cells dirty again so the next tick retries them.
      _dirtyCellIds.addAll(dirtyIds);
      _hasDirtyChangesSinceSave = true;
      state = state.copyWith(
        isAutoSaving: false,
        autoSaveError: AppStrings.errorGeneric,
      );
    }
  }

  /// Manual retry of the auto-save — bound to the "retry" button that
  /// the indicator shows when the last save failed.
  Future<void> retryAutoSave() async {
    if (!_hasDirtyChangesSinceSave) return;
    await _maybeFlushAutoSave();
  }

  // ───── Submit ─────

  Future<ManagerRateResponse?> submit() async {
    final reviewId = state.reviewId;
    final review = state.review;
    if (reviewId == null || review == null) return null;
    if (!state.isComplete) {
      state = state.copyWith(
          submitError: AppStrings.managerRateIncompleteScores);
      return null;
    }

    // Flush any pending edits before the final submit so they don't
    // get lost in a race with the autoSubmit POST.
    if (_hasDirtyChangesSinceSave) {
      await _maybeFlushAutoSave();
    }

    final scores = <ManagerRateScore>[];
    for (final row in review.rows) {
      if (row.scoreSource == ScoreSource.feed) continue;
      for (final cell in row.monthlyScores) {
        if (cell.isNotApplicable) continue;
        if (cell.monthStatus != ReviewMonthStatus.open) continue;
        scores.add(ManagerRateScore(
          monthlyScoreId: cell.monthlyScoreId,
          managerRating: cell.managerRating,
          managerRemark: cell.managerRemark,
        ));
      }
    }

    state = state.copyWith(isSubmitting: true, submitError: null);
    try {
      final req = ManagerRateRequest(
        scores: scores,
        managerComment:
            state.managerComment.isEmpty ? null : state.managerComment,
        autoSubmit: true,
      );
      final response = state.mode == ManagerRateMode.edit
          ? await _repo.updateRating(reviewId: reviewId, request: req)
          : await _repo.submitRating(reviewId: reviewId, request: req);
      _ref.invalidate(managerReviewDetailProvider(reviewId));
      _ref.invalidate(managerDashboardProvider);
      // Refresh the team list so the badge swaps from "Ready" to
      // "You Rated" once the user lands back on it.
      _ref.read(managerTeamListProvider.notifier).refresh();
      state = state.copyWith(
        isSubmitting: false,
        lastSubmitResponse: response,
      );
      return response;
    } on ApiError catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        submitError: e.message,
      );
      return null;
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        submitError: AppStrings.errorGeneric,
      );
      return null;
    }
  }

  void clearSubmitError() => state = state.copyWith(submitError: null);

  /// Reset the in-memory state so a fresh entry into the rate screen
  /// triggers a load. Called by the success / partial screens'
  /// "back to team" CTAs.
  void reset() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    _hasDirtyChangesSinceSave = false;
    _dirtyCellIds.clear();
    state = const ManagerRateState();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    super.dispose();
  }
}

final managerRateProvider = StateNotifierProvider.autoDispose<
    ManagerRateNotifier, ManagerRateState>((ref) {
  return ManagerRateNotifier(
    ref,
    ref.watch(managerRateRepositoryProvider),
  );
});
