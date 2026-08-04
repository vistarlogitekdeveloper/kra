import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/proof_file_saver.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../../employee/presentation/widgets/_formatters.dart';
import '../../data/models/monthly_review.dart';
import '../../data/models/performance_incentive_row.dart';
import '../providers/monthly_review_providers.dart';
import '../providers/performance_incentive_providers.dart';

/// An official-looking Vistar Performance Incentive Sheet as a single-file
/// spreadsheet (HTML that Excel opens as `.xls`): a branded header band with the
/// Vistar logo, the report title, the quarter, and the generation date, above a
/// bordered, colour-headed table of every column. Numbers stay numeric so Excel
/// can sum/sort them; the two remark states are colour-coded.
String _buildOfficialXls(
  List<PerformanceIncentiveRow> rows,
  List<ReviewPeriod> months, {
  required ReviewPeriod anchor,
  required String logoDataUri,
  required String generatedOn,
}) {
  String esc(Object? v) => (v ?? '')
      .toString()
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  String n(double? v) => v == null ? '' : v.round().toString();

  const totalCols = 15; // Sr, Code, Name, Amount, Loc, Self×3, Mgmt×3, Total,
  //                        Fixed, Payable, Remark
  final headers = <String>[
    'Sr No',
    'EMP Code',
    'Name of Employee',
    'Perf. Incentive Amount',
    'Project Location',
    for (final m in months) 'Self ${m.shortLabel}',
    for (final m in months) 'Mgmt ${m.shortLabel}',
    'Total',
    'Qtr Fixed Incentive',
    'Payable Incentive',
    'Remark',
  ];

  final b = StringBuffer();
  b.writeln(
      '<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel">');
  b.writeln('<head><meta http-equiv="content-type" '
      'content="text/html; charset=UTF-8"><style>'
      'table{border-collapse:collapse;font-family:Calibri,Arial,sans-serif;}'
      'td,th{border:0.5pt solid #C9C6D6;padding:5px 9px;font-size:11pt;'
      'color:#1B1630;}'
      '.plain{border:none;}'
      '.title{font-size:20pt;font-weight:bold;color:#6B1F7C;}'
      '.sub{font-size:10.5pt;color:#4A4560;}'
      '.colhead{background:#6B1F7C;color:#FFFFFF;font-weight:bold;'
      'text-align:center;}'
      '.num{text-align:right;} .center{text-align:center;}'
      '.paid{color:#1E7A3D;font-weight:bold;}'
      '.notsub{color:#B26A00;font-weight:bold;}'
      '</style></head><body>');
  b.writeln('<table>');

  // ── Branded header band ──
  final logoCell = logoDataUri.isEmpty
      ? '<td class="plain" colspan="3" rowspan="3"></td>'
      : '<td class="plain" colspan="3" rowspan="3">'
          '<img src="$logoDataUri" height="52"/></td>';
  b.writeln('<tr>$logoCell'
      '<td class="plain title" colspan="12">Performance Incentive Sheet</td></tr>');
  b.writeln('<tr><td class="plain sub" colspan="12">'
      'Vistar Logitek &bull; ${esc(anchor.fiscalQuarterLabel)} &bull; '
      "${months.first.shortLabel} – ${months.last.shortLabel}</td></tr>");
  b.writeln('<tr><td class="plain sub" colspan="12">'
      'Generated on ${esc(generatedOn)} &bull; Read-only report</td></tr>');
  b.writeln('<tr><td class="plain" colspan="$totalCols">&nbsp;</td></tr>');

  // ── Column headers ──
  b.write('<tr class="colhead">');
  for (final h in headers) {
    b.write('<td>${esc(h)}</td>');
  }
  b.writeln('</tr>');

  // ── Data rows ──
  for (final r in rows) {
    // Only the paid state is tinted; a blank remark stays an empty, unstyled cell.
    final remarkClass =
        r.remark == PerformanceIncentiveRow.remarkPaid ? 'paid' : '';
    b.write('<tr>');
    b.write('<td class="center">${r.srNo}</td>');
    b.write('<td>${esc(r.employeeCode)}</td>');
    b.write('<td>${esc(r.employeeName)}</td>');
    b.write('<td class="num">${r.performanceIncentiveAmount.round()}</td>');
    b.write('<td>${esc(r.projectLocation ?? '')}</td>');
    for (final v in r.selfRatings) {
      b.write('<td class="num">${n(v)}</td>');
    }
    for (final v in r.managementRatings) {
      b.write('<td class="num">${n(v)}</td>');
    }
    b.write('<td class="num">${r.total.round()}</td>');
    b.write('<td class="num">${r.quarterlyFixedIncentive.round()}</td>');
    b.write('<td class="num">${r.payableIncentive.round()}</td>');
    b.write('<td class="$remarkClass">${esc(r.remark)}</td>');
    b.writeln('</tr>');
  }

  b.writeln('</table></body></html>');
  return b.toString();
}

