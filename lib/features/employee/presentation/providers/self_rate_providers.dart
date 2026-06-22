import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/api/dio_client.dart';
import '../../../../core/constants/app_strings.dart';
import '../../data/models/enums.dart';
import '../../data/models/kra_score_entry.dart';
import '../../data/models/my_review_detail.dart';
import '../../data/models/self_rate_request.dart';
import '../../data/repositories/api_self_rate_repository.dart';
import '../../data/repositories/self_rate_repository.dart';
import 'employee_dashboard_providers.dart';
import 'my_kra_providers.dart';
import 'my_review_providers.dart';

// ────────────────────────────────────────────────────────────────────────
// Repository binding
// ────────────────────────────────────────────────────────────────────────

final selfRateRepositoryProvider = Provider<SelfRateRepository>((ref) {
  return ApiSelfRateRepository(dio: ref.read(dioProvider));
});

/// Single source of truth for shared_preferences — autoCloses with the
/// app, so a manual dispose isn't required.
final sharedPreferencesProvider = FutureProvider<SharedPreferences>((_) {
  return SharedPreferences.getInstance();
});

// ────────────────────────────────────────────────────────────────────────
// Draft storage helpers
// ────────────────────────────────────────────────────────────────────────

/// Wire-protocol for a draft persisted to local storage. Versioned so a
/// future schema change can ignore stale drafts cleanly. The model
/// classes don't know about persistence by design — the notifier
/// snapshots them into this DTO at save time. Exposed publicly because
/// the screen reads `savedAt` to format the resume-prompt timestamp.
class SelfRateDraftEnvelope {
  static const int currentVersion = 1;

  final int version;
  final String reviewId;
  final String? monthId;
  final List<KraScoreEntry> entries;
  final DateTime savedAt;

