import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../../auth/data/models/user.dart';
import '../../../employee/presentation/widgets/_formatters.dart';
import '../../data/models/monthly_review.dart';
import '../../data/models/review_stage.dart';
import '../providers/monthly_review_providers.dart';
import '../widgets/monthly_review_widgets.dart';

/// Admin review dashboard — a consolidated, at-a-glance table of every
/// employee's monthly review for the selected month. Filter chips (one per
/// KRA header) narrow to a KRA and add its per-employee score column; tapping
/// a row opens the review, where the admin performs the Management Review
/// (approve / return). Replaces the plain review list for the HR-tier tab.
class AdminReviewDashboardScreen extends ConsumerStatefulWidget {
  const AdminReviewDashboardScreen({super.key});

  @override
  ConsumerState<AdminReviewDashboardScreen> createState() =>
      _AdminReviewDashboardScreenState();
}

class _AdminReviewDashboardScreenState
    extends ConsumerState<AdminReviewDashboardScreen> {
  /// Selected KRA header. Null → no per-KRA column (overview of everyone).
  String? _kraFilter;

  /// Employee search text (name or code).
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(currentReviewScopeProvider)?.role;
    final periods = ref.watch(availablePeriodsProvider);
    final selected = ref.watch(selectedPeriodProvider) ?? periods.first;
    final reviewsAsync = ref.watch(monthlyReviewFullListProvider(selected));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.adminDashTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Column(
        children: [
          PeriodSelector(
            periods: periods,
            selected: selected,
            onSelect: (p) {
              setState(() => _kraFilter = null);
              ref.read(selectedPeriodProvider.notifier).state = p;
            },
          ),
          const Divider(height: 1, color: AppColors.divider),
          Expanded(
            child: reviewsAsync.when(
              loading: () => const _Skeleton(),
              error: (e, _) => _ErrorView(
                message: e.toString(),
                onRetry: () =>
                    ref.invalidate(monthlyReviewFullListProvider(selected)),
              ),
              data: (reviews) => _Content(
                reviews: reviews,
                role: role,
                kraFilter: _kraFilter,
                onKraFilter: (h) => setState(() => _kraFilter = h),
                search: _search,
                onSearch: (v) => setState(() => _search = v),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Content extends StatelessWidget {
  final List<MonthlyReview> reviews;
  final UserRole? role;
  final String? kraFilter;
  final ValueChanged<String?> onKraFilter;
  final String search;
  final ValueChanged<String> onSearch;
  const _Content({
    required this.reviews,
    required this.role,
    required this.kraFilter,
    required this.onKraFilter,
    required this.search,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    if (reviews.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(AppStrings.adminDashEmpty,
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    // Distinct KRA headers across every review, sorted.
    final headers = <String>{
      for (final r in reviews)
        for (final row in r.rows) row.name,
    }.toList()
      ..sort();

    final q = search.trim().toLowerCase();
    final visible = reviews.where((r) {
      // KRA filter → only employees who have that KRA.
      if (kraFilter != null && !r.rows.any((row) => row.name == kraFilter)) {
        return false;
      }
      // Search → name or code.
      if (q.isNotEmpty &&
          !r.employeeName.toLowerCase().contains(q) &&
          !r.employeeCode.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: TextField(
            onChanged: onSearch,
            decoration: InputDecoration(
              hintText: AppStrings.adminDashSearchHint,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              isDense: true,
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
            ),
          ),
        ),
        _FilterBar(headers: headers, selected: kraFilter, onSelect: onKraFilter),
        const Divider(height: 1, color: AppColors.divider),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _ReviewTable(
                  reviews: visible, role: role, kraFilter: kraFilter),
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  final List<String> headers;
  final String? selected;
  final ValueChanged<String?> onSelect;
  const _FilterBar({
    required this.headers,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        children: [
          _chip(AppStrings.adminDashFilterAll, selected == null,
              () => onSelect(null)),
          for (final h in headers)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _chip(h, selected == h, () => onSelect(h)),
            ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool sel, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: AppColors.primaryPurple.withValues(alpha: 0.18),
      backgroundColor: AppColors.surface,
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: sel ? AppColors.primaryPurple : AppColors.textSecondary,
      ),
      side: BorderSide(
        color: sel
            ? AppColors.primaryPurple.withValues(alpha: 0.5)
            : AppColors.divider,
      ),
    );
  }
}

class _ReviewTable extends StatelessWidget {
  final List<MonthlyReview> reviews;
  final UserRole? role;
  final String? kraFilter;
  const _ReviewTable({
    required this.reviews,
    required this.role,
    required this.kraFilter,
  });

  /// The employee's effective score for [header] as a 0–100 percent — the
  /// furthest rating stage that carries a value. Null when the employee has
  /// no such KRA, or it isn't scored yet.
  double? _kraPct(MonthlyReview r, String header) {
    for (final row in r.rows) {
      if (row.name != header) continue;
      for (final st in const [
        ReviewStage.reportingManagerRating,
        ReviewStage.accountHrRating,
        ReviewStage.selfRating,
      ]) {
        final s = row.scoreFor(st);
        if (s?.value != null && row.maxScore > 0) {
          return (s!.value! / row.maxScore) * 100;
        }
      }
      return null; // has the KRA, not scored yet
    }
    return null; // employee doesn't have this KRA
  }

  @override
  Widget build(BuildContext context) {
    return DataTable(
      showCheckboxColumn: false,
      columnSpacing: 26,
      headingRowHeight: 44,
      dataRowMinHeight: 52,
      dataRowMaxHeight: 64,
      columns: [
        const DataColumn(label: Text(AppStrings.adminDashColEmployee)),
        const DataColumn(label: Text(AppStrings.adminDashColGrade)),
        const DataColumn(label: Text(AppStrings.adminDashColStage)),
        const DataColumn(label: Text(AppStrings.adminDashColScore), numeric: true),
        const DataColumn(
            label: Text(AppStrings.adminDashColIncentive), numeric: true),
        if (kraFilter != null) DataColumn(label: Text(kraFilter!), numeric: true),
      ],
      rows: [
        for (final r in reviews)
          DataRow(
            selected: role != null && r.isActionableBy(role!),
            onSelectChanged: (_) =>
                context.push(AppRoutes.reviewsQuarterlyFor(r.employeeId)),
            cells: [
              DataCell(_EmployeeCell(
                review: r,
                needsReview: role != null && r.isActionableBy(role!),
              )),
              DataCell(Text(r.grade ?? '—')),
              DataCell(StagePill(
                  stage: r.currentStage, status: r.statusOf(r.currentStage))),
              DataCell(Text(EmployeeFormatters.percent(r.finalScorePct))),
              DataCell(Text(EmployeeFormatters.currencyInr(r.eligibleAmount))),
              if (kraFilter != null)
                DataCell(Builder(builder: (_) {
                  final p = _kraPct(r, kraFilter!);
                  return Text(p == null ? '—' : EmployeeFormatters.percent(p));
                })),
            ],
          ),
      ],
    );
  }
}

class _EmployeeCell extends StatelessWidget {
  final MonthlyReview review;
  final bool needsReview;
  const _EmployeeCell({required this.review, required this.needsReview});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (needsReview)
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 8),
            decoration: const BoxDecoration(
              color: AppColors.accentOrange,
              shape: BoxShape.circle,
            ),
          ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              review.employeeName,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
            if (review.employeeCode.isNotEmpty)
              Text(
                review.employeeCode,
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
          ],
        ),
      ],
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
        ShimmerBox(height: 40, borderRadius: 12),
        SizedBox(height: 16),
        ShimmerBox(height: 56, borderRadius: 12),
        SizedBox(height: 10),
        ShimmerBox(height: 56, borderRadius: 12),
        SizedBox(height: 10),
        ShimmerBox(height: 56, borderRadius: 12),
        SizedBox(height: 10),
        ShimmerBox(height: 56, borderRadius: 12),
      ],
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
                color: AppColors.error, size: 36),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
