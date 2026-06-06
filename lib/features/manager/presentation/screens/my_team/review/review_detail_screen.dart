import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../../../../core/router/app_router.dart';
import '../../../../../../core/widgets/shimmer_box.dart';
import '../../../../../../core/widgets/shimmer_skeletons.dart';
import '../../../../../employee/data/models/enums.dart';
import '../../../../../employee/presentation/widgets/_formatters.dart';
import '../../../../../employee/presentation/widgets/review_state_badge.dart';
import '../../../../../employee/presentation/widgets/score_pill.dart';
import '../../../../data/models/manager_review_detail.dart';
import '../../../../data/models/review_row.dart';
import '../../../providers/manager_review_providers.dart';
import 'widgets/deadline_warning_card.dart';
import 'widgets/permissions_banner.dart';
import 'widgets/previous_reviews_strip.dart';

/// Review detail screen for a single review owned by the manager.
///
/// State-dependent UI:
///   - DRAFT / IN_PROGRESS  → "Waiting for self-rating" empty state,
///                             history strip below for context
///   - EMPLOYEE_SUBMITTED_ALL → matrix preview + primary CTA "Start
///                             rating" routing to /rate
///   - MANAGER_RATED_ALL    → matrix preview + "Edit my rating" (if
///                             permissions.canEdit) + manager comment
///                             section
///   - FINALIZED / ACKNOWLEDGED → read-only with incentive callout
///
/// Permissions banner only shows when the rate CTA is hidden.
class ReviewDetailScreen extends ConsumerWidget {
  final String reviewId;
  const ReviewDetailScreen({super.key, required this.reviewId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(managerReviewDetailProvider(reviewId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          AppStrings.managerReviewDetailTitle,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go(AppRoutes.managerTeamList),
        ),
      ),
      body: async.when(
        loading: () => const _DetailLoading(),
        error: (e, _) => _DetailError(
          message: e.toString(),
          onRetry: () =>
              ref.invalidate(managerReviewDetailProvider(reviewId)),
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
  final ManagerReviewDetail review;
  const _DetailBody({required this.review});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _Header(review: review),
        DeadlineWarningCard(permissions: review.permissions),
        PermissionsBanner(
          state: review.state,
          permissions: review.permissions,
        ),
        _StateAdaptiveSection(review: review),
        if (review.previousReviews.isNotEmpty)
          PreviousReviewsStrip(reviews: review.previousReviews),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Header card — employee + cycle + totals
// ─────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final ManagerReviewDetail review;
  const _Header({required this.review});

  String _initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '·';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final totals = review.totals;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        AppColors.primaryPurple.withValues(alpha: 0.14),
                    border: Border.all(
                      color: AppColors.primaryPurple
                          .withValues(alpha: 0.40),
                      width: 1.8,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initialsOf(review.employee.name),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryPurple,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        review.employee.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${review.employee.employeeCode}  •  '
                        '${review.cycle.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                ReviewStateBadge(state: review.state),
              ],
            ),
            const Divider(color: AppColors.divider, height: 24),
            Row(
              children: [
                Expanded(
                  child: _TotalsBlock(
                    label: AppStrings.historyScoreSelf,
                    score: totals.selfTotal,
                    tone: ScorePillTone.self,
                  ),
                ),
                Expanded(
                  child: _TotalsBlock(
                    label: AppStrings.historyScoreManager,
                    score: totals.managerTotal,
                    tone: ScorePillTone.manager,
                  ),
                ),
                Expanded(
                  child: _TotalsBlock(
                    label: AppStrings.historyScoreFinal,
                    score: totals.finalTotal,
                    tone: ScorePillTone.finalised,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalsBlock extends StatelessWidget {
  final String label;
  final double? score;
  final ScorePillTone tone;

  const _TotalsBlock({
    required this.label,
    required this.score,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppColors.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        ScorePill(
          score: score,
          maxScore: null,
          asPercentage: true,
          tone: tone,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// State-adaptive middle section (the body's main affordance)
// ─────────────────────────────────────────────────────────────────────

class _StateAdaptiveSection extends StatelessWidget {
  final ManagerReviewDetail review;
  const _StateAdaptiveSection({required this.review});

  @override
  Widget build(BuildContext context) {
    switch (review.state) {
      case ReviewState.draft:
      case ReviewState.inProgress:
        return _WaitingForEmployeeCard(review: review);
      case ReviewState.employeeSubmittedAll:
        return _ReadyToRateSection(review: review);
      case ReviewState.managerRatedAll:
        return _RatedSection(review: review);
      case ReviewState.finalized:
      case ReviewState.acknowledged:
        return _FinalizedSection(review: review);
    }
  }
}

// ── DRAFT / IN_PROGRESS ──

class _WaitingForEmployeeCard extends StatelessWidget {
  final ManagerReviewDetail review;
  const _WaitingForEmployeeCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final title = review.state == ReviewState.draft
        ? AppStrings.managerReviewDetailNotStartedTitle
        : AppStrings.managerReviewDetailWaitingTitle;
    final message = review.state == ReviewState.draft
        ? AppStrings.managerReviewDetailNotStartedMessage
        : AppStrings.managerReviewDetailWaitingMessage;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.accentOrange.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.hourglass_top_rounded,
                color: AppColors.accentOrange,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${review.employee.name} $message',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── EMPLOYEE_SUBMITTED_ALL ──

class _ReadyToRateSection extends StatelessWidget {
  final ManagerReviewDetail review;
  const _ReadyToRateSection({required this.review});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _RowsPreview(review: review),
        if (review.permissions.canRate)
          _PrimaryCta(
            label: AppStrings.managerReviewDetailStartRating,
            onTap: () => context.push(AppRoutes.managerRate(review.id)),
            icon: Icons.rate_review_rounded,
          ),
      ],
    );
  }
}

// ── MANAGER_RATED_ALL ──

class _RatedSection extends StatelessWidget {
  final ManagerReviewDetail review;
  const _RatedSection({required this.review});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _RowsPreview(review: review),
        if (review.managerComment != null &&
            review.managerComment!.trim().isNotEmpty)
          _ManagerCommentCard(comment: review.managerComment!),
        if (review.permissions.canEdit)
          _PrimaryCta(
            label: AppStrings.managerReviewDetailEditRating,
            onTap: () => context.push(AppRoutes.managerRate(review.id)),
            icon: Icons.edit_rounded,
          ),
      ],
    );
  }
}

// ── FINALIZED / ACKNOWLEDGED ──

class _FinalizedSection extends StatelessWidget {
  final ManagerReviewDetail review;
  const _FinalizedSection({required this.review});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _RowsPreview(review: review),
        if (review.managerComment != null &&
            review.managerComment!.trim().isNotEmpty)
          _ManagerCommentCard(comment: review.managerComment!),
        if (review.totals.incentiveAmount != null)
          _IncentiveCard(amount: review.totals.incentiveAmount!),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Shared content fragments
// ─────────────────────────────────────────────────────────────────────

class _RowsPreview extends StatelessWidget {
  final ManagerReviewDetail review;
  const _RowsPreview({required this.review});

  @override
  Widget build(BuildContext context) {
    if (review.rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: [
            for (int i = 0; i < review.rows.length; i++) ...[
              _RowPreviewTile(row: review.rows[i]),
              if (i != review.rows.length - 1)
                const Divider(
                  color: AppColors.divider,
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RowPreviewTile extends StatelessWidget {
  final ReviewRow row;
  const _RowPreviewTile({required this.row});

  /// Weighted average of the row's manager scores (preferred) or
  /// self scores (fallback). N/A cells excluded from the denominator.
  double? _avgScore() {
    final usable = row.monthlyScores.where((c) => !c.isNotApplicable);
    if (usable.isEmpty) return null;
    final mgr =
        usable.map((c) => c.managerRating).whereType<double>().toList();
    final pool = mgr.isNotEmpty
        ? mgr
        : usable
            .map((c) => c.selfRating)
            .whereType<double>()
            .toList();
    if (pool.isEmpty) return null;
    final sum = pool.fold<double>(0, (a, b) => a + b);
    return sum / pool.length;
  }

  @override
  Widget build(BuildContext context) {
    final avg = _avgScore();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  row.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${EmployeeFormatters.weightagePercent(row.weightagePercent)}'
                  '${row.category != null ? "  •  ${row.category}" : ""}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ScorePill(
            score: avg,
            maxScore: row.maxScore,
            tone: ScorePillTone.manager,
            small: true,
          ),
        ],
      ),
    );
  }
}

class _PrimaryCta extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _PrimaryCta({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryPurple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: Icon(icon, size: 18),
          label: Text(
            label,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _ManagerCommentCard extends StatelessWidget {
  final String comment;
  const _ManagerCommentCard({required this.comment});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              AppStrings.managerReviewDetailManagerComment,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              comment,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncentiveCard extends StatelessWidget {
  final double amount;
  const _IncentiveCard({required this.amount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: AppColors.success.withValues(alpha: 0.35), width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.payments_rounded,
                color: AppColors.success,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    AppStrings.managerReviewDetailIncentive,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    EmployeeFormatters.currencyInr(amount),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.success,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: const [
        ProfileHeaderSkeleton(),
        SizedBox(height: 14),
        ShimmerBox(height: 110, borderRadius: 16),
        SizedBox(height: 14),
        ShimmerBox(height: 78, borderRadius: 14),
        SizedBox(height: 12),
        ShimmerBox(height: 78, borderRadius: 14),
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
      ),
    );
  }
}
