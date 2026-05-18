import 'package:flutter/material.dart';

import '../../../../../../../core/constants/app_colors.dart';
import '../../../../../../employee/data/models/enums.dart';
import '../../../../../../employee/presentation/widgets/_formatters.dart';
import '../../../../../data/models/manager_review_detail.dart';
import '../../../../../data/models/monthly_score.dart';
import '../../../../../data/models/review_row.dart';
import 'readonly_score_cell.dart';
import 'score_cell.dart';

/// Phone-friendly matrix layout. One expandable card per KRA;
/// inside each card a vertical list of month cells.
///
/// The expansion state lives on the per-card `ExpansionTile` so the
/// user can keep multiple rows open at once if they want to compare.
class MatrixAccordionView extends StatelessWidget {
  final ManagerReviewDetail review;
  final void Function(String monthlyScoreId, double? rating)
      onScoreChanged;
  final void Function(String monthlyScoreId, String? remark)
      onRemarkChanged;

  const MatrixAccordionView({
    super.key,
    required this.review,
    required this.onScoreChanged,
    required this.onRemarkChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in review.rows) ...[
            _RowCard(
              row: row,
              months: review.cycle.months,
              onScoreChanged: onScoreChanged,
              onRemarkChanged: onRemarkChanged,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  final ReviewRow row;
  final List<ManagerReviewMonth> months;
  final void Function(String monthlyScoreId, double? rating)
      onScoreChanged;
  final void Function(String monthlyScoreId, String? remark)
      onRemarkChanged;

  const _RowCard({
    required this.row,
    required this.months,
    required this.onScoreChanged,
    required this.onRemarkChanged,
  });

  /// Headline summary number — the row's average of filled manager
  /// ratings, so the manager can see at-a-glance progress before
  /// expanding.
  double? _rowAverage() {
    final scored = row.monthlyScores
        .where((c) =>
            !c.isNotApplicable &&
            c.monthStatus == ReviewMonthStatus.open &&
            c.managerRating != null)
        .map((c) => c.managerRating!)
        .toList();
    if (scored.isEmpty) return null;
    return scored.reduce((a, b) => a + b) / scored.length;
  }

  /// Count of cells filled / cells that need filling — drives the
  /// trailing "(2 / 3)" count chip.
  ({int filled, int needed}) _counts() {
    int filled = 0;
    int needed = 0;
    for (final c in row.monthlyScores) {
      if (c.isNotApplicable) continue;
      if (c.monthStatus != ReviewMonthStatus.open) continue;
      needed++;
      if (c.managerRating != null) filled++;
    }
    return (filled: filled, needed: needed);
  }

  @override
  Widget build(BuildContext context) {
    final counts = _counts();
    final isComplete = counts.needed > 0 && counts.filled >= counts.needed;
    final avg = _rowAverage();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isComplete
              ? AppColors.success.withValues(alpha: 0.6)
              : AppColors.divider,
          width: isComplete ? 1.4 : 1,
        ),
      ),
      child: Theme(
        // ExpansionTile inherits divider colours from the surrounding
        // theme; swap them to transparent so the card border is the
        // only edge we see.
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.fromLTRB(16, 4, 12, 4),
          childrenPadding:
              const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: AppColors.primaryPurple,
          collapsedIconColor: AppColors.textSecondary,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  row.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.2,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _CountPill(
                filled: counts.filled,
                needed: counts.needed,
                isComplete: isComplete,
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryPurpleSurface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    EmployeeFormatters.weightagePercent(
                        row.weightagePercent),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryPurple,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                if (row.category != null && row.category!.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      row.category!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.accentOrange,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
                if (avg != null) ...[
                  const Spacer(),
                  Text(
                    EmployeeFormatters.scoreOutOf(avg, row.maxScore),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryPurple,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          children: [
            if (row.description != null &&
                row.description!.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  row.description!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
              ),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 12),
            ],
            for (int i = 0; i < months.length; i++) ...[
              _MonthBlock(
                row: row,
                month: months[i],
                onScoreChanged: onScoreChanged,
                onRemarkChanged: onRemarkChanged,
              ),
              if (i != months.length - 1) const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _MonthBlock extends StatelessWidget {
  final ReviewRow row;
  final ManagerReviewMonth month;
  final void Function(String monthlyScoreId, double? rating)
      onScoreChanged;
  final void Function(String monthlyScoreId, String? remark)
      onRemarkChanged;

  const _MonthBlock({
    required this.row,
    required this.month,
    required this.onScoreChanged,
    required this.onRemarkChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cell = row.monthlyScores.firstWhere(
      (c) => c.monthId == month.id,
      orElse: () => MonthlyScore(
        monthlyScoreId: '',
        monthId: month.id,
        monthLabel: month.monthLabel,
        monthStatus: month.status,
      ),
    );
    if (cell.monthlyScoreId.isEmpty) return const SizedBox.shrink();
    final isFeed = row.scoreSource == ScoreSource.feed;
    final monthClosed = month.status != ReviewMonthStatus.open;
    final cellWidget =
        (isFeed || monthClosed || cell.isNotApplicable)
            ? ReadonlyScoreCell(
                cell: cell,
                maxScore: row.maxScore,
                isFeedRow: isFeed,
              )
            : ScoreCell(
                cell: cell,
                maxScore: row.maxScore,
                onScoreChanged: (v) =>
                    onScoreChanged(cell.monthlyScoreId, v),
                onRemarkChanged: (v) =>
                    onRemarkChanged(cell.monthlyScoreId, v),
              );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text(
                month.monthLabel.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              if (monthClosed) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.lock_rounded,
                  size: 11,
                  color: AppColors.textMuted,
                ),
              ],
            ],
          ),
        ),
        cellWidget,
      ],
    );
  }
}

class _CountPill extends StatelessWidget {
  final int filled;
  final int needed;
  final bool isComplete;
  const _CountPill({
    required this.filled,
    required this.needed,
    required this.isComplete,
  });

  @override
  Widget build(BuildContext context) {
    if (needed == 0) return const SizedBox.shrink();
    final fg = isComplete ? AppColors.success : AppColors.accentOrange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '$filled / $needed',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: fg,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
