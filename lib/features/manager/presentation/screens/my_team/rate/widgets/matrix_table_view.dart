import 'package:flutter/material.dart';

import '../../../../../../../core/constants/app_colors.dart';
import '../../../../../../employee/data/models/enums.dart';
import '../../../../../../employee/presentation/widgets/_formatters.dart';
import '../../../../../data/models/manager_review_detail.dart';
import '../../../../../data/models/monthly_score.dart';
import '../../../../../data/models/review_row.dart';
import 'month_column_header.dart';
import 'readonly_score_cell.dart';
import 'score_cell.dart';

/// Wide-viewport (≥720px) matrix layout. Renders one row per KRA,
/// one column per month. Manager input fields are inline in each
/// cell so the manager can scan across a row without scrolling.
///
/// On narrower screens the parent [MatrixViewResponsive] swaps in
/// the accordion view instead — this layout assumes there's enough
/// horizontal room to render the columns comfortably.
class MatrixTableView extends StatelessWidget {
  final ManagerReviewDetail review;
  final void Function(String monthlyScoreId, double? rating)
      onScoreChanged;
  final void Function(String monthlyScoreId, String? remark)
      onRemarkChanged;

  const MatrixTableView({
    super.key,
    required this.review,
    required this.onScoreChanged,
    required this.onRemarkChanged,
  });

  @override
  Widget build(BuildContext context) {
    final months = review.cycle.months;
    const rowFlex = 5;
    const monthFlex = 3;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header row ──
          Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppColors.divider,
                  width: 1,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Expanded(
                  flex: rowFlex,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'KRA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                for (final m in months)
                  Expanded(
                    flex: monthFlex,
                    child: MonthColumnHeader(month: m),
                  ),
              ],
            ),
          ),

          // ── Data rows ──
          for (int i = 0; i < review.rows.length; i++) ...[
            _DataRow(
              row: review.rows[i],
              months: months,
              rowFlex: rowFlex,
              monthFlex: monthFlex,
              onScoreChanged: onScoreChanged,
              onRemarkChanged: onRemarkChanged,
            ),
            if (i != review.rows.length - 1)
              const Divider(
                color: AppColors.divider,
                height: 1,
                indent: 12,
                endIndent: 12,
              ),
          ],
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final ReviewRow row;
  final List<ManagerReviewMonth> months;
  final int rowFlex;
  final int monthFlex;
  final void Function(String monthlyScoreId, double? rating)
      onScoreChanged;
  final void Function(String monthlyScoreId, String? remark)
      onRemarkChanged;

  const _DataRow({
    required this.row,
    required this.months,
    required this.rowFlex,
    required this.monthFlex,
    required this.onScoreChanged,
    required this.onRemarkChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: rowFlex, child: _RowMeta(row: row)),
          for (final month in months)
            Expanded(
              flex: monthFlex,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _CellPicker(
                  row: row,
                  month: month,
                  onScoreChanged: onScoreChanged,
                  onRemarkChanged: onRemarkChanged,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RowMeta extends StatelessWidget {
  final ReviewRow row;
  const _RowMeta({required this.row});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          row.name,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            height: 1.3,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primaryPurpleSurface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                EmployeeFormatters.weightagePercent(row.weightagePercent),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryPurple,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            if (row.category != null && row.category!.isNotEmpty)
              Text(
                row.category!,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accentOrange,
                  letterSpacing: 0.4,
                ),
              ),
          ],
        ),
        if (row.description != null && row.description!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            row.description!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}

class _CellPicker extends StatelessWidget {
  final ReviewRow row;
  final ManagerReviewMonth month;
  final void Function(String monthlyScoreId, double? rating)
      onScoreChanged;
  final void Function(String monthlyScoreId, String? remark)
      onRemarkChanged;

  const _CellPicker({
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
    if (cell.monthlyScoreId.isEmpty) {
      return const SizedBox.shrink();
    }
    final isFeed = row.scoreSource == ScoreSource.feed;
    final monthClosed = month.status != ReviewMonthStatus.open;
    if (isFeed || monthClosed || cell.isNotApplicable) {
      return ReadonlyScoreCell(
        cell: cell,
        maxScore: row.maxScore,
        isFeedRow: isFeed,
      );
    }
    return ScoreCell(
      cell: cell,
      maxScore: row.maxScore,
      onScoreChanged: (v) =>
          onScoreChanged(cell.monthlyScoreId, v),
      onRemarkChanged: (v) =>
          onRemarkChanged(cell.monthlyScoreId, v),
    );
  }
}
