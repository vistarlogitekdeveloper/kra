import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/network/connectivity_service.dart';
import '../../../../../core/router/app_router.dart';
import '../../../../../core/utils/monthly_deadlines.dart';
import '../../../../../core/widgets/monthly_deadline_notice.dart';
import '../../../../../core/widgets/shimmer_skeletons.dart';
import '../../../../hr/presentation/widgets/confirm_action_dialog.dart';
import '../../providers/employee_dashboard_providers.dart';
import '../../providers/self_rate_providers.dart';
import '../../widgets/_formatters.dart';
import '../../widgets/empty_my_dashboard.dart';
import 'widgets/kra_score_input_card.dart';
import 'widgets/month_picker_chip.dart';
import 'widgets/self_rate_submit_bar.dart';
import 'widgets/weightage_progress_bar.dart';

/// The self-rate form. Loads the active review on mount, surfaces a
/// resume-draft prompt when a local draft is found, and routes onward
/// to the review / locked screens as appropriate.
class SelfRateScreen extends ConsumerStatefulWidget {
  const SelfRateScreen({super.key});

  @override
  ConsumerState<SelfRateScreen> createState() => _SelfRateScreenState();
}

class _SelfRateScreenState extends ConsumerState<SelfRateScreen> {
  /// Flips true after a submit attempt with missing scores — drives
  /// the orange "missing" highlight on incomplete cards.
  bool _showMissingHighlights = false;

