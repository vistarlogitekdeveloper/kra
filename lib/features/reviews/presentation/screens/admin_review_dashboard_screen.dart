import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/adaptive_leading.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../../../core/widgets/workspace_drawer.dart';
import '../../../auth/data/models/user.dart';
import '../../../employee/presentation/widgets/_formatters.dart';
import '../../data/models/quarterly_review_summary.dart';
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
    final scope = ref.watch(currentReviewScopeProvider);
    final role = scope?.role;
    final userId = scope?.userId;
    final periods = ref.watch(availablePeriodsProvider);
    final selected = ref.watch(selectedPeriodProvider) ?? periods.first;
    final listAsync = ref.watch(quarterlyReviewDashboardProvider(selected));

    return Scaffold(
      backgroundColor: AppColors.background,
      // Workspace switcher so an admin isn't stranded here — the ☰ opens the
      // drawer to hop back to My KRA (review) / My Team / HR Admin.
      drawer: workspaceDrawerFor(ref),
      appBar: AppBar(
        leading: adaptiveLeading(context),
        title: const Text(AppStrings.adminDashTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: listAsync.when(
        loading: () => const _Skeleton(),
        error: (e, _) => _ErrorView(
          message: e.toString(),
          onRetry: () =>
              ref.invalidate(quarterlyReviewDashboardProvider(selected)),
        ),
        data: (items) => _Content(
          items: items,
          role: role,
          userId: userId,
          search: _search,
          onSearch: (v) => setState(() => _search = v),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  final List<QuarterlyReviewSummary> items;
  final UserRole? role;

  /// Signed-in user id — resolves the relationship rating stages (own review /
  /// reviews I'm the reporting manager of) for the "needs review" flag.
  final String? userId;
  final String search;
  final ValueChanged<String> onSearch;
  const _Content({
    required this.items,
    required this.role,
    required this.userId,
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
                borderSide: BorderSide(color: AppColors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.divider),
              ),
            ),
          ),
        ),
        Divider(height: 1, color: AppColors.divider),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(AppStrings.adminDashEmpty,
                        style: TextStyle(color: AppColors.textSecondary)),
                  ),
                )
              : _ReviewList(items: visible, role: role, userId: userId),
        ),
      ],
    );
  }
}

// Shared column flex weights so the wide-table header and rows line up. A
// Project Location column fills the space the Employee column used to waste;
// the incentive column carries two figures (payable + quarterly fixed).
const int _flexEmployee = 26;
const int _flexLocation = 22;
const int _flexGrade = 10;
const int _flexStage = 18;
const int _flexScore = 10;
const int _flexIncentive = 24;

// Below this width the columns can't breathe, so we switch to stacked cards —
// everything for one employee stays visible without any horizontal scroll.
const double _wideBreakpoint = 720;

// Every review opens in the quarterly KRA sheet — the single place to view and
// act on it, whatever its stage.
void _openReview(BuildContext context, QuarterlyReviewSummary s) =>
    context.push(AppRoutes.reviewsQuarterlyFor(s.employeeId));

/// Responsive review list. A width-filling table on wide screens (no more
/// horizontal scroll), one card per employee on phones — same columns, same
/// data, laid out to fit the viewport.
class _ReviewList extends StatelessWidget {
  final List<QuarterlyReviewSummary> items;
  final UserRole? role;
  final String? userId;
  const _ReviewList({
    required this.items,
    required this.role,
    required this.userId,
  });

  bool _needs(QuarterlyReviewSummary s) =>
      role != null && s.needsActionBy(role!, userId: userId);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= _wideBreakpoint) {
        return Column(
          children: [
            const _WideHeader(),
            Divider(height: 1, color: AppColors.divider),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 20),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: AppColors.divider),
                itemBuilder: (_, i) =>
                    _WideRow(summary: items[i], needsReview: _needs(items[i])),
              ),
            ),
          ],
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) =>
            _ReviewCard(summary: items[i], needsReview: _needs(items[i])),
      );
    });
  }
}

Widget _locationText(String? location) {
  final l = (location ?? '').trim();
  if (l.isEmpty) {
    return Text('—',
        style: TextStyle(fontSize: 12, color: AppColors.textMuted));
  }
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.location_on_rounded, size: 13, color: AppColors.textMuted),
      const SizedBox(width: 4),
      Flexible(
        child: Text(l,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12, height: 1.25, color: AppColors.textSecondary)),
      ),
    ],
  );
}

