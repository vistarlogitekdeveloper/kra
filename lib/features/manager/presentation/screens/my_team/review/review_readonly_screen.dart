import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../../../../core/router/app_router.dart';
import '../../../../../../core/widgets/shimmer_skeletons.dart';
import '../../../../../employee/data/models/enums.dart';
import '../../../../../employee/presentation/widgets/_formatters.dart';
import '../../../../../employee/presentation/widgets/review_state_badge.dart';
import '../../../../../employee/presentation/widgets/score_pill.dart';
import '../../../../data/models/manager_review_detail.dart';
import '../../../../data/models/monthly_score.dart';
import '../../../../data/models/review_row.dart';
import '../../../providers/manager_review_providers.dart';

/// Read-only review view. Routes to this screen when the manager opens
/// a review whose state is past the editable window (FINALIZED /
/// ACKNOWLEDGED) or whose `permissions.canEdit` is `false`.
///
/// Distinct from the rate screen by intent: this one is "look at what
/// happened" while the other is "do the rating." Layout is a horizontal-
/// scrollable matrix of self vs. manager scores per (row × month).
class ReviewReadonlyScreen extends ConsumerWidget {
  final String reviewId;
  const ReviewReadonlyScreen({super.key, required this.reviewId});

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
        loading: () => const _Loading(),
        error: (e, _) => _Error(
          message: e.toString(),
          onRetry: () =>
              ref.invalidate(managerReviewDetailProvider(reviewId)),
        ),
        data: (review) => _Body(review: review),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final ManagerReviewDetail review;
  const _Body({required this.review});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _Header(review: review),
        if (review.rows.isNotEmpty) _MatrixCard(review: review),
        if (review.managerComment != null &&
            review.managerComment!.trim().isNotEmpty)
          _CommentCard(comment: review.managerComment!),
        if (review.totals.incentiveAmount != null)
          _IncentiveCard(amount: review.totals.incentiveAmount!),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Header — slim variant focused on totals
// ─────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final ManagerReviewDetail review;
  const _Header({required this.review});

  @override
  Widget build(BuildContext context) {
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
              children: [
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
                        review.cycle.name,
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
                  child: _TotalBlock(
                    label: AppStrings.historyScoreSelf,
                    score: review.totals.selfTotal,
                    tone: ScorePillTone.self,
                  ),
                ),
                Expanded(
                  child: _TotalBlock(
                    label: AppStrings.historyScoreManager,
                    score: review.totals.managerTotal,
                    tone: ScorePillTone.manager,
                  ),
                ),
                Expanded(
                  child: _TotalBlock(
                    label: AppStrings.historyScoreFinal,
                    score: review.totals.finalTotal,
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

class _TotalBlock extends StatelessWidget {
  final String label;
  final double? score;
  final ScorePillTone tone;
  const _TotalBlock({
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
// Horizontal-scroll comparison matrix
// ─────────────────────────────────────────────────────────────────────

class _MatrixCard extends StatelessWidget {
  final ManagerReviewDetail review;
  const _MatrixCard({required this.review});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingTextStyle: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
            dataTextStyle: const TextStyle(
              fontSize: 12,
              color: AppColors.textPrimary,
            ),
            columnSpacing: 20,
            horizontalMargin: 16,
            headingRowHeight: 42,
            dataRowMinHeight: 60,
            dataRowMaxHeight: 80,
            dividerThickness: 0.6,
            columns: [
              const DataColumn(label: Text('KRA')),
              const DataColumn(label: Text('WT')),
              for (final m in review.cycle.months)
                DataColumn(label: Text(m.monthLabel.toUpperCase())),
            ],
            rows: [
              for (final row in review.rows)
                DataRow(cells: [
                  DataCell(_RowName(row: row)),
                  DataCell(Text(
                    EmployeeFormatters.weightagePercent(
                        row.weightagePercent),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  )),
                  for (final m in review.cycle.months)
                    DataCell(_Cell(row: row, monthId: m.id)),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowName extends StatelessWidget {
  final ReviewRow row;
  const _RowName({required this.row});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
          ),
          if (row.category != null && row.category!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                row.category!,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accentOrange,
                  letterSpacing: 0.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final ReviewRow row;
  final String monthId;
  const _Cell({required this.row, required this.monthId});

  @override
  Widget build(BuildContext context) {
    final cell = row.monthlyScores.firstWhere(
      (c) => c.monthId == monthId,
      orElse: () => MonthlyScore(
        monthlyScoreId: '',
        monthId: monthId,
        monthLabel: '',
        monthStatus: ReviewMonthStatus.open,
      ),
    );
    if (cell.monthlyScoreId.isEmpty || cell.isNotApplicable) {
      return const Text(
        '—',
        style: TextStyle(
          fontSize: 12,
          color: AppColors.textMuted,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ScorePill(
          score: cell.selfRating,
          maxScore: row.maxScore,
          tone: ScorePillTone.self,
          small: true,
        ),
        const SizedBox(height: 4),
        ScorePill(
          score: cell.managerRating,
          maxScore: row.maxScore,
          tone: ScorePillTone.manager,
          small: true,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Manager comment + incentive cards
// ─────────────────────────────────────────────────────────────────────

class _CommentCard extends StatelessWidget {
  final String comment;
  const _CommentCard({required this.comment});

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

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        ProfileHeaderSkeleton(),
        SizedBox(height: 14),
        KraTableSkeleton(),
      ],
    );
  }
}

class _Error extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _Error({required this.message, required this.onRetry});

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
