import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/proof_file_saver.dart';
import '../../../hr/data/models/employee.dart';
import '../../data/models/review_stage.dart';
import '../../data/repositories/rating_report_repository.dart';

/// KRA rating report: HR, Accounts and management pick employees (all, some
/// or one), months and ratings, and download Excel or PDF. The server builds
/// the file by the same rules as the quarterly sheet.
class KraRatingReportScreen extends ConsumerStatefulWidget {
  const KraRatingReportScreen({super.key});

  @override
  ConsumerState<KraRatingReportScreen> createState() =>
      _KraRatingReportScreenState();
}

const _monthShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// The financial year (April to March) a month belongs to, by its start year.
int _fyOf(DateTime m) => m.month >= 4 ? m.year : m.year - 1;

/// The twelve months of a financial year, April first.
List<DateTime> _fyMonths(int fy) =>
    [for (var i = 0; i < 12; i++) DateTime(fy, 4 + i)];

String _label(DateTime m) => '${_monthShort[m.month - 1]} ${m.year}';

class _KraRatingReportScreenState extends ConsumerState<KraRatingReportScreen> {
  late final DateTime _thisMonth;
  late int _fy;
  final Set<DateTime> _months = {};

  bool _allEmployees = true;
  bool _includeInactive = false;
  final Set<String> _employeeIds = {};
  String _search = '';

