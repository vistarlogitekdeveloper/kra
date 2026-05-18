import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/router/app_router.dart';
import '../../../../../core/widgets/shimmer_skeletons.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/my_review_detail.dart';
import '../../providers/my_review_providers.dart';
import '../../widgets/_formatters.dart';
import '../../widgets/review_state_badge.dart';
import '../../widgets/score_pill.dart';
import 'widgets/score_comparison_table.dart';
import 'widgets/score_progression_chart.dart';

/// Drill-down for a single review. Shows the lifecycle timeline, the
/// per-row × per-month comparison matrix, the progression chart, and
/// — if finalised — the incentive earned card. If the user is still
/// allowed to edit (state == SELF_RATED, manager hasn't reviewed yet)
/// a CTA at the bottom kicks them back into the self-rate form.
class ReviewDetailScreen extends ConsumerWidget {
  final String reviewId;
  const ReviewDetailScreen({super.key, required this.reviewId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(myReviewDetailProvider(reviewId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: detail.maybeWhen(
          data: (r) => Text(
            r.reviewCycle?.name ?? AppStrings.commonView,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          orElse: () => const Text(
            AppStrings.commonView,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go(AppRoutes.employeeHistory),
        ),
      ),
      body: detail.when(
        loading: () => const _DetailLoading(),
        error: (e, _) => _DetailError(
          message: e.toString(),
          onRetry: () => ref.invalidate(myReviewDetailProvider(reviewId)),
        ),
        data: (review) => _DetailBody(review: review),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Body
// ─────────────────────────────────────────────────────────────────────

class _DetailBody extends StatelessWidget {
  final MyReview review;
  const _DetailBody({required this.review});

  @override
  Widget build(BuildContext context) {
    final isEditable = review.state.isSelfEditable &&
        !(review.state == ReviewState.employeeSubmittedAll);
    final earned = review.payableIncentive;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _HeaderBlock(review: review),
        const SizedBox(height: 14),
        _TimelineStrip(state: review.state),
        const SizedBox(height: 22),
        const _SectionLabel(text: 'Per-KRA scores'),
        const SizedBox(height: 8),
        ScoreComparisonTable(review: review),
        ScoreProgressionChart(review: review),
        if (review.state == ReviewState.finalized ||
            review.state == ReviewState.acknowledged) ...[
          const SizedBox(height: 12),
          _IncentiveCard(amount: earned ?? 0),
        ],
        if (isEditable) ...[
          const SizedBox(height: 20),
          _EditSubmissionButton(),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Header (state badge + final totals)
// ─────────────────────────────────────────────────────────────────────

class _HeaderBlock extends StatelessWidget {
  final MyReview review;
  const _HeaderBlock({required this.review});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  review.reviewCycle?.name ?? '—',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              ReviewStateBadge(state: review.state),
            ],
          ),
          if (review.reviewCycle?.fyLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              review.reviewCycle!.fyLabel!,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              _TotalBlock(
                label: AppStrings.historyScoreSelf,
                value: review.finalAvgSelfPct,
                tone: ScorePillTone.self,
              ),
              const SizedBox(width: 14),
              _TotalBlock(
                label: AppStrings.historyScoreManager,
                value: review.finalAvgManagerPct,
                tone: ScorePillTone.manager,
              ),
              const SizedBox(width: 14),
              _TotalBlock(
                label: AppStrings.historyScoreFinal,
                value: review.finalAvgManagerPct,
                tone: ScorePillTone.finalised,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TotalBlock extends StatelessWidget {
  final String label;
  final double? value;
  final ScorePillTone tone;
  const _TotalBlock({
    required this.label,
    required this.value,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          ScorePill(
            score: value,
            maxScore: null,
            asPercentage: true,
            tone: tone,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Timeline (5 dots: DRAFT → SELF → MANAGER → … → FINALIZED)
// ─────────────────────────────────────────────────────────────────────

class _TimelineStrip extends StatelessWidget {
  final ReviewState state;
  const _TimelineStrip({required this.state});

  static const _steps = [
    _TimelineStep(label: AppStrings.historyTimelineDraft, stepIndex: 1),
    _TimelineStep(label: AppStrings.historyTimelineSelfRated, stepIndex: 2),
    _TimelineStep(
      label: AppStrings.historyTimelineManagerReviewed,
      stepIndex: 3,
    ),
    _TimelineStep(label: AppStrings.historyTimelineFinalized, stepIndex: 5),
  ];

  @override
  Widget build(BuildContext context) {
    final current = state.pipelineStep;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (int i = 0; i < _steps.length; i++) ...[
            _Dot(active: _steps[i].stepIndex <= current),
            Expanded(
              child: Container(
                height: 2,
                color: i == _steps.length - 1
                    ? Colors.transparent
                    : (_steps[i + 1].stepIndex <= current
                        ? AppColors.primaryPurple
                        : AppColors.divider),
              ),
            ),
            if (i == _steps.length - 1)
              const SizedBox.shrink(),
          ],
        ],
      ),
    );
  }
}

class _TimelineStep {
  final String label;
  final int stepIndex;
  const _TimelineStep({required this.label, required this.stepIndex});
}

class _Dot extends StatelessWidget {
  final bool active;
  const _Dot({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? AppColors.primaryPurple : AppColors.divider,
        border: Border.all(
          color: active ? AppColors.primaryPurple : AppColors.divider,
          width: 2,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Earned incentive card (only when finalised)
// ─────────────────────────────────────────────────────────────────────

class _IncentiveCard extends StatelessWidget {
  final double amount;
  const _IncentiveCard({required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.success.withValues(alpha: 0.4), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.payments_rounded,
              color: AppColors.success,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  AppStrings.historyDetailIncentiveLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  EmployeeFormatters.currencyInr(amount),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.success,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Loading + error
// ─────────────────────────────────────────────────────────────────────

class _DetailLoading extends StatelessWidget {
  const _DetailLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        DashboardCardSkeleton(),
        SizedBox(height: 14),
        KraTableSkeleton(),
      ],
    );
  }
}

class _DetailError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _DetailError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
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
        Center(
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(AppStrings.commonRetry),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryPurple,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// "Edit submission" CTA — when the user is still allowed to edit
// ─────────────────────────────────────────────────────────────────────

class _EditSubmissionButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => context.go(AppRoutes.employeeSelfRate),
          icon: const Icon(Icons.edit_rounded),
          label: const Text(
            AppStrings.historyDetailEditSubmission,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryPurple,
            side: BorderSide(
              color: AppColors.primaryPurple.withValues(alpha: 0.4),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Tiny utility
// ─────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppColors.textSecondary,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}