  /// Guards against running the resume-draft / lock-redirect logic
  /// twice for the same load.
  bool _handledLoadSideEffects = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureLoaded();
    });
  }

  /// Resolves the active review id from the dashboard provider, then
  /// kicks off the notifier load. Pulling the id from the dashboard
  /// rather than asking the user keeps the form opening to the right
  /// review with zero clicks.
  Future<void> _ensureLoaded() async {
    final notifierState = ref.read(selfRateProvider);
    if (notifierState.reviewId != null) return; // already loaded
    final dashboard = await ref.read(employeeDashboardProvider.future);
    final reviewId = dashboard.scorecard?.reviewId;
    if (!mounted) return;
    if (reviewId == null || reviewId.isEmpty) return;
    await ref.read(selfRateProvider.notifier).load(reviewId);
  }

  // ───── Side effects on state changes ─────

  void _onStateChanged(SelfRateState? prev, SelfRateState next) {
    // If load resolved to a locked review, route to the locked screen.
    // Only fire once per load — flips back to false on reset.
    if (!_handledLoadSideEffects &&
        !next.isLoading &&
        next.isLocked &&
        next.review != null) {
      _handledLoadSideEffects = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(AppRoutes.employeeSelfRateLocked);
      });
      return;
    }
    if (!next.isLoading && next.review != null) {
      _handledLoadSideEffects = true;
    }
    // Surface submit errors as snackbars and clear them.
    final newError = next.submitError;
    if (newError != null && newError != prev?.submitError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(newError)),
      );
      ref.read(selfRateProvider.notifier).clearSubmitError();
    }
  }

  // ───── Back-press guard ─────

  Future<bool> _confirmDiscardIfDirty() async {
    final s = ref.read(selfRateProvider);
    if (!s.isDirty) return true;
    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.selfRateUnsavedTitle,
      message: AppStrings.selfRateUnsavedMessage,
      confirmLabel: AppStrings.selfRateUnsavedDiscard,
      cancelLabel: AppStrings.commonKeepEditing,
      icon: Icons.edit_note_rounded,
      accentColor: AppColors.error,
    );
    // Only the destructive 'Discard' returns true → leave.
    // 'Keep editing' (false) and outside-tap (null) → stay.
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SelfRateState>(selfRateProvider, _onStateChanged);
    final state = ref.watch(selfRateProvider);
    final isOnline = ref.watch(connectivityProvider).maybeWhen(
          data: (v) => v,
          orElse: () => true,
        );

    return PopScope(
      canPop: !state.isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmDiscardIfDirty();
        if (!ok) return;
        if (!context.mounted) return;
        // The form itself doesn't have anywhere to "go back" to inside
        // the shell — sending the user to Home is the sensible default.
        context.go(AppRoutes.employeeHome);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: _buildAppBar(state),
        body: _buildBody(state),
        bottomNavigationBar: state.review == null
            ? null
            : SelfRateSubmitBar(
                weightedTotalPct: state.weightedTotalPct,
                primaryLabel: AppStrings.selfRateReviewCta,
                isPrimaryEnabled: state.isComplete,
                isSubmitting: state.isSubmitting,
                isAutoSaving: state.isAutoSaving,
                isOffline: !isOnline,
                onPrimary: state.isComplete
                    ? () => _onReviewPressed(state)
                    : () => setState(() => _showMissingHighlights = true),
              ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(SelfRateState state) {
    final months = state.review?.reviewCycle?.months;
    String monthLabel = '';
    if (state.entries.isNotEmpty) {
      monthLabel = state.entries.first.monthLabel;
    } else if (months != null && months.isNotEmpty) {
      // Don't use firstWhere(orElse: () => months.first) — when no month
      // matches activeMonthId the orElse is fine, but an empty `months`
      // list would make `months.first` throw StateError and crash the
      // whole screen (build calls this unconditionally) instead of letting
      // the body render its empty state.
      final match = months.where((m) => m.id == state.activeMonthId);
      monthLabel = (match.isNotEmpty ? match.first : months.first).monthLabel;
    }
    final title = monthLabel.isEmpty
        ? AppStrings.selfRateTitle
        : '${AppStrings.selfRateTitle} — $monthLabel';
    return AppBar(
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: AppStrings.commonClose,
        onPressed: () async {
          if (await _confirmDiscardIfDirty() && mounted) {
            context.go(AppRoutes.employeeHome);
          }
        },
      ),
    );
  }

  Widget _buildBody(SelfRateState state) {
    if (state.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: KraTableSkeleton(),
      );
    }
    if (state.loadError != null) {
      return _LoadErrorView(
        message: state.loadError!,
        onRetry: () {
          _handledLoadSideEffects = false;
          _ensureLoaded();
        },
      );
    }
    if (state.review == null || state.entries.isEmpty) {
      return EmptyMyDashboard(
        title: AppStrings.homeMyKrasEmpty,
        message: AppStrings.homeNoActiveCycleMessage,
        onRetry: () {
          _handledLoadSideEffects = false;
          _ensureLoaded();
        },
      );
    }

    final review = state.review!;
    final months = review.reviewCycle?.months ?? const [];

    return Column(
      children: [
        MonthlyDeadlineNotice(
          title: AppStrings.deadlineSelfRatingTitle,
          deadline: MonthlyDeadlines.selfRating(),
        ),
        // Sticky top: progress bar + month picker
        WeightageProgressBar(
          weightedTotalPct: state.weightedTotalPct,
          filledCount: state.entries.where((e) => e.isFilled).length,
          totalCount: state.entries.length,
        ),
        if (months.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: MonthPickerChip(
              months: months,
              activeMonthId: state.activeMonthId,
              onSelect: (id) =>
                  ref.read(selfRateProvider.notifier).switchMonth(id),
            ),
          ),
        if (state.pendingDraft != null)
          _ResumeDraftPrompt(
            savedAt: state.pendingDraft!.savedAt,
            onResume: () => ref.read(selfRateProvider.notifier).resumeDraft(),
            onDiscard: () => ref.read(selfRateProvider.notifier).discardDraft(),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            itemCount: state.entries.length,
            itemBuilder: (_, i) {
              final entry = state.entries[i];
              return KraScoreInputCard(
                key: ValueKey(entry.monthlyScoreId),
                entry: entry,
                isHighlightedAsMissing: _showMissingHighlights,
                onScoreChanged: (v) => ref
                    .read(selfRateProvider.notifier)
                    .setScore(entry.monthlyScoreId, v),
                onRemarkChanged: (v) => ref
                    .read(selfRateProvider.notifier)
                    .setRemark(entry.monthlyScoreId, v),
                onToggleNotApplicable: (v) => ref
                    .read(selfRateProvider.notifier)
                    .toggleNotApplicable(entry.monthlyScoreId, v),
                onAttach: (name, path) => ref
                    .read(selfRateProvider.notifier)
                    .setAttachment(entry.monthlyScoreId, name, path),
                onRemoveAttachment: () => ref
                    .read(selfRateProvider.notifier)
                    .clearAttachment(entry.monthlyScoreId),
              );
            },
          ),
        ),
      ],
    );
  }

  void _onReviewPressed(SelfRateState state) {
    if (!state.isComplete) {
      setState(() => _showMissingHighlights = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.selfRateErrorIncompleteScores)),
      );
      return;
    }
    setState(() => _showMissingHighlights = false);
    context.go(AppRoutes.employeeSelfRateReview);
  }
}

// ─────────────────────────────────────────────────────────────────────
// Resume-draft prompt (inline banner)
// ─────────────────────────────────────────────────────────────────────

class _ResumeDraftPrompt extends StatelessWidget {
  final DateTime savedAt;
  final VoidCallback onResume;
  final VoidCallback onDiscard;
  const _ResumeDraftPrompt({
    required this.savedAt,
    required this.onResume,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.accentOrange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppColors.accentOrange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.history_toggle_off_rounded,
            color: AppColors.accentOrange,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  AppStrings.selfRateResumeTitle,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Last saved ${EmployeeFormatters.relativeTime(savedAt)}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onDiscard,
            child: const Text(
              AppStrings.selfRateResumeStartFresh,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          FilledButton(
            onPressed: onResume,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentOrange,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              AppStrings.selfRateResumeContinue,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Load error
// ─────────────────────────────────────────────────────────────────────

class _LoadErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _LoadErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final unwrapState = ScaffoldMessenger.maybeOf(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: AppColors.error,
              ),
              const SizedBox(height: 14),
              const Text(
                AppStrings.errorGeneric,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: () {
                  unwrapState?.hideCurrentSnackBar();
                  onRetry();
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text(AppStrings.commonRetry),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryPurple,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