  final Set<ReviewStage> _stages = {...ratingReportStages};
  RatingReportFormat _format = RatingReportFormat.excel;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _thisMonth = DateTime(now.year, now.month);
    // The month being rated now: last month.
    final last = DateTime(now.year, now.month - 1);
    _months.add(last);
    _fy = _fyOf(last);
  }

  bool _isFuture(DateTime m) => m.isAfter(_thisMonth);

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Why the download is not possible yet, or null when it is.
  String? get _blocker {
    if (_months.isEmpty) return AppStrings.ratingReportNeedMonth;
    if (_months.length > 24) return AppStrings.ratingReportTooManyMonths;
    if (_stages.isEmpty) return AppStrings.ratingReportNeedRating;
    if (!_allEmployees && _employeeIds.isEmpty) {
      return AppStrings.ratingReportNeedEmployee;
    }
    return null;
  }

  Future<void> _download() async {
    if (_blocker != null || _downloading) return;
    setState(() => _downloading = true);
    try {
      final file = await ref.read(ratingReportRepositoryProvider).download(
            RatingReportRequest(
              months: _months.toList(),
              employeeIds: _allEmployees ? null : _employeeIds.toList(),
              stages: _stages,
              format: _format,
            ),
          );
      final ok = await saveProofFile(
        bytes: file.bytes,
        fileName: file.fileName,
        mime: file.mime,
      );
      _snack(ok
          ? AppStrings.ratingReportDone(file.fileName, file.employees, file.reviews)
          : AppStrings.perfIncentiveExportUnsupported);
    } on ApiError catch (e) {
      _snack(e.statusCode == 404
          ? AppStrings.ratingReportNothing
          : e.combinedMessage);
    } catch (_) {
      _snack(AppStrings.ratingReportFailed);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocker = _blocker;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: AppStrings.commonBack,
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.hrHome),
        ),
        title: const Text(AppStrings.ratingReportTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(
                AppStrings.ratingReportIntro,
                style: TextStyle(
                    fontSize: 13, color: AppColors.textSecondary, height: 1.45),
              ),
              const SizedBox(height: 16),
              _section('1. Employees', _employeesSection()),
              _section('2. Months', _monthsSection()),
              _section('3. Ratings', _ratingsSection()),
              _section('4. Format', _formatSection()),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('ratingReportDownload'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: blocker == null && !_downloading ? _download : null,
                icon: _downloading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.download_rounded),
                label: Text(_downloading
                    ? AppStrings.ratingReportPreparing
                    : 'Download ${_format.label}'),
              ),
              if (blocker != null) ...[
                const SizedBox(height: 8),
                Text(blocker,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // A Material (not a decorated Container): the tick boxes inside paint their
  // ripple on the nearest Material, which a coloured box would hide.
  Widget _section(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.divider),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: _sectionBody(title, child),
        ),
      ),
    );
  }

  Widget _sectionBody(String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        child,
      ],
    );
  }

  // ── 1. Employees ──────────────────────────────────────────────────────────

  Widget _employeesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
                value: true,
                icon: Icon(Icons.groups_rounded),
                label: Text('All employees')),
            ButtonSegment(
                value: false,
                icon: Icon(Icons.person_search_rounded),
                label: Text('Choose employees')),
          ],
          selected: {_allEmployees},
          onSelectionChanged: (s) => setState(() => _allEmployees = s.first),
        ),
        const SizedBox(height: 8),
        if (_allEmployees)
          Text(AppStrings.ratingReportAllHint,
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary))
        else
          _employeePicker(),
      ],
    );
  }

  Widget _employeePicker() {
    final async = ref.watch(ratingReportEmployeesProvider(_includeInactive));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Column(
        children: [
          Text(e is ApiError ? e.message : AppStrings.ratingReportEmployeesFailed,
              style: const TextStyle(color: AppColors.error)),
          TextButton(
            onPressed: () =>
                ref.invalidate(ratingReportEmployeesProvider(_includeInactive)),
            child: const Text('Retry'),
          ),
        ],
      ),
      data: (employees) {
        final q = _search.trim().toLowerCase();
        final shown = q.isEmpty
            ? employees
            : employees
                .where((e) =>
                    e.fullName.toLowerCase().contains(q) ||
                    e.employeeCode.toLowerCase().contains(q))
                .toList();
        // A selection made with "include deactivated" on must not linger,
        // invisibly, once they are hidden again.
        final visibleIds = employees.map((e) => e.id).toSet();
        final chosen = _employeeIds.where(visibleIds.contains).length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('ratingReportSearch'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search by name or employee code',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 6),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                TextButton(
                  onPressed: shown.isEmpty
                      ? null
                      : () => setState(
                          () => _employeeIds.addAll(shown.map((e) => e.id))),
                  child: Text(q.isEmpty ? 'Select all' : 'Select all shown'),
                ),
                TextButton(
                  onPressed: _employeeIds.isEmpty
                      ? null
                      : () => setState(_employeeIds.clear),
                  child: const Text('Clear'),
                ),
                FilterChip(
                  label: const Text('Include deactivated'),
                  selected: _includeInactive,
                  onSelected: (v) => setState(() {
                    _includeInactive = v;
                    if (!v) {
                      // Drop the deactivated ones that were picked.
                      final active = employees
                          .where((e) => e.isActive)
                          .map((e) => e.id)
                          .toSet();
                      _employeeIds.retainWhere(active.contains);
                    }
                  }),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text('$chosen selected',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryPurple)),
                ),
              ],
            ),
            Container(
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.divider),
                borderRadius: BorderRadius.circular(10),
              ),
              child: shown.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('No employee matches "$_search".',
                          style: TextStyle(color: AppColors.textSecondary)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: shown.length,
                      itemBuilder: (_, i) => _employeeTile(shown[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _employeeTile(Employee e) {
    final picked = _employeeIds.contains(e.id);
    final sub = [
      e.employeeCode,
      if ((e.projectLocation ?? '').isNotEmpty) e.projectLocation!,
      if (!e.isActive) 'Deactivated',
    ].join('  ·  ');
    return CheckboxListTile(
      dense: true,
      value: picked,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(e.fullName),
      subtitle: Text(sub),
      onChanged: (v) => setState(() {
        if (v == true) {
          _employeeIds.add(e.id);
        } else {
          _employeeIds.remove(e.id);
        }
      }),
    );
  }

  // ── 2. Months ─────────────────────────────────────────────────────────────

  Widget _monthsSection() {
    final currentFy = _fyOf(_thisMonth);
    final years = [for (var y = currentFy; y >= currentFy - 3; y--) y];
    final months = _fyMonths(_fy);
    void setQuarter(int q) => setState(() {
          for (final m in months.sublist(q * 3, q * 3 + 3)) {
            if (!_isFuture(m)) _months.add(m);
          }
        });
    final picked = _months.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Financial year',
                style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(width: 12),
            DropdownButton<int>(
              value: _fy,
              items: [
                for (final y in years)
                  DropdownMenuItem(
                      value: y,
                      child: Text('FY $y-${(y + 1).toString().substring(2)}')),
              ],
              onChanged: (y) => setState(() => _fy = y ?? _fy),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in months)
              FilterChip(
                label: Text(_label(m)),
                selected: _months.contains(m),
                // A month that has not started has no reviews to report.
                onSelected: _isFuture(m)
                    ? null
                    : (v) => setState(
                        () => v ? _months.add(m) : _months.remove(m)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          children: [
            for (var q = 0; q < 4; q++)
              OutlinedButton(
                onPressed: _isFuture(months[q * 3]) ? null : () => setQuarter(q),
                child: Text('Q${q + 1}'),
              ),
            OutlinedButton(
              onPressed: () => setState(() {
                for (final m in months) {
                  if (!_isFuture(m)) _months.add(m);
                }
              }),
              child: const Text('Whole year'),
            ),
            TextButton(
              onPressed:
                  _months.isEmpty ? null : () => setState(_months.clear),
              child: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          picked.isEmpty
              ? 'No month selected'
              : '${picked.length} month${picked.length == 1 ? '' : 's'}: '
                  '${picked.map(_label).join(', ')}',
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
        if (picked.length > 24)
          const Text(AppStrings.ratingReportTooManyMonths,
              style: TextStyle(fontSize: 12.5, color: AppColors.error)),
      ],
    );
  }

  // ── 3. Ratings ────────────────────────────────────────────────────────────

  static const _stageLabels = {
    ReviewStage.selfRating: ('Self rating', 'The employee\'s own score'),
    ReviewStage.reportingManagerRating:
        ('Manager rating', 'The reporting manager\'s score'),
    ReviewStage.accountHrRating: ('HR rating', 'KRAs assigned to HR'),
    ReviewStage.financeRating: ('Accounts rating', 'KRAs assigned to Accounts'),
    ReviewStage.managementReview: (
      'Management rating',
      'Also adds the final score, incentive and payable'
    ),
  };

  Widget _ratingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in ratingReportStages)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _stages.contains(s),
            title: Text(_stageLabels[s]!.$1),
            subtitle: Text(_stageLabels[s]!.$2),
            onChanged: (v) => setState(
                () => v == true ? _stages.add(s) : _stages.remove(s)),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _stages.length == ratingReportStages.length
                ? null
                : () => setState(() => _stages.addAll(ratingReportStages)),
            child: const Text('Select all ratings'),
          ),
        ),
      ],
    );
  }

  // ── 4. Format ─────────────────────────────────────────────────────────────

  Widget _formatSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<RatingReportFormat>(
          segments: const [
            ButtonSegment(
                value: RatingReportFormat.excel,
                icon: Icon(Icons.table_chart_rounded),
                label: Text('Excel')),
            ButtonSegment(
                value: RatingReportFormat.pdf,
                icon: Icon(Icons.picture_as_pdf_rounded),
                label: Text('PDF')),
          ],
          selected: {_format},
          onSelectionChanged: (s) => setState(() => _format = s.first),
        ),
        const SizedBox(height: 8),
        Text(
          _format == RatingReportFormat.excel
              ? AppStrings.ratingReportExcelHint
              : AppStrings.ratingReportPdfHint,
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