/// Loads the bundled Vistar logo as a `data:` URI for embedding in the export.
/// Returns empty (header renders without a logo) if the asset can't be read.
Future<String> _logoDataUri() async {
  try {
    final data = await rootBundle.load(AppAssets.logo);
    final b64 = base64Encode(data.buffer.asUint8List());
    return 'data:image/png;base64,$b64';
  } catch (_) {
    return '';
  }
}

String _generatedOn() => EmployeeFormatters.date(DateTime.now());

/// Quarterly Performance Incentive Sheet — a READ-ONLY report mirroring the
/// "Performance Incentive" Excel: every column, one row per employee, for the
/// three months of a fiscal quarter. Access is restricted to Management / HR /
/// Accounts by the router (see [AppRoutes.canReview]); nothing here edits.
class PerformanceIncentiveSheetScreen extends ConsumerStatefulWidget {
  const PerformanceIncentiveSheetScreen({super.key});

  @override
  ConsumerState<PerformanceIncentiveSheetScreen> createState() =>
      _PerformanceIncentiveSheetScreenState();
}

class _PerformanceIncentiveSheetScreenState
    extends ConsumerState<PerformanceIncentiveSheetScreen> {
  ReviewPeriod? _anchor;
  bool _exporting = false;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Builds a CSV of the current quarter's sheet (every Excel column) and
  /// downloads it. CSV opens straight into Excel — no dependency needed — and a
  /// leading BOM keeps Excel's UTF-8 detection happy.
  Future<void> _export() async {
    final anchor = _anchor!;
    final rows =
        ref.read(performanceIncentiveSheetProvider(anchor)).valueOrNull;
    if (rows == null || rows.isEmpty) {
      _snack(AppStrings.perfIncentiveExportNothing);
      return;
    }
    setState(() => _exporting = true);
    try {
      final months = quarterMonthsFor(anchor);
      final html = _buildOfficialXls(
        rows,
        months,
        anchor: anchor,
        logoDataUri: await _logoDataUri(),
        generatedOn: _generatedOn(),
      );
      final bytes = Uint8List.fromList(utf8.encode(html));
      final ok = await saveProofFile(
        bytes: bytes,
        fileName:
            'Vistar_Performance_Incentive_Q${anchor.fiscalQuarter}_FY${anchor.fiscalYearStartYear}.xls',
        mime: 'application/vnd.ms-excel',
      );
      _snack(ok
          ? AppStrings.perfIncentiveExported
          : AppStrings.perfIncentiveExportUnsupported);
    } catch (_) {
      _snack(AppStrings.perfIncentiveExportUnsupported);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _anchor ??= ref.read(performanceIncentiveAnchorProvider) ??
        ref.read(selectedPeriodProvider) ??
        ref.read(availablePeriodsProvider).first;
    final anchor = _anchor!;
    final months = quarterMonthsFor(anchor);
    final rowsAsync = ref.watch(performanceIncentiveSheetProvider(anchor));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: AppStrings.commonBack,
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.hrHome),
        ),
        title: const Text(AppStrings.perfIncentiveTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: AppStrings.perfIncentiveExport,
            onPressed: _exporting ? null : _export,
          ),
        ],
      ),
      body: Column(
        children: [
          _QuarterBar(
            anchor: anchor,
            months: months,
            onPrev: () => _shiftQuarter(-1),
            onNext: () => _shiftQuarter(1),
          ),
          const _ReadOnlyHint(),
          Divider(height: 1, color: AppColors.divider),
          Expanded(
            child: rowsAsync.when(
              loading: () => const _Skeleton(),
              error: (e, _) => _ErrorView(
                message:
                    e is ApiError ? e.combinedMessage : AppStrings.errorGeneric,
                onRetry: () =>
                    ref.invalidate(performanceIncentiveSheetProvider(anchor)),
              ),
              data: (rows) => rows.isEmpty
                  ? const _EmptyView()
                  : _SheetTable(rows: rows, months: months),
            ),
          ),
        ],
      ),
    );
  }

  void _shiftQuarter(int delta) {
    setState(() {
      var m = _anchor!.month + delta * 3;
      var y = _anchor!.year;
      while (m > 12) {
        m -= 12;
        y += 1;
      }
      while (m < 1) {
        m += 12;
        y -= 1;
      }
      _anchor = ReviewPeriod(y, m);
    });
    // Keep the anchor sticky for the next open.
    ref.read(performanceIncentiveAnchorProvider.notifier).state = _anchor;
  }
}

