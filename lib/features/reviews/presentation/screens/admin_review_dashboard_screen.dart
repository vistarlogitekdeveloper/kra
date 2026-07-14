import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../../auth/data/models/user.dart';
import '../../../employee/presentation/widgets/_formatters.dart';
import '../../data/models/monthly_review_summary.dart';
import '../providers/monthly_review_providers.dart';
import '../widgets/monthly_review_widgets.dart';

/// Admin Review Dashboard — a searchable list of every employee's review.
/// Tapping an employee opens their quarterly KRA sheet. HR-tier only.
class AdminReviewDashboardScreen extends ConsumerStatefulWidget {
  const AdminReviewDashboardScreen({super.key});

  @override
  ConsumerState<AdminReviewDashboardScreen> createState() =>
      _AdminReviewDashboardScreenState();
}

class _AdminReviewDashboardScreenState
    extends ConsumerState<AdminReviewDashboardScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(currentReviewScopeProvider)?.role;
    final periods = ref.watch(availablePeriodsProvider);
    final selected = ref.watch(selectedPeriodProvider) ?? periods.first;
    final listAsync = ref.watch(monthlyReviewListProvider(selected));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.adminDashTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: listAsync.when(
        loading: () => const _Skeleton(),
        error: (e, _) => _ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(monthlyReviewListProvider(selected)),
        ),
        data: (items) => _Content(
          items: items,
          role: role,
          search: _search,
          onSearch: (v) => setState(() => _search = v),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  final List<MonthlyReviewSummary> items;
  final UserRole? role;
  final String search;
  final ValueChanged<String> onSearch;
  const _Content({
    required this.items,
    required this.role,
    required this.search,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final q = search.trim().toLowerCase();
    final visible = items.where((s) {
      if (q.isEmpty) return true;
      return s.employeeName.toLowerCase().contains(q) ||
          s.employeeCode.toLowerCase().contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
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
        const Divider(height: 1, color: AppColors.divider),
        Expanded(
          child: visible.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(AppStrings.adminDashEmpty,
                        style: TextStyle(color: AppColors.textSecondary)),
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _ReviewTable(items: visible, role: role),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ReviewTable extends StatelessWidget {
  final List<MonthlyReviewSummary> items;
  final UserRole? role;
  const _ReviewTable({required this.items, required this.role});

  @override
  Widget build(BuildContext context) {
    return DataTable(
      showCheckboxColumn: false,
      columnSpacing: 26,
      headingRowHeight: 44,
      dataRowMinHeight: 52,
      dataRowMaxHeight: 64,
      columns: const [
        DataColumn(label: Text(AppStrings.adminDashColEmployee)),
        DataColumn(label: Text(AppStrings.adminDashColGrade)),
        DataColumn(label: Text(AppStrings.adminDashColStage)),
        DataColumn(label: Text(AppStrings.adminDashColScore), numeric: true),
        DataColumn(label: Text(AppStrings.adminDashColIncentive), numeric: true),
      ],
      rows: [
        for (final s in items)
          DataRow(
            selected: role != null && s.needsActionBy(role!),
            onSelectChanged: (_) => context.push(
              s.opensReviewDetail
                  ? AppRoutes.monthlyReviewDetail(s.id)
                  : AppRoutes.reviewsQuarterlyFor(s.employeeId),
            ),
            cells: [
              DataCell(_EmployeeCell(
                summary: s,
                needsReview: role != null && s.needsActionBy(role!),
              )),
              DataCell(Text(s.employeeGrade ?? '—')),
              DataCell(StagePill(
                  stage: s.currentStage, status: s.currentStageStatus)),
              DataCell(Text(EmployeeFormatters.percent(s.finalScorePct))),
              DataCell(Text(
                  EmployeeFormatters.currencyInr(s.incentiveEligibleAmount ?? 0))),
            ],
          ),
      ],
    );
  }
}

class _EmployeeCell extends StatelessWidget {
  final MonthlyReviewSummary summary;
  final bool needsReview;
  const _EmployeeCell({required this.summary, required this.needsReview});

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
              summary.employeeName,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
            if (summary.employeeCode.isNotEmpty)
              Text(
                summary.employeeCode,
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
