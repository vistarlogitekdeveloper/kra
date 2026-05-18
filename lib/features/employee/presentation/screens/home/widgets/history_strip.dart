import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../../../../core/widgets/shimmer_box.dart';
import '../../../../data/models/enums.dart';
import '../../../../data/models/my_review_detail.dart';
import '../../../providers/my_review_providers.dart';
import '../../../widgets/_formatters.dart';

/// Horizontally scrolling strip of the user's most recent reviews.
///
/// Each chip is one CYCLE-level review (the new contract has one review
/// per cycle — the per-month dimension lives inside it as the
/// `rows[].monthlyScores[]` matrix). Tap → detail screen.
class HistoryStrip extends ConsumerWidget {
  /// Tapped when the user picks a chip. The id is the review's id —
  /// the caller is expected to push the detail route.
  final void Function(String reviewId) onTapReview;

  const HistoryStrip({super.key, required this.onTapReview});

  static const int _chipCount = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(myReviewListProvider);

    Widget body;
    if (state.isInitialLoading) {
      body = _buildLoading();
    } else if (state.error != null) {
      body = _buildError(state.error!);
    } else if (state.reviews.isEmpty) {
      body = _buildEmpty();
    } else {
      final preview = state.reviews.take(_chipCount).toList(growable: false);
      body = _buildLoaded(preview);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              AppStrings.homeHistoryStripTitle,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(height: 10),
          body,
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, __) =>
            const ShimmerBox(width: 120, height: 88, borderRadius: 14),
      ),
    );
  }

  Widget _buildError(String message) {
    return Container(
      height: 88,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.error, fontSize: 12),
      ),
    );
  }

  Widget _buildEmpty() {
    return Container(
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Text(
        AppStrings.historyEmptyTitle,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildLoaded(List<MyReview> previews) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: previews.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _HistoryChip(
          review: previews[i],
          onTap: () => onTapReview(previews[i].id),
        ),
      ),
    );
  }
}

class _HistoryChip extends StatelessWidget {
  final MyReview review;
  final VoidCallback onTap;
  const _HistoryChip({required this.review, required this.onTap});

  Color get _stateColor {
    switch (review.state) {
      case ReviewState.draft:
      case ReviewState.inProgress:
        return AppColors.textMuted;
      case ReviewState.employeeSubmittedAll:
        return AppColors.accentOrange;
      case ReviewState.managerRatedAll:
        return AppColors.primaryPurple;
      case ReviewState.finalized:
      case ReviewState.acknowledged:
        return AppColors.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Each chip represents one cycle. Use the cycle name (e.g.
    // "FY26 Q1") as the headline since the per-month dimension lives
    // inside the review's matrix.
    final cycleLabel = review.reviewCycle?.name ?? '—';

    // Prefer the manager's final-avg when present; fall back to the
    // employee's self-avg until the manager passes through.
    final hasFinal = review.finalAvgManagerPct != null;
    final scoreValue =
        review.finalAvgManagerPct ?? review.finalAvgSelfPct;
    final scoreText = scoreValue == null
        ? AppStrings.homeHistoryStripPending
        : EmployeeFormatters.percent(scoreValue);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 132,
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                cycleLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _stateColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  review.state.displayName,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: _stateColor,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              Text(
                scoreText,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: hasFinal
                      ? AppColors.textPrimary
                      : AppColors.textMuted,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
