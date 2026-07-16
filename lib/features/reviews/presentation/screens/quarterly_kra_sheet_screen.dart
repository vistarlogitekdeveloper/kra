import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../../../core/widgets/workspace_drawer.dart';
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

  /// Locally-attached proof files, keyed by "reviewId|rowId|stage". Kept only
  /// for this session — there's no upload endpoint yet, so the file itself
  /// doesn't survive a reload. The Reason and the Proof *note* DO persist
  /// (they ride on the saved score).
  final Map<String, ({String name, String path})> _proofFiles = {};

  String _cellKey(String reviewId, String rowId, ReviewStage stage) =>
      '$reviewId|$rowId|${stage.toApiString()}';

  RowScore? _currentScore(
      MonthlyReview review, String rowId, ReviewStage stage) {
    for (final row in review.rows) {
      if (row.id == rowId) return row.scoreFor(stage);
    }
    return null;
  }

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

  // Self rating: editable ONLY by the employee themselves (their own sheet).
  // Admins, HR and managers can view it but not change someone's self score.
  bool _canEditSelf(MonthlyReview r, ReviewScope? scope) {
    if (scope == null) return false;
    return scope.userId == r.employeeId;
  }

  // Manager rating: editable ONLY by this employee's own reporting manager.
  // Not admins/HR, not other managers, not the employee.
  bool _canEditManager(MonthlyReview r, ReviewScope? scope) {
    if (scope == null) return false;
    final isManagerRole = scope.role == UserRole.manager ||
        scope.role == UserRole.bdManager ||
        scope.role == UserRole.warehouseMgr;
    return isManagerRole && r.managerId != null && r.managerId == scope.userId;
  }

  String _stageLabel(ReviewStage stage) => stage == ReviewStage.selfRating
      ? AppStrings.ratingSelf
      : AppStrings.ratingManager;

  Future<void> _editCell({
    required MonthlyReview review,
    required String rowId,
    required double maxScore,
    required ReviewStage stage,
    required double? currentPct,
    required String kraName,
    required String monthLabel,
  }) async {
    final current = _currentScore(review, rowId, stage);
    final key = _cellKey(review.id, rowId, stage);

    final result = await showDialog<_RatingResult>(
      context: context,
      builder: (ctx) => _RatingEditDialog(
        title: '$monthLabel · ${_stageLabel(stage)}',
        kraName: kraName,
        initialPct: currentPct,
        initialReason: current?.remark ?? '',
        initialProofNote: current?.proofNote ?? '',
        initialFile: _proofFiles[key],
      ),
    );
    if (result == null) return; // cancelled

    setState(() => _saving = true);
    try {
      // Empty % leaves the existing score untouched — so you can add a reason
      // or proof without re-entering the number.
      final newValue =
          result.pct != null ? result.pct! / 100 * maxScore : current?.value;
      await ref.read(monthlyReviewRepositoryProvider).saveStageScores(
        review.id,
        stage,
        rowScores: {
          rowId: RowScore(
            value: newValue,
            remark: result.reason.trim().isEmpty ? null : result.reason.trim(),
            proofNote: result.proofNote.trim().isEmpty
                ? null
                : result.proofNote.trim(),
          ),
        },
      );
      // The proof file is kept locally only (no upload endpoint yet).
      if (result.file != null) {
        _proofFiles[key] = result.file!;
      } else {
        _proofFiles.remove(key);
      }
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

  /// Read-only reason + proof view for a cell the current user can't edit
  /// (e.g. a manager looking at the employee's self-rating justification).
  void _viewCell({
    required MonthlyReview review,
    required String rowId,
    required ReviewStage stage,
    required String kraName,
    required String monthLabel,
  }) {
    final current = _currentScore(review, rowId, stage);
    showDialog<void>(
      context: context,
      builder: (ctx) => _RatingViewDialog(
        title: '$monthLabel · ${_stageLabel(stage)}',
        kraName: kraName,
        reason: current?.remark ?? '',
        proofNote: current?.proofNote ?? '',
      ),
    );
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
      // Left "☰" workspace menu — shows for manager/HR viewing their own sheet;
      // null (no menu) for a plain employee, who has only My KRA.
      drawer: workspaceDrawerFor(ref),
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
        error: (e, _) => _SheetError(
          message: e is ApiError
              ? e.combinedMessage
              : 'Something went wrong. Please try again.',
          onRetry: () => ref.invalidate(quarterlySheetProvider(
              (employeeId: employeeId, anchor: _anchor!))),
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
          onView: _viewCell,
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
  final void Function({
    required MonthlyReview review,
    required String rowId,
    required ReviewStage stage,
    required String kraName,
    required String monthLabel,
  }) onView;

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
    required this.onView,
  });

  MonthlyReview? get _any => reviews.firstWhere((r) => r != null, orElse: () => null);

  @override
  Widget build(BuildContext context) {
    final any = _any;
    if (any == null) {
      // A review row only exists once HR has generated the cycle's monthly
      // reviews. Employees added mid-cycle land here until that happens, so
      // explain it rather than dead-ending on a bare "no review" line.
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_note_outlined,
                  size: 44, color: AppColors.textMuted),
              SizedBox(height: 14),
              Text(
                'No review to rate yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'This quarter’s review hasn’t been set up for these '
                'KRAs yet. It will appear here once HR generates it — '
                'please check back or contact HR.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
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

    final canSelf = canEditSelf(any);
    final canMgr = canEditManager(any);
    final scopeLabel = canSelf
        ? 'You can edit the Self ratings on this sheet.'
        : canMgr
            ? 'You can edit the Manager ratings for your report.'
            : 'View only — you cannot edit this sheet.';

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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              Icon(canSelf || canMgr ? Icons.edit_rounded : Icons.visibility_rounded,
                  size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(scopeLabel,
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
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
            onView: onView,
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
  final void Function({
    required MonthlyReview review,
    required String rowId,
    required ReviewStage stage,
    required String kraName,
    required String monthLabel,
  }) onView;
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
    required this.onView,
    required this.monthTotal,
    required this.qAvg,
  });

  String _fmt(double? p) => p == null ? '—' : '${p.round()}%';

  /// The stored score for a (month, row, stage) — used to detect whether a
  /// cell carries a reason/proof note (drives the small indicator).
  RowScore? _scoreOf(MonthlyReview review, String rowId, ReviewStage stage) {
    for (final row in review.rows) {
      if (row.id == rowId) return row.scoreFor(stage);
    }
    return null;
  }

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
    // Does this cell carry a written reason / proof note? Drives the small
    // sticky-note indicator (and makes read-only cells tappable to view it).
    final hasNote = review != null &&
        (_scoreOf(review, rowId, stage)?.hasJustification ?? false);
    final text = Text(_fmt(p),
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: editable ? AppColors.primaryPurple : AppColors.textSecondary,
        ));

    if (editable) {
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
            if (hasNote) ...[
              const SizedBox(width: 3),
              const Icon(Icons.sticky_note_2_rounded,
                  size: 11, color: AppColors.accentOrange),
            ],
            const SizedBox(width: 3),
            Icon(Icons.edit_rounded,
                size: 11, color: AppColors.primaryPurple.withValues(alpha: 0.7)),
          ]),
        ),
      );
    }

    // Not editable but has a reason/proof → tap to view it read-only.
    if (hasNote) {
      return InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => onView(
          review: review,
          rowId: rowId,
          stage: stage,
          kraName: name,
          monthLabel: _shortMonth(months[monthIdx]),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            text,
            const SizedBox(width: 3),
            const Icon(Icons.sticky_note_2_outlined,
                size: 11, color: AppColors.textMuted),
          ]),
        ),
      );
    }

    return text;
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

