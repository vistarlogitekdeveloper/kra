import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/adaptive_leading.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../../../core/widgets/workspace_drawer.dart';
import '../../../auth/data/models/user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../hr/presentation/widgets/confirm_action_dialog.dart';
import '../../../manager/presentation/screens/my_team/dashboard/widgets/no_reports_empty_state.dart';
import '../../../employee/presentation/widgets/_formatters.dart';
import '../../data/models/monthly_review.dart';
import '../../data/models/monthly_review_summary.dart';
import '../../data/models/stage_status.dart';
import '../providers/monthly_review_providers.dart';
import '../widgets/monthly_review_widgets.dart';

/// Role-adaptive monthly review dashboard. The list is scoped by the
/// provider (employee → own, manager → team, HR/finance/admin → all);
/// this screen renders it with a month selector and routes into each
/// review's stage screen.
class MonthlyReviewDashboardScreen extends ConsumerStatefulWidget {
  const MonthlyReviewDashboardScreen({super.key});

  @override
  ConsumerState<MonthlyReviewDashboardScreen> createState() =>
      _MonthlyReviewDashboardScreenState();
}

class _MonthlyReviewDashboardScreenState
    extends ConsumerState<MonthlyReviewDashboardScreen> {
  String _search = '';

  /// When true, the list is narrowed to reviews awaiting THIS user's action —
  /// the KRAs a reviewer (or self-rater) still has to rate.
  bool _awaitingMine = false;

  String _title(UserRole? role) {
    switch (role) {
      case UserRole.employee:
      case UserRole.ops:
        return AppStrings.monthlyReviewsTitleSelf;
      case UserRole.manager:
      case UserRole.bdManager:
      case UserRole.warehouseMgr:
        return AppStrings.monthlyReviewsTitleTeam;
      default:
        return AppStrings.monthlyReviewsTitleAll;
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.profileLogoutConfirmTitle,
      message: AppStrings.profileLogoutConfirmMessage,
      confirmLabel: AppStrings.profileLogout,
      cancelLabel: AppStrings.commonCancel,
      icon: Icons.logout_rounded,
      accentColor: AppColors.error,
    );
    if (ok == true) {
      ref.read(authStateProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(currentReviewScopeProvider);
    final role = scope?.role;
    final userId = scope?.userId;
    final periods = ref.watch(availablePeriodsProvider);
    final selected = ref.watch(selectedPeriodProvider) ?? periods.first;
    // HR / Accounts land here as their home and have no bottom-nav Profile to
    // log out from, so surface logout in the app bar for those review roles.
    final reviewOnly = role == UserRole.hr || role == UserRole.finance;

    return Scaffold(
      backgroundColor: AppColors.background,
      // Left "☰" workspace menu — auto-rendered by the AppBar when a drawer is
      // present. Null (no menu) for plain employees who have only My KRA.
      drawer: workspaceDrawerFor(ref),
      appBar: AppBar(
        leading: adaptiveLeading(context),
        title: Text(_title(role)),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          // Management / HR / Accounts can open the quarterly Performance
          // Incentive Sheet from here (they have no HR "Reports" tab).
          if (role != null && AppRoutes.canReview(role))
            IconButton(
              icon: const Icon(Icons.payments_rounded),
              tooltip: AppStrings.perfIncentiveTitle,
              onPressed: () => context.push(AppRoutes.perfIncentiveSheet),
            ),
          if (reviewOnly)
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: AppStrings.profileLogout,
              onPressed: _confirmLogout,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: AppStrings.monthlyReviewsSearchHint,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
            child: Row(
              children: [
                _FilterChip(
                  label: AppStrings.monthlyReviewsFilterAll,
                  selected: !_awaitingMine,
                  onTap: () => setState(() => _awaitingMine = false),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: AppStrings.monthlyReviewsFilterMine,
                  icon: Icons.assignment_turned_in_rounded,
                  selected: _awaitingMine,
                  onTap: () => setState(() => _awaitingMine = true),
                ),
              ],
            ),
          ),
          Expanded(
            child: _ReviewList(
              period: selected,
              role: role,
              userId: userId,
              search: _search,
              awaitingMine: _awaitingMine,
            ),
          ),
        ],
      ),
    );
  }
}

