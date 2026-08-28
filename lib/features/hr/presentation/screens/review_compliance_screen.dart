import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../../reviews/data/models/review_compliance_row.dart';
import '../../../reviews/presentation/providers/monthly_review_providers.dart';
import '../../../reviews/presentation/widgets/monthly_review_widgets.dart';

/// HR's review-compliance report: for one month, who has reviewed and who has
/// not, one row per employee.
///
/// Answers the question the Review Dashboard cannot. That one shows how far each
/// review has PROGRESSED; this shows which specific reviewer is holding it up,
/// so it works as a chase-list.
class ReviewComplianceScreen extends ConsumerWidget {
  const ReviewComplianceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periods = ref.watch(availablePeriodsProvider);
    final selected = ref.watch(selectedPeriodProvider) ?? periods.first;
    final async = ref.watch(reviewComplianceProvider(selected));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.complianceTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: AppStrings.commonRetry,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(reviewComplianceProvider(selected)),
          ),
        ],
      ),
      body: Column(
        children: [
          PeriodSelector(
            periods: periods,
            selected: selected,
            onSelect: (p) =>
                ref.read(selectedPeriodProvider.notifier).state = p,
          ),
          Divider(height: 1, color: AppColors.divider),
          Expanded(
            child: async.when(
              loading: () => const _Loading(),
              error: (e, _) => _Error(
                message: e is ApiError ? e.message : AppStrings.errorGeneric,
                onRetry: () =>
                    ref.invalidate(reviewComplianceProvider(selected)),
              ),
              data: (report) => report.rows.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          AppStrings.complianceEmpty,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  : _Table(rows: report.rows, skipped: report.skipped),
            ),
          ),
        ],
      ),
    );
  }
}

// Column weights, shared by the header and every row so they line up.
const int _flexSl = 6;
const int _flexName = 26;
const int _flexSelf = 16;
const int _flexCell = 12;
const int _flexFinal = 14;

/// Below this width eight columns cannot shrink without becoming unreadable, so
/// the table scrolls sideways instead of being squeezed.
const double _minTableWidth = 760;

class _Table extends StatelessWidget {
  final List<ReviewComplianceRow> rows;

  /// Reviews that could not be fetched. Shown rather than swallowed: without
  /// it the stat line reads as the whole team when it is only the part that
  /// loaded, and HR would chase the wrong list.
  final int skipped;
  const _Table({required this.rows, required this.skipped});

