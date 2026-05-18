import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../../../../core/router/app_router.dart';
import '../../../../../../core/widgets/shimmer_box.dart';
import '../../../../../../core/widgets/shimmer_skeletons.dart';
import '../../../../../hr/presentation/widgets/confirm_action_dialog.dart';
import '../../../providers/manager_rate_providers.dart';
import 'widgets/auto_save_indicator.dart';
import 'widgets/manager_total_footer.dart';
import 'widgets/quarterly_review_matrix.dart';

/// The manager-rate matrix screen. Loads the review on mount via
/// the notifier, hands off the matrix UI to
/// [QuarterlyReviewMatrix], and shows the sticky footer.
///
/// Submit → routes to the review screen (final summary before POST).
class ManagerRateScreen extends ConsumerStatefulWidget {
  final String reviewId;
  const ManagerRateScreen({super.key, required this.reviewId});

  @override
  ConsumerState<ManagerRateScreen> createState() =>
      _ManagerRateScreenState();
}

class _ManagerRateScreenState extends ConsumerState<ManagerRateScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(managerRateProvider.notifier).load(widget.reviewId);
    });
  }

  Future<bool> _confirmDiscardIfDirty() async {
    final state = ref.read(managerRateProvider);
    // No edits queued → safe to leave.
    if (state.lastSavedAt != null || !state.isAutoSaving) {
      // Auto-save means changes are durable on the server — leaving
      // is safe; just confirm we're not mid-flight.
      if (!state.isAutoSaving) return true;
    }
    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.managerRateUnsavedTitle,
      message: AppStrings.managerRateUnsavedMessage,
      confirmLabel: AppStrings.commonDiscard,
      cancelLabel: AppStrings.commonCancel,
      icon: Icons.edit_note_rounded,
      accentColor: AppColors.error,
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(managerRateProvider);
    final review = state.review;

    return PopScope(
      canPop: !state.isAutoSaving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!await _confirmDiscardIfDirty()) return;
        if (!context.mounted) return;
        context.go(
          AppRoutes.managerReviewDetail(widget.reviewId),
        );
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            review?.employee.name == null
                ? AppStrings.managerRateTitle
                : '${AppStrings.managerRateTitle} '
                    '— ${review!.employee.name.split(" ").first}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: AppStrings.commonClose,
            onPressed: () async {
              if (await _confirmDiscardIfDirty() && context.mounted) {
                context.go(
                  AppRoutes.managerReviewDetail(widget.reviewId),
                );
              }
            },
          ),
          actions: const [AutoSaveIndicator()],
        ),
        body: _buildBody(state),
        bottomNavigationBar: review == null
            ? null
            : ManagerTotalFooter(
                weightedTotalPct: state.weightedTotalPct,
                filledCount: _filledCount(state),
                totalCount: _totalCount(state),
                primaryLabel: AppStrings.managerRateReviewCta,
                isPrimaryEnabled: state.isComplete,
                isSubmitting: state.isSubmitting,
                onPrimary: () => context
                    .go(AppRoutes.managerRateReview(widget.reviewId)),
              ),
      ),
    );
  }

  int _filledCount(ManagerRateState s) {
    final review = s.review;
    if (review == null) return 0;
    int n = 0;
    for (final row in review.rows) {
      for (final c in row.monthlyScores) {
        if (c.isNotApplicable) continue;
        if (!c.isEditable) continue;
        if (c.managerRating != null) n++;
      }
    }
    return n;
  }

  int _totalCount(ManagerRateState s) {
    final review = s.review;
    if (review == null) return 0;
    int n = 0;
    for (final row in review.rows) {
      for (final c in row.monthlyScores) {
        if (c.isNotApplicable) continue;
        if (!c.isEditable) continue;
        n++;
      }
    }
    return n;
  }

  Widget _buildBody(ManagerRateState state) {
    if (state.isLoading) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ShimmerBox(height: 100, borderRadius: 14),
          SizedBox(height: 14),
          KraTableSkeleton(),
        ],
      );
    }
    if (state.loadError != null) {
      return _LoadError(
        message: state.loadError!,
        onRetry: () =>
            ref.read(managerRateProvider.notifier).load(widget.reviewId),
      );
    }
    if (state.review == null) {
      return const Center(child: Text(AppStrings.errorGeneric));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
      children: const [QuarterlyReviewMatrix()],
    );
  }
}

class _LoadError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _LoadError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 44,
              color: AppColors.error,
            ),
            const SizedBox(height: 12),
            const Text(
              AppStrings.errorGeneric,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
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
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(AppStrings.commonRetry),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryPurple,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
