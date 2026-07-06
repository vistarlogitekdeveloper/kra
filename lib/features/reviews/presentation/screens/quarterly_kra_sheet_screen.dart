import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../../auth/data/models/user.dart';
import '../../../employee/presentation/widgets/_formatters.dart';
import '../../data/models/monthly_review.dart';
import '../../data/models/review_stage.dart';
import '../../data/models/row_score.dart';
import '../providers/monthly_review_providers.dart';

const _monthAbbr = [
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _shortMonth(ReviewPeriod p) =>
    "${_monthAbbr[p.month]} '${p.year.toString().substring(2)}";

/// Quarterly KRA sheet for one employee — models the "KRA for … .xlsx"
/// reference: every KRA across the 3 months of a quarter with Self + Manager
/// scores, a quarter average, and the payout. The employee edits their own
/// Self scores; the reporting manager edits Manager scores; admins/HR can
/// edit either. Pass [employeeId] to view someone else; omit it for the
/// signed-in user's own sheet.
class QuarterlyKraSheetScreen extends ConsumerStatefulWidget {
  final String? employeeId;
  const QuarterlyKraSheetScreen({super.key, this.employeeId});

  @override
  ConsumerState<QuarterlyKraSheetScreen> createState() =>
      _QuarterlyKraSheetScreenState();
}

class _QuarterlyKraSheetScreenState
    extends ConsumerState<QuarterlyKraSheetScreen> {
  ReviewPeriod? _anchor;
  bool _saving = false;

  double? _pct(MonthlyReview? r, String rowId, ReviewStage stage) {
    if (r == null) return null;
    for (final row in r.rows) {
      if (row.id != rowId) continue;
      final s = row.scoreFor(stage);
      if (s?.value != null && row.maxScore > 0) {
        return (s!.value! / row.maxScore) * 100;
      }
      return null;
    }
    return null;
  }

  bool _canEditSelf(MonthlyReview r, ReviewScope? scope) {
    if (scope == null) return false;
    if (scope.role == UserRole.admin || scope.role == UserRole.hrAdmin) {
      return true;
    }
    final isOwner = scope.userId == r.employeeId &&
        (scope.role == UserRole.employee || scope.role == UserRole.ops);
    return isOwner;
  }

  bool _canEditManager(MonthlyReview r, ReviewScope? scope) {
    if (scope == null) return false;
    if (scope.role == UserRole.admin || scope.role == UserRole.hrAdmin) {
      return true;
    }
    final isManager = scope.role == UserRole.manager ||
        scope.role == UserRole.bdManager ||
        scope.role == UserRole.warehouseMgr;
    return isManager && r.managerId == scope.userId;
  }

  Future<void> _editCell({
    required MonthlyReview review,
    required String rowId,
    required double maxScore,
    required ReviewStage stage,
    required double? currentPct,
    required String kraName,
    required String monthLabel,
  }) async {
    final controller = TextEditingController(
      text: currentPct == null ? '' : currentPct.round().toString(),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$monthLabel · ${stage == ReviewStage.selfRating ? 'Self' : 'Manager'}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(kraName,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Achievement %',
                hintText: '0 – 100',
                suffixText: '%',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(controller.text.trim());
              Navigator.of(ctx).pop(v == null ? -1 : v.clamp(0, 100).toDouble());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result < 0) return;

    setState(() => _saving = true);
    try {
      final value = result / 100 * maxScore;
      await ref.read(monthlyReviewRepositoryProvider).saveStageScores(
        review.id,
        stage,
        rowScores: {rowId: RowScore(value: value)},
      );
      // Refresh every quarterly-sheet query for this employee.
      ref.invalidate(quarterlySheetProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(currentReviewScopeProvider);
    final employeeId = widget.employeeId ?? scope?.userId;
    _anchor ??= ref.read(selectedPeriodProvider) ??
        ref.read(availablePeriodsProvider).first;

    if (employeeId == null) {
      return const Scaffold(
        body: Center(child: Text('Not signed in.')),
      );
    }

    final sheetAsync = ref.watch(
        quarterlySheetProvider((employeeId: employeeId, anchor: _anchor!)));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.quarterlySheetTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        bottom: _saving
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: sheetAsync.when(
        loading: () => const _Skeleton(),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(e.toString(),
                style: const TextStyle(color: AppColors.error)),
          ),
        ),
        data: (data) => _Sheet(
          months: data.months,
          reviews: data.reviews,
          scope: scope,
          onPrevQuarter: () => setState(() => _anchor =
              quarterMonthsFor(_anchor!).first.let((m) => _shiftQuarter(m, -1))),
          onNextQuarter: () => setState(() => _anchor =
              quarterMonthsFor(_anchor!).first.let((m) => _shiftQuarter(m, 1))),
          pct: _pct,
          canEditSelf: (r) => _canEditSelf(r, scope),
          canEditManager: (r) => _canEditManager(r, scope),
          onEdit: _editCell,
        ),
      ),
    );
  }

  ReviewPeriod _shiftQuarter(ReviewPeriod quarterStart, int delta) {
    var m = quarterStart.month + delta * 3;
    var y = quarterStart.year;
    while (m > 12) {
      m -= 12;
      y += 1;
    }
    while (m < 1) {
      m += 12;
      y -= 1;
    }
    return ReviewPeriod(y, m);
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

class _Sheet extends StatelessWidget {
  final List<ReviewPeriod> months;
  final List<MonthlyReview?> reviews;
  final ReviewScope? scope;
  final VoidCallback onPrevQuarter;
  final VoidCallback onNextQuarter;
  final double? Function(MonthlyReview?, String, ReviewStage) pct;
  final bool Function(MonthlyReview) canEditSelf;
  final bool Function(MonthlyReview) canEditManager;
  final Future<void> Function({
    required MonthlyReview review,
    required String rowId,
    required double maxScore,
    required ReviewStage stage,
    required double? currentPct,
    required String kraName,
    required String monthLabel,
  }) onEdit;

  const _Sheet({
    required this.months,
    required this.reviews,
    required this.scope,
    required this.onPrevQuarter,
    required this.onNextQuarter,
    required this.pct,
    required this.canEditSelf,
    required this.canEditManager,
    required this.onEdit,
  });

  MonthlyReview? get _any => reviews.firstWhere((r) => r != null, orElse: () => null);

  @override
  Widget build(BuildContext context) {
    final any = _any;
    if (any == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No review for this employee this quarter.',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    // Canonical KRA rows (same template across months) from the first review.
    final rows = [...any.rows]..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    // Weighted monthly totals per stage (0–100) and the quarter average.
    double monthTotal(int i, ReviewStage stage) =>
        reviews[i]?.weightedScorePct(stage) ?? 0;
    double qAvg(ReviewStage stage) =>
        (monthTotal(0, stage) + monthTotal(1, stage) + monthTotal(2, stage)) / 3;

    final qMgr = qAvg(ReviewStage.reportingManagerRating);
    final qSelf = qAvg(ReviewStage.selfRating);
    final eligibleMonthly = any.eligibleAmount;
    final quarterEligible = eligibleMonthly * 3;
    final payout = quarterEligible * qMgr / 100;

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _HeaderCard(
          review: any,
          months: months,
          onPrev: onPrevQuarter,
          onNext: onNextQuarter,
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: _Grid(
            rows: rows,
            months: months,
            reviews: reviews,
            pct: pct,
            canEditSelf: canEditSelf,
            canEditManager: canEditManager,
            onEdit: onEdit,
            monthTotal: monthTotal,
            qAvg: qAvg,
          ),
        ),
        const SizedBox(height: 16),
        _PayoutCard(
          qSelf: qSelf,
          qMgr: qMgr,
          eligibleMonthly: eligibleMonthly,
          quarterEligible: quarterEligible,
          payout: payout,
        ),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final MonthlyReview review;
  final List<ReviewPeriod> months;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _HeaderCard({
    required this.review,
    required this.months,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [AppColors.primaryPurple, AppColors.primaryPurpleLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            review.employeeName,
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            [
              if (review.employeeCode.isNotEmpty) review.employeeCode,
              if (review.grade != null) 'Grade ${review.grade}',
              if (review.managerName != null) 'Mgr: ${review.managerName}',
            ].join('  ·  '),
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _navBtn(Icons.chevron_left_rounded, onPrev),
              const SizedBox(width: 8),
              Text(
                '${_shortMonth(months.first)} – ${_shortMonth(months.last)}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14),
              ),
              const SizedBox(width: 8),
              _navBtn(Icons.chevron_right_rounded, onNext),
            ],
          ),
        ],
      ),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback onTap) => Material(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      );
}

class _Grid extends StatelessWidget {
  final List<dynamic> rows; // MonthlyKraRow
  final List<ReviewPeriod> months;
  final List<MonthlyReview?> reviews;
  final double? Function(MonthlyReview?, String, ReviewStage) pct;
  final bool Function(MonthlyReview) canEditSelf;
  final bool Function(MonthlyReview) canEditManager;
  final Future<void> Function({
    required MonthlyReview review,
    required String rowId,
    required double maxScore,
    required ReviewStage stage,
    required double? currentPct,
    required String kraName,
    required String monthLabel,
  }) onEdit;
  final double Function(int, ReviewStage) monthTotal;
  final double Function(ReviewStage) qAvg;

  const _Grid({
    required this.rows,
    required this.months,
    required this.reviews,
    required this.pct,
    required this.canEditSelf,
    required this.canEditManager,
    required this.onEdit,
    required this.monthTotal,
    required this.qAvg,
  });

  String _fmt(double? p) => p == null ? '—' : '${p.round()}%';

  @override
  Widget build(BuildContext context) {
    final columns = <DataColumn>[
      const DataColumn(label: Text('Wt')),
      const DataColumn(label: Text('KRA')),
      for (final m in months) ...[
        DataColumn(label: Text('${_shortMonth(m)}\nSelf'), numeric: true),
        DataColumn(label: Text('${_shortMonth(m)}\nMgr'), numeric: true),
      ],
      const DataColumn(label: Text('Qtr\nSelf'), numeric: true),
      const DataColumn(label: Text('Qtr\nMgr'), numeric: true),
    ];

    return DataTable(
      columnSpacing: 18,
      headingRowHeight: 48,
      dataRowMinHeight: 52,
      dataRowMaxHeight: 78,
      border: TableBorder.symmetric(
        inside: BorderSide(color: AppColors.divider.withValues(alpha: 0.5)),
      ),
      columns: columns,
      rows: [
        for (final row in rows) _dataRow(row),
        _totalsRow(),
      ],
    );
  }

  DataRow _dataRow(dynamic row) {
    final rowId = row.id as String;
    final maxScore = (row.maxScore as num).toDouble();
    final name = row.name as String;
    // per-KRA quarter averages
    double qKra(ReviewStage stage) {
      final vals = [
        for (var i = 0; i < 3; i++) pct(reviews[i], rowId, stage) ?? 0,
      ];
      return (vals[0] + vals[1] + vals[2]) / 3;
    }

    return DataRow(cells: [
      DataCell(Text('${(row.weightagePercent as num).round()}%')),
      DataCell(_kraCell(row)),
      for (var i = 0; i < 3; i++) ...[
        DataCell(_scoreCell(i, rowId, maxScore, name, ReviewStage.selfRating)),
        DataCell(_scoreCell(
            i, rowId, maxScore, name, ReviewStage.reportingManagerRating)),
      ],
      DataCell(Text(_fmt(qKra(ReviewStage.selfRating)),
          style: const TextStyle(fontWeight: FontWeight.w700))),
      DataCell(Text(_fmt(qKra(ReviewStage.reportingManagerRating)),
          style: const TextStyle(
              fontWeight: FontWeight.w800, color: AppColors.primaryPurple))),
    ]);
  }

  Widget _kraCell(dynamic row) {
    final cat = row.category as String?;
    final target = row.target as String?;
    final tracking = row.trackingMethod as String?;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cat != null && cat.isNotEmpty)
            Text(cat,
                style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accentOrange)),
          Text(row.name as String,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600)),
          if ((target != null && target.isNotEmpty) ||
              (tracking != null && tracking.isNotEmpty))
            Text(
              [
                if (target != null && target.isNotEmpty) 'Target: $target',
                if (tracking != null && tracking.isNotEmpty) tracking,
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }

  Widget _scoreCell(
      int monthIdx, String rowId, double maxScore, String name, ReviewStage stage) {
    final review = reviews[monthIdx];
    final p = pct(review, rowId, stage);
    final editable = review != null &&
        (stage == ReviewStage.selfRating
            ? canEditSelf(review)
            : canEditManager(review));
    final text = Text(_fmt(p),
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: editable ? AppColors.primaryPurple : AppColors.textSecondary,
        ));
    if (!editable) return text;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => onEdit(
        review: review,
        rowId: rowId,
        maxScore: maxScore,
        stage: stage,
        currentPct: p,
        kraName: name,
        monthLabel: _shortMonth(months[monthIdx]),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: AppColors.primaryPurple.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          text,
          const SizedBox(width: 3),
          Icon(Icons.edit_rounded,
              size: 11, color: AppColors.primaryPurple.withValues(alpha: 0.7)),
        ]),
      ),
    );
  }

  DataRow _totalsRow() {
    return DataRow(
      color: WidgetStatePropertyAll(
          AppColors.primaryPurple.withValues(alpha: 0.06)),
      cells: [
        const DataCell(Text('100%',
            style: TextStyle(fontWeight: FontWeight.w800))),
        const DataCell(Text('Total',
            style: TextStyle(fontWeight: FontWeight.w800))),
        for (var i = 0; i < 3; i++) ...[
          DataCell(Text('${monthTotal(i, ReviewStage.selfRating).round()}%',
              style: const TextStyle(fontWeight: FontWeight.w700))),
          DataCell(Text(
              '${monthTotal(i, ReviewStage.reportingManagerRating).round()}%',
              style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
        DataCell(Text('${qAvg(ReviewStage.selfRating).round()}%',
            style: const TextStyle(fontWeight: FontWeight.w800))),
        DataCell(Text('${qAvg(ReviewStage.reportingManagerRating).round()}%',
            style: const TextStyle(
                fontWeight: FontWeight.w900, color: AppColors.primaryPurple))),
      ],
    );
  }
}

class _PayoutCard extends StatelessWidget {
  final double qSelf;
  final double qMgr;
  final double eligibleMonthly;
  final double quarterEligible;
  final double payout;
  const _PayoutCard({
    required this.qSelf,
    required this.qMgr,
    required this.eligibleMonthly,
    required this.quarterEligible,
    required this.payout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(AppStrings.quarterlyPayoutTitle,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 12),
          _row('Quarter self average', '${qSelf.round()}%'),
          _row('Quarter manager average', '${qMgr.round()}%'),
          _row('Monthly incentive', EmployeeFormatters.currencyInr(eligibleMonthly)),
          _row('Quarter eligible (×3)',
              EmployeeFormatters.currencyInr(quarterEligible)),
          const Divider(height: 20),
          _row(
            AppStrings.quarterlyPayoutAmount,
            EmployeeFormatters.currencyInr(payout),
            emphasize: true,
          ),
          const SizedBox(height: 4),
          const Text(
            'Payout = monthly incentive × 3 × quarter manager average.',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: emphasize ? 14 : 12.5,
                  fontWeight: emphasize ? FontWeight.w800 : FontWeight.w500,
                  color: emphasize
                      ? AppColors.textPrimary
                      : AppColors.textSecondary)),
          Text(value,
              style: TextStyle(
                  fontSize: emphasize ? 16 : 13,
                  fontWeight: FontWeight.w800,
                  color: emphasize
                      ? AppColors.primaryPurple
                      : AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        ShimmerBox(height: 90, borderRadius: 16),
        SizedBox(height: 16),
        ShimmerBox(height: 260, borderRadius: 12),
        SizedBox(height: 16),
        ShimmerBox(height: 160, borderRadius: 16),
      ],
    );
  }
}