/// A pill toggle for the review list's "All / Awaiting my review" filter.
class _FilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primaryPurple : AppColors.textSecondary;
    return Material(
      color: selected
          ? AppColors.primaryPurple.withValues(alpha: 0.12)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primaryPurple : AppColors.divider,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 5),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewList extends ConsumerWidget {
  final ReviewPeriod period;
  final UserRole? role;

  /// Signed-in user id — resolves the relationship rating stages (own review /
  /// reviews I'm the reporting manager of) for the "needs you" badge.
  final String? userId;

  /// Free-text filter over employee name + code.
  final String search;

  /// Narrow to reviews awaiting this user's action.
  final bool awaitingMine;
  const _ReviewList({
    required this.period,
    required this.role,
    required this.userId,
    required this.search,
    required this.awaitingMine,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(monthlyReviewListProvider(period));
    return RefreshIndicator(
      color: AppColors.primaryPurple,
      onRefresh: () async => ref.invalidate(monthlyReviewListProvider(period)),
      child: listAsync.when(
        loading: () => const _DashboardSkeleton(),
        error: (e, _) {
          // A manager with zero direct reports (the roster load 403s) gets
          // the friendly no-team empty state with a jump into their own KRA
          // — never a raw 403 on the dashboard they land next to.
          if (e is ApiError && e.isNoDirectReports) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [NoReportsEmptyState()],
            );
          }
          // Everything else (cold-start timeout, roster failure, …) gets a
          // friendly message + retry — never a raw `ApiError(...)` dump.
          return _ReviewListError(
            message: e is ApiError ? e.message : AppStrings.errorGeneric,
            onRetry: () => ref.invalidate(monthlyReviewListProvider(period)),
          );
        },
        data: (allItems) {
          if (allItems.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 80),
                Center(child: Text(AppStrings.monthlyReviewsEmpty)),
              ],
            );
          }
          // Filter by employee name OR code (case-insensitive), and — when the
          // "Awaiting my review" chip is on — to reviews needing THIS user's
          // action (a KRA they still have to rate / sign off).
          final q = search.trim().toLowerCase();
          final items = allItems.where((s) {
            if (q.isNotEmpty &&
                !s.employeeName.toLowerCase().contains(q) &&
                !s.employeeCode.toLowerCase().contains(q)) {
              return false;
            }
            if (awaitingMine &&
                !(role != null && s.needsActionBy(role!, userId: userId))) {
              return false;
            }
            return true;
          }).toList();
          if (items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),
                Center(
                  child: Text(awaitingMine
                      ? AppStrings.monthlyReviewsNoneAwaiting
                      : AppStrings.monthlyReviewsNoMatch),
                ),
              ],
            );
          }
          // Responsive grid: one column on a phone, two on a tablet, three on
          // a desktop — so a wide screen shows many reviews at once instead of
          // one stretched-out card per row. Pull-to-refresh still works via the
          // always-scrollable single scroll view.
          return LayoutBuilder(builder: (context, constraints) {
            final w = constraints.maxWidth;
            final cols = w >= 1080 ? 3 : (w >= 680 ? 2 : 1);
            const gap = 10.0;
            final inner = w - 32; // horizontal padding (16 each side)
            final tileW = cols == 1 ? inner : (inner - gap * (cols - 1)) / cols;
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              child: Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final s in items)
                    SizedBox(
                      width: tileW,
                      child:
                          _ReviewTile(summary: s, role: role, userId: userId),
                    ),
                ],
              ),
            );
          });
        },
      ),
    );
  }
}

class _ReviewTile extends ConsumerStatefulWidget {
  final MonthlyReviewSummary summary;
  final UserRole? role;
  final String? userId;
  const _ReviewTile({
    required this.summary,
    required this.role,
    required this.userId,
  });

  @override
  ConsumerState<_ReviewTile> createState() => _ReviewTileState();
}

class _ReviewTileState extends ConsumerState<_ReviewTile> {
  bool _payingOut = false;

  MonthlyReviewSummary get summary => widget.summary;
  UserRole? get role => widget.role;
  String? get userId => widget.userId;