Widget _gradeChip(String? grade) {
  final g = (grade ?? '').trim();
  if (g.isEmpty || g == '—') {
    return Text('—',
        style: TextStyle(fontSize: 12, color: AppColors.textMuted));
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.primaryPurple.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(g,
        style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryPurple)),
  );
}

class _WideHeader extends StatelessWidget {
  const _WideHeader();

  @override
  Widget build(BuildContext context) {
    final h = TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        color: AppColors.textMuted,
        letterSpacing: 0.3);
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
              flex: _flexEmployee,
              child: Text(AppStrings.adminDashColEmployee, style: h)),
          Expanded(
              flex: _flexLocation,
              child: Text(AppStrings.adminDashColLocation, style: h)),
          Expanded(
              flex: _flexGrade,
              child:
                  Center(child: Text(AppStrings.adminDashColGrade, style: h))),
          Expanded(
              flex: _flexStage,
              child: Text(AppStrings.adminDashColStage, style: h)),
          Expanded(
              flex: _flexScore,
              child: Text(AppStrings.adminDashColScore,
                  textAlign: TextAlign.right, style: h)),
          Expanded(
              flex: _flexIncentive,
              child: Text(AppStrings.adminDashColPayable,
                  textAlign: TextAlign.right, style: h)),
        ],
      ),
    );
  }
}

/// Two-line incentive figure used in both the wide row and the narrow card:
/// the performance-based PAYABLE amount as the headline, with the fixed
/// quarterly incentive (the ceiling) beneath it.
class _IncentiveCell extends StatelessWidget {
  final QuarterlyReviewSummary summary;
  const _IncentiveCell({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          EmployeeFormatters.currencyInr(summary.payableIncentive),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 2),
        Text(
          '${AppStrings.adminDashFixedPrefix} '
          '${EmployeeFormatters.currencyInr(summary.quarterlyFixedIncentive)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _WideRow extends StatelessWidget {
  final QuarterlyReviewSummary summary;
  final bool needsReview;
  const _WideRow({required this.summary, required this.needsReview});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: needsReview
          ? AppColors.accentOrange.withValues(alpha: 0.06)
          : AppColors.surface,
      child: InkWell(
        onTap: () => _openReview(context, summary),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                flex: _flexEmployee,
                child:
                    _EmployeeCell(summary: summary, needsReview: needsReview),
              ),
              Expanded(
                flex: _flexLocation,
                child: _locationText(summary.projectLocation),
              ),
              Expanded(
                  flex: _flexGrade,
                  child: Center(child: _gradeChip(summary.employeeGrade))),
              Expanded(
                flex: _flexStage,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: StagePill(
                      stage: summary.stage, status: summary.stageStatus),
                ),
              ),
              Expanded(
                flex: _flexScore,
                child: Text(
                  EmployeeFormatters.percent(summary.scorePct),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryPurple),
                ),
              ),
              Expanded(
                flex: _flexIncentive,
                child: _IncentiveCell(summary: summary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final QuarterlyReviewSummary summary;
  final bool needsReview;
  const _ReviewCard({required this.summary, required this.needsReview});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openReview(context, summary),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: needsReview
                  ? AppColors.accentOrange.withValues(alpha: 0.5)
                  : AppColors.divider,
              width: needsReview ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _EmployeeCell(
                        summary: summary, needsReview: needsReview),
                  ),
                  const SizedBox(width: 8),
                  _gradeChip(summary.employeeGrade),
                ],
              ),
              if ((summary.projectLocation ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                _locationText(summary.projectLocation),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: StagePill(
                          stage: summary.stage, status: summary.stageStatus),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    EmployeeFormatters.percent(summary.scorePct),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryPurple),
                  ),
                  const SizedBox(width: 12),
                  _IncentiveCell(summary: summary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmployeeCell extends StatelessWidget {
  final QuarterlyReviewSummary summary;
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
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
            if (summary.employeeCode.isNotEmpty)
              Text(
                summary.employeeCode,
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
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
              style: TextStyle(color: AppColors.textSecondary),
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