class _SheetError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _SheetError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 40),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryPurple,
                side: const BorderSide(color: AppColors.primaryPurple),
              ),
            ),
          ],
        ),
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

// ─────────────────────────────────────────────────────────────────────
// Rating edit dialog — achievement %, reason, proof note + proof file
// ─────────────────────────────────────────────────────────────────────

/// What the edit dialog returns on Save. [pct] is null when the % field was
/// left blank — the caller then keeps the existing score, so a user can add a
/// reason / proof without re-typing the number.
class _RatingResult {
  final double? pct;
  final String reason;
  final String proofNote;
  final ({String name, String path})? file;
  const _RatingResult({
    required this.pct,
    required this.reason,
    required this.proofNote,
    required this.file,
  });
}

class _RatingEditDialog extends StatefulWidget {
  final String title;
  final String kraName;
  final double? initialPct;
  final String initialReason;
  final String initialProofNote;
  final ({String name, String path})? initialFile;

  const _RatingEditDialog({
    required this.title,
    required this.kraName,
    required this.initialPct,
    required this.initialReason,
    required this.initialProofNote,
    required this.initialFile,
  });

  @override
  State<_RatingEditDialog> createState() => _RatingEditDialogState();
}

class _RatingEditDialogState extends State<_RatingEditDialog> {
  late final TextEditingController _pct;
  late final TextEditingController _reason;
  late final TextEditingController _proofNote;
  ({String name, String path})? _file;

