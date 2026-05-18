import 'package:flutter/material.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../data/models/my_review_detail.dart';
import '../../../widgets/_formatters.dart';
import '../../../widgets/score_pill.dart';

/// Row-by-row, column-by-column matrix of scores for a single review.
/// Rows are KRA items. Columns are months. Each cell renders a self
/// score and (if present) a manager score below.
///
/// Long-press a cell to surface the per-cell comment in a bottom sheet —
/// kept out of the table itself to keep rows compact.
class ScoreComparisonTable extends StatelessWidget {
  final MyReview review;
  const ScoreComparisonTable({super.key, required this.review});

  @override
  Widget build(BuildContext context) {
    final months = review.reviewCycle?.months ?? const [];
    final rows = review.rows;
    if (rows.isEmpty || months.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
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
          columnSpacing: 18,
          horizontalMargin: 16,
          headingRowHeight: 42,
          dataRowMinHeight: 56,
          dataRowMaxHeight: 76,
          dividerThickness: 0.6,
          columns: [
            const DataColumn(label: Text('KRA')),
            const DataColumn(label: Text('WT')),
            for (final m in months)
              DataColumn(label: Text(m.monthLabel.toUpperCase())),
          ],
          rows: [
            for (final row in rows)
              DataRow(
                cells: [
                  DataCell(_KraNameCell(row: row)),
                  DataCell(Text(
                    EmployeeFormatters.weightagePercent(row.weightPercent),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  )),
                  for (final m in months)
                    DataCell(
                      _CellWidget(
                        row: row,
                        monthId: m.id,
                      ),
                      onLongPress: () =>
                          _showCommentSheet(context, row, m.id),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _showCommentSheet(BuildContext context, ReviewRow row, String monthId) {
    final cell = row.monthlyScores.firstWhere(
      (c) => c.monthId == monthId,
      orElse: () => MonthlyScore(id: '', monthId: monthId),
    );
    if (cell.id.isEmpty) return;
    final hasAny = (cell.selfRemark?.isNotEmpty ?? false) ||
        (cell.managerRemark?.isNotEmpty ?? false);
    if (!hasAny) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CommentSheet(
        title: row.templateItem?.name ?? 'KRA',
        selfRemark: cell.selfRemark,
        managerRemark: cell.managerRemark,
      ),
    );
  }
}

class _KraNameCell extends StatelessWidget {
  final ReviewRow row;
  const _KraNameCell({required this.row});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.templateItem?.name ?? '—',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
          ),
          if (row.templateItem?.category != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                row.templateItem!.category!,
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

class _CellWidget extends StatelessWidget {
  final ReviewRow row;
  final String monthId;
  const _CellWidget({required this.row, required this.monthId});

  @override
  Widget build(BuildContext context) {
    final cell = row.monthlyScores.firstWhere(
      (c) => c.monthId == monthId,
      orElse: () => MonthlyScore(id: '', monthId: monthId),
    );
    if (cell.id.isEmpty || cell.isNotApplicable) {
      return const Text(
        '—',
        style: TextStyle(
          fontSize: 12,
          color: AppColors.textMuted,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    final hasRemark = (cell.selfRemark?.isNotEmpty ?? false) ||
        (cell.managerRemark?.isNotEmpty ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScorePill(
              score: cell.selfRating,
              maxScore: row.maxScore,
              tone: ScorePillTone.self,
              small: true,
            ),
            if (hasRemark)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.comment_rounded,
                  size: 11,
                  color: AppColors.textMuted,
                ),
              ),
          ],
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

class _CommentSheet extends StatelessWidget {
  final String title;
  final String? selfRemark;
  final String? managerRemark;
  const _CommentSheet({
    required this.title,
    required this.selfRemark,
    required this.managerRemark,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            if (selfRemark != null && selfRemark!.isNotEmpty)
              _RemarkBlock(
                label: 'You',
                text: selfRemark!,
                accent: AppColors.accentOrange,
              ),
            if (managerRemark != null && managerRemark!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _RemarkBlock(
                label: 'Manager',
                text: managerRemark!,
                accent: AppColors.primaryPurple,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RemarkBlock extends StatelessWidget {
  final String label;
  final String text;
  final Color accent;
  const _RemarkBlock({
    required this.label,
    required this.text,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: accent,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