  const SelfRateDraftEnvelope({
    required this.version,
    required this.reviewId,
    required this.monthId,
    required this.entries,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'reviewId': reviewId,
        'monthId': monthId,
        'entries': entries.map((e) => e.toJson()).toList(),
        'savedAt': savedAt.toIso8601String(),
      };

  static SelfRateDraftEnvelope? tryFromJson(Map<String, dynamic> json) {
    final v = json['version'];
    if (v is! int || v != currentVersion) return null;
    final id = json['reviewId'];
    if (id is! String || id.isEmpty) return null;
    return SelfRateDraftEnvelope(
      version: v,
      reviewId: id,
      monthId: json['monthId'] as String?,
      entries: ((json['entries'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(KraScoreEntry.fromJson)
          .toList(),
      savedAt: DateTime.tryParse('${json['savedAt']}') ?? DateTime.now(),
    );
  }

  static String keyFor(String reviewId) => 'self_rate_draft.$reviewId';
}

// ────────────────────────────────────────────────────────────────────────
// State
// ────────────────────────────────────────────────────────────────────────

/// State of the self-rate form. Distinct from [AsyncValue] because the
/// form has its own "submitting" / "saving" sub-states that aren't a
/// simple loading→data→error tri-modal.
class SelfRateState {
  /// The review the user is rating, once fetched.
  final MyReview? review;
  final String? reviewId;

  /// Active month — the form opens to the latest OPEN month by default.
  /// May be `null` if the cycle has no months yet.
  final String? activeMonthId;

  /// One entry per (applicable row × activeMonthId) cell. Sorted by
  /// `displayOrder` so the UI list is stable across saves.
  final List<KraScoreEntry> entries;

  /// Whether a local draft was found on screen open. Used by the
  /// resume-draft prompt — clears once the user picks an option.
  final SelfRateDraftEnvelope? pendingDraft;

  /// Mark the form as locked when the review state has moved past
  /// EMPLOYEE_SUBMITTED_ALL or any cell's month is LOCKED. Drives the
  /// router redirect to SelfRateLockedScreen.
  final bool isLocked;

  /// Initial-load network state.
  final bool isLoading;
  final String? loadError;

  /// In-flight POST. Submit-bar shows a progress spinner when true.
  final bool isSubmitting;
  final String? submitError;

  /// Set after a successful submit so the success screen can pick up
  /// the freshly-returned totals without an extra fetch.
  final MyReview? lastSubmittedReview;

  /// True while the auto-save timer is mid-write. Surfaced as a small
  /// "Saving…" indicator on the submit bar — purely visual.
  final bool isAutoSaving;

  const SelfRateState({
    this.review,
    this.reviewId,
    this.activeMonthId,
    this.entries = const [],
    this.pendingDraft,
    this.isLocked = false,
    this.isLoading = true,
    this.loadError,
    this.isSubmitting = false,
    this.submitError,
    this.lastSubmittedReview,
    this.isAutoSaving = false,
  });

  /// Convenience — total of all weighted contributions for the active
  /// month, scaled 0–100. N/A cells are excluded from both numerator
  /// and denominator so a fully-N/A row doesn't drag the total down.
  ///
  /// Math: each applicable cell contributes `(score/maxScore) × weight_pct`.
  /// We sum that and re-normalise by the remaining weight (which may be
  /// less than 100 if some cells are N/A), producing a final 0–100 value
  /// that matches what the server computes.
  double get weightedTotalPct {
    if (entries.isEmpty) return 0;
    double weightedSum = 0;
    double remainingWeight = 0;
    for (final e in entries) {
      if (e.isNotApplicable) continue;
      remainingWeight += e.weightagePercent;
      weightedSum += e.weightedContribution;
    }
    if (remainingWeight <= 0) return 0;
    // weightedSum already includes a `weightagePercent` factor — dividing
    // by the remaining-weight total renormalises to a 0–100 average.
    return (weightedSum * 100 / remainingWeight).clamp(0.0, 100.0);
  }

  /// True iff every applicable cell has been rated or marked N/A.
  /// Submit button gates on this — server enforces the same rule.
  bool get isComplete => entries.isNotEmpty && entries.every((e) => e.isFilled);

  /// True iff there are local changes not yet persisted to the
  /// server (used for the dirty-form back-press guard).
  bool get isDirty => entries.any((e) => e.isFilled) && !(isSubmitting);

  SelfRateState copyWith({
    MyReview? review,
    String? reviewId,
    Object? activeMonthId = _sentinel,
    List<KraScoreEntry>? entries,
    Object? pendingDraft = _sentinel,
    bool? isLocked,
    bool? isLoading,
    Object? loadError = _sentinel,
    bool? isSubmitting,
    Object? submitError = _sentinel,
    Object? lastSubmittedReview = _sentinel,
    bool? isAutoSaving,
  }) {
    return SelfRateState(
      review: review ?? this.review,
      reviewId: reviewId ?? this.reviewId,
      activeMonthId: identical(activeMonthId, _sentinel)
          ? this.activeMonthId
          : activeMonthId as String?,
      entries: entries ?? this.entries,
      pendingDraft: identical(pendingDraft, _sentinel)
          ? this.pendingDraft
          : pendingDraft as SelfRateDraftEnvelope?,
      isLocked: isLocked ?? this.isLocked,
      isLoading: isLoading ?? this.isLoading,
      loadError: identical(loadError, _sentinel)
          ? this.loadError
          : loadError as String?,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      submitError: identical(submitError, _sentinel)
          ? this.submitError
          : submitError as String?,
      lastSubmittedReview: identical(lastSubmittedReview, _sentinel)
          ? this.lastSubmittedReview
          : lastSubmittedReview as MyReview?,
      isAutoSaving: isAutoSaving ?? this.isAutoSaving,
    );
  }

  static const _sentinel = Object();
}

// ────────────────────────────────────────────────────────────────────────
// Notifier
// ────────────────────────────────────────────────────────────────────────

/// Drives the self-rate flow end-to-end:
///   1. Resolves the review for the active cycle / month
///   2. Materialises one [KraScoreEntry] per applicable cell
///   3. Auto-saves to SharedPreferences every 5 s while the form is dirty
///   4. Restores from a local draft when one is found (resume prompt)
///   5. Submits to POST /reviews/:id/self-rate and maps errors to user-
///      friendly snackbars
class SelfRateNotifier extends StateNotifier<SelfRateState> {
  final Ref _ref;
  final SelfRateRepository _repo;

  /// Cadence at which auto-save fires while the form is dirty. 5s
  /// matches the spec; tweak via [autoSaveInterval] override in tests.
  static const Duration _autoSaveInterval = Duration(seconds: 5);

  Timer? _autoSaveTimer;
  bool _hasMutatedSinceLastSave = false;

  SelfRateNotifier(this._ref, this._repo) : super(const SelfRateState());

  // ───── Initial load ─────

  /// Loads the review for [reviewId] and seeds [entries] from its cells.
  /// If a local draft exists, surfaces it via [SelfRateState.pendingDraft]
  /// — the screen prompts the user to resume or start fresh.
  Future<void> load(String reviewId) async {
    state = state.copyWith(
      reviewId: reviewId,
      isLoading: true,
      loadError: null,
    );
    try {
      // We reuse the review-detail provider so a freshly-saved review
      // is available immediately to History without an extra round-trip.
      final review = await _ref.read(myReviewDetailProvider(reviewId).future);

      // Pick the active month — the latest OPEN month, falling back to
      // the latest month overall if none are open.
      final months = review.reviewCycle?.months ?? const [];
      final openMonths =
          months.where((m) => m.status == ReviewMonthStatus.open).toList();
      final activeMonth =
          openMonths.isNotEmpty ? openMonths.last : months.lastOrNull;

      final entries = _materialiseEntries(review, activeMonth?.id);

      // Look for a local draft. If the saved draft is for a different
      // reviewId we ignore it — drafts are scoped per review.
      final draft = await _loadDraft(reviewId);

      // Lockout check: if the review state has progressed past the
      // self-edit window or the active month is LOCKED, redirect via
      // [isLocked]. The screen routes to SelfRateLockedScreen.
      final isLocked = !review.state.isSelfEditable ||
          activeMonth?.status == ReviewMonthStatus.locked;

      state = state.copyWith(
        review: review,
        activeMonthId: activeMonth?.id,
        entries: entries,
        pendingDraft: draft,
        isLocked: isLocked,
        isLoading: false,
        loadError: null,
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

  /// Rebuilds the in-memory entries when the user picks a different
  /// month (rare — the form usually opens to the active month). Drops
  /// any in-flight draft because the cell IDs are different.
  void switchMonth(String monthId) {
    final review = state.review;
    if (review == null) return;
    final entries = _materialiseEntries(review, monthId);
    state = state.copyWith(
      activeMonthId: monthId,
      entries: entries,
      pendingDraft: null,
    );
    _scheduleAutoSave();
  }

  /// Apply the local draft the user just opted to resume. Cells whose
  /// monthlyScoreId no longer exists on the server (e.g. the row was
  /// removed) are silently dropped — drafts are best-effort restores.
  void resumeDraft() {
    final draft = state.pendingDraft;
    if (draft == null) return;
    final byId = {for (final e in draft.entries) e.monthlyScoreId: e};
    final merged = [
      for (final e in state.entries)
        byId[e.monthlyScoreId] == null
            ? e
            : e.copyWith(
                selfRating: byId[e.monthlyScoreId]!.selfRating,
                selfRemark: byId[e.monthlyScoreId]!.selfRemark,
                isNotApplicable: byId[e.monthlyScoreId]!.isNotApplicable,
              ),
    ];
    state = state.copyWith(entries: merged, pendingDraft: null);
    _scheduleAutoSave();
  }

  /// User declined the resume prompt — wipe the saved draft.
  Future<void> discardDraft() async {
    final reviewId = state.reviewId;
    state = state.copyWith(pendingDraft: null);
    if (reviewId != null) await _clearDraft(reviewId);
  }

  // ───── Mutation handlers (called by per-card widgets) ─────

  void setScore(String monthlyScoreId, double? newScore) {
    final updated = [
      for (final e in state.entries)
        if (e.monthlyScoreId == monthlyScoreId)
          e.copyWith(
            selfRating: newScore,
            isNotApplicable: false,
          )
        else
          e,
    ];
    state = state.copyWith(entries: updated);
    _scheduleAutoSave();
  }

  void setRemark(String monthlyScoreId, String remark) {
    final updated = [
      for (final e in state.entries)
        if (e.monthlyScoreId == monthlyScoreId)
          e.copyWith(selfRemark: remark)
        else
          e,
    ];
    state = state.copyWith(entries: updated);
    _scheduleAutoSave();
  }

  /// Attaches a locally-picked proof file to a cell. Stored in the
  /// draft only — there is no server upload endpoint yet.
  void setAttachment(String monthlyScoreId, String name, String path) {
    final updated = [
      for (final e in state.entries)
        if (e.monthlyScoreId == monthlyScoreId)
          e.copyWith(attachmentName: name, attachmentPath: path)
        else
          e,
    ];
    state = state.copyWith(entries: updated);
    _scheduleAutoSave();
  }

  /// Removes a cell's attached proof file.
  void clearAttachment(String monthlyScoreId) {
    final updated = [
      for (final e in state.entries)
        if (e.monthlyScoreId == monthlyScoreId)
          e.copyWith(attachmentName: null, attachmentPath: null)
        else
          e,
    ];
    state = state.copyWith(entries: updated);
    _scheduleAutoSave();
  }

  void toggleNotApplicable(String monthlyScoreId, bool isNotApplicable) {
    final updated = [
      for (final e in state.entries)
        if (e.monthlyScoreId == monthlyScoreId)
          e.copyWith(
            isNotApplicable: isNotApplicable,
            // Clear the rating when flagging N/A — the server will
            // store null on the cell anyway.
            selfRating: isNotApplicable ? null : e.selfRating,
          )
        else
          e,
    ];
    state = state.copyWith(entries: updated);
    _scheduleAutoSave();
  }

  // ───── Submit ─────

  /// Submits the form. Returns the freshly-refreshed [MyReview] on
  /// success or `null` on error (state carries the error message).
  ///
  /// Server-side validation can still reject the payload (locked month,
  /// past deadline, out-of-range score) — error codes are mapped to
  /// AppStrings before surfacing.
  Future<MyReview?> submit() async {
    final reviewId = state.reviewId;
    if (reviewId == null) return null;
    if (!state.isComplete) {
      state =
          state.copyWith(submitError: AppStrings.selfRateErrorIncompleteScores);
      return null;
    }
    state = state.copyWith(isSubmitting: true, submitError: null);
    try {
      final request = SelfRateRequest.fromEntries(state.entries);
      final updated = await _repo.submitSelfRating(
        reviewId: reviewId,
        request: request,
      );
      // Clear the local draft — submission succeeded.
      await _clearDraft(reviewId);
      // Refresh dependent providers so home / history pick up the
      // new review state without a manual refetch.
      _ref.invalidate(employeeDashboardProvider);
      _ref.invalidate(myReviewDetailProvider(reviewId));
      _ref.invalidate(myKraAssignmentsProvider(updated.reviewCycleId));
      state = state.copyWith(
        review: updated,
        lastSubmittedReview: updated,
        isSubmitting: false,
        isLocked: !updated.state.isSelfEditable,
      );
      return updated;
    } on ApiError catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        submitError: _mapServerError(e),
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

  /// Drops any error / pending-draft and resets the loaded flag so the
  /// next entry into the screen does a fresh load. Used by the success
  /// screen's "Back to home" CTA.
  void reset() {
    _autoSaveTimer?.cancel();
    _hasMutatedSinceLastSave = false;
    state = const SelfRateState();
  }

  // ───── Internal helpers ─────

  /// Builds the form's entry list from a review + active month. Only
  /// includes rows whose scoreSource accepts a self-rating and whose
  /// active-month cell is not feed-only.
  List<KraScoreEntry> _materialiseEntries(MyReview review, String? monthId) {
    if (monthId == null) return const [];
    final List<KraScoreEntry> out = [];
    for (final row in review.rows) {
      // FEED rows aren't self-rateable.
      if (row.scoreSource == ScoreSource.feed) continue;
      final cell = row.monthlyScores.firstWhere(
        (m) => m.monthId == monthId,
        orElse: () => MonthlyScore(id: '', monthId: monthId),
      );
      if (cell.id.isEmpty) continue;
      out.add(KraScoreEntry.fromRowAndCell(row, cell));
    }
    out.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return out;
  }

  void _scheduleAutoSave() {
    _hasMutatedSinceLastSave = true;
    _autoSaveTimer ??= Timer.periodic(
      _autoSaveInterval,
      (_) => _maybeFlushAutoSave(),
    );
  }

  Future<void> _maybeFlushAutoSave() async {
    if (!_hasMutatedSinceLastSave) return;
    final reviewId = state.reviewId;
    if (reviewId == null) return;
    _hasMutatedSinceLastSave = false;
    state = state.copyWith(isAutoSaving: true);
    try {
      await _persistDraft(
        reviewId: reviewId,
        monthId: state.activeMonthId,
        entries: state.entries,
      );
    } catch (_) {
      // Auto-save is best-effort — surfacing a SharedPreferences
      // failure to the user would just be noise. The next tick retries.
      _hasMutatedSinceLastSave = true;
    } finally {
      state = state.copyWith(isAutoSaving: false);
    }
  }

  Future<void> _persistDraft({
    required String reviewId,
    required String? monthId,
    required List<KraScoreEntry> entries,
  }) async {
    final prefs = await _ref.read(sharedPreferencesProvider.future);
    final envelope = SelfRateDraftEnvelope(
      version: SelfRateDraftEnvelope.currentVersion,
      reviewId: reviewId,
      monthId: monthId,
      entries: entries.where((e) => e.isFilled).toList(),
      savedAt: DateTime.now(),
    );
    if (envelope.entries.isEmpty) {
      // Nothing to save — clear any stale draft.
      await prefs.remove(SelfRateDraftEnvelope.keyFor(reviewId));
      return;
    }
    await prefs.setString(
      SelfRateDraftEnvelope.keyFor(reviewId),
      jsonEncode(envelope.toJson()),
    );
  }

  Future<SelfRateDraftEnvelope?> _loadDraft(String reviewId) async {
    try {
      final prefs = await _ref.read(sharedPreferencesProvider.future);
      final raw = prefs.getString(SelfRateDraftEnvelope.keyFor(reviewId));
      if (raw == null) return null;
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      return SelfRateDraftEnvelope.tryFromJson(json);
    } catch (_) {
      // Malformed draft — drop it rather than crash the screen.
      return null;
    }
  }

  Future<void> _clearDraft(String reviewId) async {
    try {
      final prefs = await _ref.read(sharedPreferencesProvider.future);
      await prefs.remove(SelfRateDraftEnvelope.keyFor(reviewId));
    } catch (_) {
      // Ignore — at worst the resume prompt fires next time, and the
      // user can decline it.
    }
  }

  static String _mapServerError(ApiError e) {
    switch (e.code) {
      case 'REVIEW_ALREADY_RATED':
        return AppStrings.selfRateErrorAlreadyRated;
      case 'MONTH_LOCKED':
        return AppStrings.selfRateErrorMonthLocked;
      case 'DEADLINE_PASSED':
        return AppStrings.selfRateErrorDeadlinePassed;
      case 'SCORE_OUT_OF_RANGE':
        return AppStrings.selfRateErrorScoreOutOfRange;
      case 'INCOMPLETE_SCORES':
        return AppStrings.selfRateErrorIncompleteScores;
      default:
        return e.message;
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    super.dispose();
  }
}

/// Resume metadata exposed to the screen so it can format the "Resume
/// draft from 30 seconds ago?" prompt without unwrapping the envelope.
class DraftResumeInfo {
  final DateTime savedAt;
  final int entryCount;
  const DraftResumeInfo({required this.savedAt, required this.entryCount});
}

/// The notifier. autoDispose'd so the form's in-memory state is fresh
/// every time the user enters the self-rate tab — the persisted draft
/// is the source of truth across re-opens.
final selfRateProvider =
    StateNotifierProvider.autoDispose<SelfRateNotifier, SelfRateState>((ref) {
  return SelfRateNotifier(
    ref,
    ref.watch(selfRateRepositoryProvider),
  );
});
