import 'package:flutter/material.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../../data/models/my_review_detail.dart';
import '../../../widgets/_formatters.dart';
import '../../../widgets/review_state_badge.dart';
import '../../../widgets/score_pill.dart';

/// One card in the review-history list. Shows at-a-glance scores —
/// self / manager / final — plus the earned amount when finalised.
/// Tap routes to the [ReviewDetailScreen].
class ReviewHistoryCard extends StatelessWidget {
  final MyReview review;
  final VoidCallback onTap;
  const ReviewHistoryCard({
    super.key,
    required this.review,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cycle = review.reviewCycle;
    final earned = review.payableIncentive;
    final hasEarned = earned != null && earned > 0;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cycle?.name ?? 'Cycle',
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (cycle?.fyLabel != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            cycle!.fyLabel!,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ReviewStateBadge(state: review.state, compact: true),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _ScoreColumn(
                    label: AppStrings.historyScoreSelf,
                    score: review.finalAvgSelfPct,
                    tone: ScorePillTone.self,
                  ),
                  const SizedBox(width: 12),
                  _ScoreColumn(
                    label: AppStrings.historyScoreManager,
                    score: review.finalAvgManagerPct,
                    tone: ScorePillTone.manager,
                  ),
                  const SizedBox(width: 12),
                  _ScoreColumn(
                    label: AppStrings.historyScoreFinal,
                    score: review.finalAvgManagerPct,
                    tone: ScorePillTone.finalised,
                  ),
                  const Spacer(),
                  if (hasEarned)
                    _EarnedPill(amount: earned),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreColumn extends StatelessWidget {
  final String label;
  final double? score;
  final ScorePillTone tone;
  const _ScoreColumn({
    required this.label,
    required this.score,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: AppColors.textSecondary,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 4),
        ScorePill(
          score: score,
          maxScore: null,
          asPercentage: true,
          tone: tone,
          small: true,
        ),
      ],
    );
  }
}

class _EarnedPill extends StatelessWidget {
  final double amount;
  const _EarnedPill({required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.payments_rounded,
            size: 13,
            color: AppColors.success,
          ),
          const SizedBox(width: 4),
          Text(
            EmployeeFormatters.currencyInr(amount),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppColors.success,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