  @override
  void initState() {
    super.initState();
    _pct = TextEditingController(
      text: widget.initialPct == null
          ? ''
          : widget.initialPct!.round().toString(),
    );
    _reason = TextEditingController(text: widget.initialReason);
    _proofNote = TextEditingController(text: widget.initialProofNote);
    _file = widget.initialFile;
  }

  @override
  void dispose() {
    _pct.dispose();
    _reason.dispose();
    _proofNote.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.single;
    final path = f.path;
    if (path == null) return;
    setState(() => _file = (name: f.name, path: path));
  }

  void _save() {
    final v = double.tryParse(_pct.text.trim());
    Navigator.of(context).pop(_RatingResult(
      pct: v?.clamp(0, 100).toDouble(),
      reason: _reason.text,
      proofNote: _proofNote.text,
      file: _file,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.kraName,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 14),
            TextField(
              controller: _pct,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: AppStrings.ratingAchievementLabel,
                hintText: AppStrings.ratingAchievementHint,
                suffixText: '%',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: AppStrings.ratingReasonLabel,
                hintText: AppStrings.ratingReasonHint,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _proofNote,
              minLines: 1,
              maxLines: 2,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: AppStrings.ratingProofNoteLabel,
                hintText: AppStrings.ratingProofNoteHint,
              ),
            ),
            const SizedBox(height: 10),
            _FilePickRow(
              file: _file,
              onPick: _pickFile,
              onRemove: () => setState(() => _file = null),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.commonCancel),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// The "Attach proof file" control — an add button, or the picked-file chip
/// with replace/remove and a note that the file is local-only for now.
class _FilePickRow extends StatelessWidget {
  final ({String name, String path})? file;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _FilePickRow({
    required this.file,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (file == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.attach_file_rounded, size: 18),
          label: const Text(AppStrings.ratingProofFileAdd),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryPurple,
            side: const BorderSide(color: AppColors.divider),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          decoration: BoxDecoration(
            color: AppColors.primaryPurple.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.primaryPurple.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.insert_drive_file_outlined,
                  size: 18, color: AppColors.primaryPurple),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  file!.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
              ),
              TextButton(
                onPressed: onPick,
                child: const Text(AppStrings.ratingProofFileReplace),
              ),
              IconButton(
                onPressed: onRemove,
                tooltip: AppStrings.ratingProofFileRemove,
                icon: const Icon(Icons.close_rounded,
                    size: 18, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          AppStrings.ratingProofFileLocalNote,
          style: TextStyle(
              fontSize: 10.5, color: AppColors.textMuted, height: 1.3),
        ),
      ],
    );
  }
}

/// Read-only reason + proof note, shown when tapping a cell you can't edit.
class _RatingViewDialog extends StatelessWidget {
  final String title;
  final String kraName;
  final String reason;
  final String proofNote;

  const _RatingViewDialog({
    required this.title,
    required this.kraName,
    required this.reason,
    required this.proofNote,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kraName,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          _labelled(
            AppStrings.ratingReasonLabel,
            reason.trim().isEmpty ? AppStrings.ratingNoReason : reason.trim(),
            muted: reason.trim().isEmpty,
          ),
          const SizedBox(height: 12),
          _labelled(
            AppStrings.ratingProofNoteLabel,
            proofNote.trim().isEmpty
                ? AppStrings.ratingNoProof
                : proofNote.trim(),
            muted: proofNote.trim().isEmpty,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _labelled(String label, String value, {required bool muted}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textMuted,
                letterSpacing: 0.6)),
        const SizedBox(height: 3),
        Text(value,
            style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: muted ? AppColors.textMuted : AppColors.textPrimary)),
      ],
    );
  }
}