  @override
  Widget build(BuildContext context) {
    final approved = rows.where((r) => r.finalApproval).length;
    final submitted = rows.where((r) => r.selfSubmitted).length;

    return Column(
      children: [
        if (skipped > 0) _SkippedNotice(count: skipped),
        // Counts first: HR opens this to see how far off "everyone done" is.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              _Stat(
                label: AppStrings.complianceStatEmployees,
                value: '${rows.length}',
              ),
              const SizedBox(width: 20),
              _Stat(
                label: AppStrings.complianceStatSubmitted,
                value: '$submitted/${rows.length}',
              ),
              const SizedBox(width: 20),
              _Stat(
                label: AppStrings.complianceStatApproved,
                value: '$approved/${rows.length}',
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < _minTableWidth;
            final table = SizedBox(
              width: narrow ? _minTableWidth : c.maxWidth,
              child: Column(
                children: [
                  const _Header(),
                  Divider(height: 1, color: AppColors.divider),
                  Expanded(
                    child: ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: AppColors.divider),
                      itemBuilder: (_, i) => _Row(index: i + 1, row: rows[i]),
                    ),
                  ),
                ],
              ),
            );
            return narrow
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: table,
                  )
                : table;
          }),
        ),
        const _Legend(),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      color: AppColors.textMuted,
      letterSpacing: 0.2,
    );
    Widget cell(String t, int flex, {TextAlign align = TextAlign.center}) =>
        Expanded(
          flex: flex,
          child: Text(t, textAlign: align, style: style),
        );

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          cell(AppStrings.complianceColSl, _flexSl),
          cell(AppStrings.complianceColName, _flexName, align: TextAlign.left),
          cell(AppStrings.complianceColSelf, _flexSelf),
          cell(AppStrings.complianceColFinance, _flexCell),
          cell(AppStrings.complianceColHr, _flexCell),
          cell(AppStrings.complianceColManager, _flexCell),
          cell(AppStrings.complianceColOps, _flexCell),
          cell(AppStrings.complianceColFinal, _flexFinal),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final int index;
  final ReviewComplianceRow row;
  const _Row({required this.index, required this.row});

  @override
  Widget build(BuildContext context) {
    // The report is a chase-list, so every row leads to the thing you chase:
    // that employee's own quarterly KRA sheet, where the missing ratings are
    // entered. Same destination and same `push` the Review Dashboard uses, so
    // the back button returns here.
    return InkWell(
      onTap: () => context.push(AppRoutes.reviewsQuarterlyFor(row.employeeId)),
      // Named for screen readers and for the web tooltip, since a bare table
      // row gives no hint that it is actionable.
      child: Tooltip(
        message: AppStrings.complianceOpenSheet(row.employeeName),
        waitDuration: const Duration(milliseconds: 600),
        child: _rowBody(),
      ),
    );
  }

  Widget _rowBody() {
    return Container(
      // Faintly tint rows where something has happened, so the untouched ones
      // stand out as the list to chase.
      color: row.untouched
          ? AppColors.surface
          : AppColors.primaryPurple.withValues(alpha: 0.03),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      child: Row(
        children: [
          Expanded(
            flex: _flexSl,
            child: Text(
              '$index',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
          ),
          Expanded(
            flex: _flexName,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.employeeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                if (row.employeeCode.isNotEmpty)
                  Text(
                    row.employeeCode,
                    style:
                        TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: _flexSelf,
            child: Center(child: _SelfPill(submitted: row.selfSubmitted)),
          ),
          Expanded(
              flex: _flexCell, child: Center(child: _YesNo(row.byFinance))),
          Expanded(flex: _flexCell, child: Center(child: _YesNo(row.byHr))),
          Expanded(
            flex: _flexCell,
            child: Center(child: _YesNo(row.byReportingManager)),
          ),
          Expanded(
            flex: _flexCell,
            child: Center(child: _YesNo(row.byOpsExcellence)),
          ),
          Expanded(
            flex: _flexFinal,
            child: Center(
              child: _YesNo(row.finalApproval
                  ? ReviewerProgress.yes
                  : ReviewerProgress.no),
            ),
          ),
        ],
      ),
    );
  }
}

/// Says how many reviews were dropped, so a partial report is never mistaken
/// for a complete one.
class _SkippedNotice extends StatelessWidget {
  final int count;
  const _SkippedNotice({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.accentOrange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: AppColors.accentOrange.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 16, color: AppColors.accentOrange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppStrings.complianceSkipped(count),
              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Submitted / Not submitted as a pill, so the two states are separable at a
/// glance down a long column rather than needing to be read.
class _SelfPill extends StatelessWidget {
  final bool submitted;
  const _SelfPill({required this.submitted});

  @override
  Widget build(BuildContext context) {
    final c = submitted ? AppColors.success : AppColors.accentOrange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Text(
        submitted
            ? AppStrings.complianceSubmitted
            : AppStrings.complianceNotSubmitted,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: c),
      ),
    );
  }
}

class _YesNo extends StatelessWidget {
  final ReviewerProgress progress;
  const _YesNo(this.progress);

  @override
  Widget build(BuildContext context) {
    switch (progress) {
      case ReviewerProgress.yes:
        return const Icon(Icons.check_circle_rounded,
            size: 17, color: AppColors.success);
      case ReviewerProgress.no:
        return Icon(Icons.radio_button_unchecked_rounded,
            size: 16, color: AppColors.accentOrange.withValues(alpha: 0.85));
      case ReviewerProgress.notApplicable:
        // No KRA on this sheet belongs to that reviewer, so they have nothing to
        // do. Deliberately not "No", which would read as an outstanding action.
        return Text('—',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted));
      case ReviewerProgress.notTracked:
        return Icon(Icons.remove_circle_outline_rounded,
            size: 15, color: AppColors.textMuted.withValues(alpha: 0.6));
    }
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final s = TextStyle(fontSize: 10.5, color: AppColors.textMuted);
    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              const _LegendItem(
                icon: Icons.check_circle_rounded,
                color: AppColors.success,
                label: AppStrings.complianceLegendYes,
              ),
              const _LegendItem(
                icon: Icons.radio_button_unchecked_rounded,
                color: AppColors.accentOrange,
                label: AppStrings.complianceLegendNo,
              ),
              _LegendItem(
                icon: Icons.remove_rounded,
                color: AppColors.textMuted,
                label: AppStrings.complianceLegendNa,
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(AppStrings.complianceTapHint,
              style: s.copyWith(color: AppColors.primaryPurple)),
          const SizedBox(height: 3),
          Text(AppStrings.complianceOpsNote, style: s),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _LegendItem({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryPurple,
          ),
        ),
        Text(label,
            style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // This report costs one request per employee, so it is slower than a
        // normal list. Say why rather than showing a bare spinner.
        Text(
          AppStrings.complianceLoading,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < 8; i++) ...[
          const ShimmerBox(height: 44, borderRadius: 10),
          const SizedBox(height: 8),
        ],
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 34),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(AppStrings.commonRetry),
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple),
            ),
          ],
        ),
      ),
    );
  }
}