  // Settle the incentive for this review — the payout action Accounts/Finance
  // runs once the management review is done. Confirms first (it's terminal),
  // then refreshes the list so the tile flips to a "Paid" badge.
  Future<void> _markPaid() async {
    final scope = ref.read(currentReviewScopeProvider);
    if (scope == null) return;
    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.monthlyReviewMarkPaidConfirmTitle,
      message: AppStrings.monthlyReviewMarkPaidConfirmMessage,
      confirmLabel: AppStrings.monthlyReviewMarkPaid,
      icon: Icons.payments_rounded,
    );
    if (ok != true) return;
    setState(() => _payingOut = true);
    try {
      await ref.read(monthlyReviewRepositoryProvider).markPaid(
            summary.id,
            actorId: scope.userId,
            actorName: scope.userName,
          );
      ref.invalidate(monthlyReviewListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.monthlyReviewPaid)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.monthlyReviewActionFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _payingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsYou =
        role != null && summary.needsActionBy(role!, userId: userId);
    final completed = summary.displayStage.isTerminal;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        // Every review — whatever its stage — opens in the quarterly KRA sheet,
        // the single place to view + act on it (Self / Review / Management
        // columns, evidence and payout all live there).
        onTap: () =>
            context.push(AppRoutes.reviewsQuarterlyFor(summary.employeeId)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: needsYou
                  ? AppColors.accentOrange.withValues(alpha: 0.5)
                  : AppColors.divider,
              width: needsYou ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.employeeName,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        StagePill(
                          stage: summary.displayStage,
                          status: completed
                              ? StageStatus.submitted
                              : summary.displayStatus,
                        ),
                        if (needsYou) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.accentOrange,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              AppStrings.monthlyReviewsNeedsYou,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    EmployeeFormatters.percent(summary.finalScorePct),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryPurple,
                    ),
                  ),
                  if (summary.employeeCode.isNotEmpty)
                    Text(
                      summary.employeeCode,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
              _PayoutControl(
                paid: summary.payoutPaid,
                canMarkPaid: role != null && summary.canMarkPaidBy(role!),
                busy: _payingOut,
                onMarkPaid: _markPaid,
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// The incentive-payout affordance on a review tile: a green "Paid" check once
/// settled, or — for Accounts/Finance, after the management review — a tappable
/// check to settle it. Nothing at all when neither applies, so ordinary tiles
/// are unchanged.
class _PayoutControl extends StatelessWidget {
  final bool paid;
  final bool canMarkPaid;
  final bool busy;
  final VoidCallback onMarkPaid;
  const _PayoutControl({
    required this.paid,
    required this.canMarkPaid,
    required this.busy,
    required this.onMarkPaid,
  });

  @override
  Widget build(BuildContext context) {
    if (paid) {
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: AppColors.success.withValues(alpha: 0.35)),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle_rounded,
                size: 14, color: AppColors.success),
            SizedBox(width: 4),
            Text(AppStrings.monthlyReviewPaidBadge,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.success)),
          ]),
        ),
      );
    }
    if (!canMarkPaid) return const SizedBox.shrink();
    return IconButton(
      onPressed: busy ? null : onMarkPaid,
      tooltip: AppStrings.monthlyReviewMarkPaidTooltip,
      visualDensity: VisualDensity.compact,
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation(AppColors.success),
              ),
            )
          : const Icon(Icons.check_circle_outline_rounded,
              color: AppColors.success),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        ShimmerBox(height: 44, borderRadius: 20),
        SizedBox(height: 16),
        ShimmerBox(height: 78, borderRadius: 16),
        SizedBox(height: 12),
        ShimmerBox(height: 78, borderRadius: 16),
        SizedBox(height: 12),
        ShimmerBox(height: 78, borderRadius: 16),
      ],
    );
  }
}

/// Friendly, retryable error for the monthly-review list — replaces a raw
/// `e.toString()` dump so a Render cold-start timeout reads as a message, not
/// a technical class name. Scrollable so pull-to-refresh still works.
class _ReviewListError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ReviewListError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
      children: [
        const Icon(Icons.error_outline_rounded,
            size: 44, color: AppColors.error),
        const SizedBox(height: 14),
        Text(
          AppStrings.errorGeneric,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(AppStrings.commonRetry),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryPurple,
            ),
          ),
        ),
      ],
    );
  }
}