/// Purple quarter header with prev/next arrows + the fiscal-quarter label.
class _QuarterBar extends StatelessWidget {
  final ReviewPeriod anchor;
  final List<ReviewPeriod> months;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _QuarterBar({
    required this.anchor,
    required this.months,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [AppColors.primaryPurple, AppColors.primaryPurpleLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          _navBtn(Icons.chevron_left_rounded, onPrev),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  anchor.fiscalQuarterLabel,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  '${months.first.shortLabel} – ${months.last.shortLabel}',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9), fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _navBtn(Icons.chevron_right_rounded, onNext),
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

class _ReadOnlyHint extends StatelessWidget {
  const _ReadOnlyHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Icon(Icons.visibility_rounded, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              AppStrings.perfIncentiveReadOnly,
              style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// The wide, horizontally-scrollable report grid. Every Excel column is here.
class _SheetTable extends StatelessWidget {
  final List<PerformanceIncentiveRow> rows;
  final List<ReviewPeriod> months;
  const _SheetTable({required this.rows, required this.months});

  // Fixed column widths so the header and every row stay aligned in the scroll.
  static const double _wSr = 42,
      _wCode = 92,
      _wName = 168,
      _wAmt = 104,
      _wLoc = 140,
      _wMon = 60,
      _wTotal = 64,
      _wFixed = 108,
      _wPayable = 108,
      _wRemark = 150;

  double get _totalWidth =>
      _wSr +
      _wCode +
      _wName +
      _wAmt +
      _wLoc +
      _wMon * 6 +
      _wTotal +
      _wFixed +
      _wPayable +
      _wRemark;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: _totalWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            Divider(height: 1, color: AppColors.divider),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: rows.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: AppColors.divider),
                itemBuilder: (_, i) => _row(rows[i], i),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(double w, Widget child,
          {Alignment align = Alignment.centerLeft}) =>
      Container(
        width: w,
        // A right hairline on every cell gives the report proper vertical
        // gridlines; the row/header dividers supply the horizontal ones — so it
        // reads as a spreadsheet grid.
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: AppColors.divider)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Align(alignment: align, child: child),
      );

  Widget _header() {
    final h = TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        color: AppColors.textMuted,
        height: 1.2);
    Widget hc(double w, String label,
            {Alignment align = Alignment.centerLeft}) =>
        _cell(w, Text(label, style: h, textAlign: _alignToText(align)),
            align: align);
    return Container(
      color: AppColors.surface,
      child: Row(children: [
        hc(_wSr, AppStrings.perfIncColSrNo, align: Alignment.center),
        hc(_wCode, AppStrings.perfIncColCode),
        hc(_wName, AppStrings.perfIncColName),
        hc(_wAmt, AppStrings.perfIncColAmount, align: Alignment.centerRight),
        hc(_wLoc, AppStrings.perfIncColLocation),
        for (final m in months)
          hc(_wMon, 'Self\n${m.shortLabel}', align: Alignment.centerRight),
        for (final m in months)
          hc(_wMon, 'Mgmt\n${m.shortLabel}', align: Alignment.centerRight),
        hc(_wTotal, AppStrings.perfIncColTotal, align: Alignment.centerRight),
        hc(_wFixed, AppStrings.perfIncColFixed, align: Alignment.centerRight),
        hc(_wPayable, AppStrings.perfIncColPayable,
            align: Alignment.centerRight),
        hc(_wRemark, AppStrings.perfIncColRemark),
      ]),
    );
  }

  Widget _row(PerformanceIncentiveRow r, int index) {
    final t = TextStyle(fontSize: 12, color: AppColors.textPrimary);
    final tMuted = TextStyle(fontSize: 12, color: AppColors.textMuted);
    String pct(double? v) => v == null ? '—' : '${v.round()}%';
    return Container(
      color: index.isEven ? AppColors.surface : Colors.transparent,
      child: Row(children: [
        _cell(_wSr, Text('${r.srNo}', style: tMuted), align: Alignment.center),
        _cell(
            _wCode,
            Text(r.employeeCode,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary))),
        _cell(
            _wName,
            Text(r.employeeName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary))),
        _cell(
            _wAmt,
            Text(EmployeeFormatters.currencyInr(r.performanceIncentiveAmount),
                style: t),
            align: Alignment.centerRight),
        _cell(
            _wLoc,
            Text(
                (r.projectLocation ?? '').trim().isEmpty
                    ? '—'
                    : r.projectLocation!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tMuted)),
        for (final v in r.selfRatings)
          _cell(_wMon, Text(pct(v), style: t), align: Alignment.centerRight),
        for (final v in r.managementRatings)
          _cell(_wMon, Text(pct(v), style: t), align: Alignment.centerRight),
        _cell(
            _wTotal,
            Text('${r.total.round()}%',
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryPurple)),
            align: Alignment.centerRight),
        _cell(
            _wFixed,
            Text(EmployeeFormatters.currencyInr(r.quarterlyFixedIncentive),
                style: t),
            align: Alignment.centerRight),
        _cell(
            _wPayable,
            Text(EmployeeFormatters.currencyInr(r.payableIncentive),
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            align: Alignment.centerRight),
        _cell(_wRemark, _RemarkChip(remark: r.remark)),
      ]),
    );
  }

  TextAlign _alignToText(Alignment a) => a == Alignment.centerRight
      ? TextAlign.right
      : (a == Alignment.center ? TextAlign.center : TextAlign.left);
}

class _RemarkChip extends StatelessWidget {
  final String remark;
  const _RemarkChip({required this.remark});

  @override
  Widget build(BuildContext context) {
    // Only the paid state gets a chip; anything else is left blank for now.
    if (remark.isEmpty) return const SizedBox.shrink();
    final color = remark == PerformanceIncentiveRow.remarkPaid
        ? AppColors.success
        : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(remark,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
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
        ShimmerBox(height: 40, borderRadius: 10),
        SizedBox(height: 12),
        ShimmerBox(height: 52, borderRadius: 10),
        SizedBox(height: 10),
        ShimmerBox(height: 52, borderRadius: 10),
        SizedBox(height: 10),
        ShimmerBox(height: 52, borderRadius: 10),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_chart_outlined,
                size: 44, color: AppColors.textMuted),
            const SizedBox(height: 14),
            Text(AppStrings.perfIncentiveEmpty,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, color: AppColors.textSecondary, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

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
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text(AppStrings.commonRetry),
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
