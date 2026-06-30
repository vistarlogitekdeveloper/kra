import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/ambient_background.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
import '../../../../core/widgets/slow_load_hint.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/models/hr_dashboard_models.dart';
import '../providers/hr_dashboard_providers.dart';
import '../widgets/_formatters.dart';
import '../widgets/empty_state.dart';
import '../widgets/location_heatmap.dart';
import '../widgets/overview_stat_card.dart';
import '../widgets/quick_action_button.dart';

/// HR home screen. Progressive loading — each panel fetches its own data.
class HrHomeScreen extends ConsumerWidget {
  const HrHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // App bar stays as a solid dark surface above the scrolling content.
      // Letting the body scroll behind it (extendBodyBehindAppBar: true)
      // caused the 'HR Dashboard' title to visually overlap whatever card
      // happened to be at that scroll position. The AmbientBackground
      // still wraps the body below, so the aurora glows + S watermark
      // continue underneath without competing with the title.
      appBar: AppBar(
        title: const Text(AppStrings.hrHomeTitle),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
            tooltip: 'Menu',
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => ref.read(authStateProvider.notifier).logout(),
            tooltip: AppStrings.dashboardLogoutTooltip,
          ),
        ],
      ),
      body: AmbientBackground(
        child: RefreshIndicator(
          color: AppColors.pink,
          onRefresh: () async {
            // Invalidate all root dashboard providers. Family providers
            // will auto-refresh when they get watched again.
            ref.invalidate(hrOverviewProvider);
            ref.invalidate(hrActiveCycleProvider);
            ref.invalidate(hrRecentActivityProvider);
            // Wait for the root provider to finish so the pull spinner hides
            try {
              await ref.read(hrOverviewProvider.future);
            } catch (_) {
              // Ignore errors for refresh pull
            }
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              _OverviewSection(),
              SizedBox(height: 24),
              _SectionHeader(title: AppStrings.hrHomeQuickActions),
              SizedBox(height: 10),
              _QuickActionsGrid(),
              SizedBox(height: 24),
              _CycleDependentSections(),
              _SectionHeader(title: AppStrings.hrRecentActivityTitle),
              SizedBox(height: 6),
              _RecentActivitySection(),
              SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Overview Section (Greeting + 4 Stats)
// ─────────────────────────────────────────────────────────────────────

class _OverviewSection extends ConsumerWidget {
  const _OverviewSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(hrOverviewProvider);
    final authState = ref.watch(authStateProvider);
    final user = authState is AuthAuthenticated ? authState.user : null;
    final fullName = user?.fullName ?? 'there';

    return overviewAsync.when(
      loading: () => const _OverviewLoading(),
      error: (e, _) => _ErrorPanel(
        message: e.toString(),
        onRetry: () => ref.invalidate(hrOverviewProvider),
      ),
      data: (overview) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GreetingCard(name: fullName, cycle: overview.cycle),
            const SizedBox(height: 18),
            _StatsGrid(overview: overview),
          ],
        );
      },
    );
  }
}

class _OverviewLoading extends StatelessWidget {
  const _OverviewLoading();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SlowLoadHint(),
        const ShimmerBox(height: 120, borderRadius: 20),
        const SizedBox(height: 18),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.18,
          children: const [
            DashboardCardSkeleton(),
            DashboardCardSkeleton(),
            DashboardCardSkeleton(),
            DashboardCardSkeleton(),
          ],
        ),
      ],
    );
  }
}

class _GreetingCard extends StatelessWidget {
  final String name;
  final HrOverviewCycle? cycle;
  const _GreetingCard({required this.name, required this.cycle});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    if (hour < 21) return 'Good evening';
    return 'Good night';
  }

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('EEEE, d MMMM yyyy').format(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryPurple, AppColors.primaryPurpleLight],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryPurple.withValues(alpha: 0.30),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_greeting()}, $name',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            today,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.80),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          if (cycle != null)
            _ActiveCyclePill(cycle: cycle!)
          else
            const _NoActiveCyclePill(),
        ],
      ),
    );
  }
}

class _ActiveCyclePill extends StatelessWidget {
  final HrOverviewCycle cycle;
  const _ActiveCyclePill({required this.cycle});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final daysRemaining =
        cycle.endDate.difference(DateTime(now.year, now.month, now.day)).inDays;
    final daysLabel = daysRemaining < 0
        ? AppStrings.hrHomeCycleEnded
        : '$daysRemaining ${daysRemaining == 1 ? AppStrings.hrHomeDayRemaining : AppStrings.hrHomeDaysRemaining}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.event_outlined, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${cycle.name} · $daysLabel',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoActiveCyclePill extends StatelessWidget {
  const _NoActiveCyclePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.white, size: 14),
          SizedBox(width: 6),
          Text(
            AppStrings.hrHomeNoActiveCycle,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final HrOverview overview;
  const _StatsGrid({required this.overview});

  @override
  Widget build(BuildContext context) {
    final cards = [
      OverviewStatCard(
        icon: Icons.groups_rounded,
        label: AppStrings.hrKpiActiveEmployees,
        value: overview.activeEmployees.toString(),
        iconBg: AppColors.primaryPurple.withValues(alpha: 0.10),
        iconFg: AppColors.primaryPurple,
      ),
      OverviewStatCard(
        icon: Icons.pending_actions_rounded,
        label: AppStrings.hrKpiPendingReviews,
        value: overview.pendingReviews.toString(),
        iconBg: AppColors.accentOrange.withValues(alpha: 0.12),
        iconFg: AppColors.accentOrange,
      ),
      OverviewStatCard(
        icon: Icons.payments_rounded,
        label: AppStrings.hrKpiQuarterPayout,
        value: HrFormatters.currencyInr(overview.totalPayout),
        iconBg: AppColors.accentYellow.withValues(alpha: 0.20),
        iconFg: AppColors.accentYellow,
        valueColor: AppColors.textPrimary,
      ),
      // Empty slot for balance
      const SizedBox.shrink(),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final crossAxisCount = wide ? 4 : 2;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: wide ? 1.4 : 1.18,
          children: cards,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Cycle-Dependent Sections (Deadlines, Pipeline, Action Items)
// ─────────────────────────────────────────────────────────────────────

class _CycleDependentSections extends ConsumerWidget {
  const _CycleDependentSections();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeCycleIdAsync = ref.watch(hrActiveCycleIdProvider);

    return activeCycleIdAsync.when(
      loading: () => const _CycleDependentLoading(),
      error: (e, _) => _ErrorPanel(
        message: e.toString(),
        onRetry: () => ref.invalidate(hrActiveCycleProvider),
      ),
      data: (cycleId) {
        if (cycleId == null) {
          return const SizedBox
              .shrink(); // No active cycle -> hide these panels
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHeader(title: AppStrings.hrDeadlinesTitle),
            const SizedBox(height: 6),
            _DeadlinesSection(cycleId: cycleId),
            const SizedBox(height: 24),
            const _SectionHeader(title: AppStrings.hrActionItemsTitle),
            const SizedBox(height: 6),
            _ActionItemsSection(cycleId: cycleId),
            const SizedBox(height: 24),
            const _SectionHeader(title: AppStrings.hrPipelineTitle),
            const SizedBox(height: 6),
            _PipelineSection(cycleId: cycleId),
            const SizedBox(height: 24),
            const _SectionHeader(title: AppStrings.hrHeatmapTitle),
            const SizedBox(height: 6),
            LocationHeatmap(cycleId: cycleId),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

class _CycleDependentLoading extends StatelessWidget {
  const _CycleDependentLoading();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ShimmerBox(height: 16, width: 120, borderRadius: 6),
        const SizedBox(height: 12),
        for (int i = 0; i < 2; i++) ...[
          const ShimmerBox(height: 60, borderRadius: 14),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

// ── Deadlines ──

class _DeadlinesSection extends ConsumerWidget {
  final String cycleId;
  const _DeadlinesSection({required this.cycleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deadlinesAsync = ref.watch(hrDeadlinesProvider(cycleId));

    return deadlinesAsync.when(
      loading: () => const ShimmerBox(height: 80, borderRadius: 14),
      error: (e, _) => _ErrorPanel(
        message: e.toString(),
        onRetry: () => ref.invalidate(hrDeadlinesProvider(cycleId)),
      ),
      data: (deadlines) {
        if (deadlines.isEmpty) {
          return const Text('No upcoming deadlines.',
              style: TextStyle(color: AppColors.textMuted));
        }
        return SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: deadlines.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final d = deadlines[index];
              return Container(
                width: 140,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: d.isOverdue
                        ? AppColors.error.withValues(alpha: 0.5)
                        : d.isUrgent
                            ? AppColors.accentOrange.withValues(alpha: 0.5)
                            : AppColors.divider,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      d.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      d.isOverdue
                          ? AppStrings.hrOverdue
                          : '${d.daysRemaining} days left',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: d.isOverdue
                            ? AppColors.error
                            : d.isUrgent
                                ? AppColors.accentOrange
                                : AppColors.primaryPurple,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ── Action Items ──

class _ActionItemsSection extends ConsumerWidget {
  final String cycleId;
  const _ActionItemsSection({required this.cycleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionsAsync = ref.watch(hrActionItemsProvider(cycleId));

    return actionsAsync.when(
      loading: () => const ShimmerBox(height: 100, borderRadius: 14),
      error: (e, _) => _ErrorPanel(
        message: e.toString(),
        onRetry: () => ref.invalidate(hrActionItemsProvider(cycleId)),
      ),
      data: (actions) {
        if (actions.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: AppColors.success.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.success),
                SizedBox(width: 12),
                Text(
                  AppStrings.hrAllCaughtUp,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          children: actions.map((item) {
            Color color;
            IconData icon;
            if (item.severity == ActionSeverity.critical) {
              color = AppColors.error;
              icon = Icons.error_rounded;
            } else if (item.severity == ActionSeverity.warning) {
              color = AppColors.accentOrange;
              icon = Icons.warning_rounded;
            } else {
              color = AppColors.primaryPurple;
              icon = Icons.info_rounded;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: ListTile(
                leading: Icon(icon, color: color),
                title: Text(
                  item.headline,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                trailing: item.deepLink != null
                    ? const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textMuted)
                    : null,
                onTap: item.deepLink == null
                    ? null
                    : () => _openActionItem(context, item),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  /// Routes an action item to the right screen. Two resolution paths:
  ///
  ///   1. **Direct path** — if `deepLink` looks like an internal route
  ///      (starts with `/hr/` or `/employee/`), navigate to it directly.
  ///      Lets the backend point at any in-app surface, including
  ///      parameterised paths the client doesn't need to know about.
  ///   2. **Key-based fallback** — older payloads supply a [key] like
  ///      `PENDING_REVIEWS` or `UNASSIGNED_EMPLOYEES`; map those to the
  ///      best-fit `AppRoutes` constant.
  ///
  /// If neither resolves, surface a snackbar rather than fail silently —
  /// the user clicked something and expects feedback.
  /// Base paths actually registered in the router. A deep-link is only
  /// followed when it matches one of these — older code navigated to any
  /// `/hr/` or `/employee/` link, so a backend pointer at an unbuilt
  /// screen (e.g. `/hr/feeds/...`) dead-ended on the router error page.
  static const List<String> _navigablePrefixes = [
    AppRoutes.hrHome,
    AppRoutes.hrEmployees,
    AppRoutes.hrTemplates,
    AppRoutes.hrAssign,
    AppRoutes.hrReviews,
    AppRoutes.hrReports,
    AppRoutes.hrLocations,
    AppRoutes.hrBulkSetup,
    AppRoutes.hrAuditLog,
    AppRoutes.employeeHome,
    AppRoutes.employeeSelfRate,
    AppRoutes.employeeHistory,
    AppRoutes.employeeProfile,
  ];

  bool _isNavigableDeepLink(String link) {
    final path = link.split('?').first;
    return _navigablePrefixes.any((p) => path == p || path.startsWith('$p/'));
  }

  void _openActionItem(BuildContext context, HrActionItem item) {
    final link = item.deepLink ?? '';
    if (_isNavigableDeepLink(link)) {
      context.go(link);
      return;
    }
    final fallback = routeForActionKey(item.key);
    if (fallback != null) {
      context.go(fallback);
      return;
    }
    // Truly unmapped — log so we can grow `_routeForKey` next time, and
    // surface a snackbar so the tap isn't perceived as a frozen UI.
    assert(() {
      debugPrint(
        'hr action-item: unmapped key="${item.key}" '
        'deepLink="${item.deepLink}" headline="${item.headline}"',
      );
      return true;
    }());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'No screen for this action yet — ${item.headline}',
        ),
      ),
    );
  }
}

/// Maps a dashboard action-item `key` to the best-fit registered HR route.
///
/// Top-level (rather than a private method on the widget) so the mapping
/// can be unit-tested directly — see `hr_action_item_routing_test.dart`.
///
/// Backend ships SCREAMING_SNAKE and snake_case interchangeably — the live
/// `/hr/dashboard/action-items` response uses `hr_feed_missing` /
/// `draft_stuck`, while older payloads used `PENDING_REVIEWS`. We
/// normalise to UPPER then match.
String? routeForActionKey(String key) {
  switch (key.toUpperCase()) {
    // Cycle-scoped work (feeds, stuck reviews, scoring overdue, etc.)
    // all lands on the cycles list — the umbrella entry-point for any
    // mid-cycle remediation. There's no per-state review filter screen
    // yet; cycles is the deepest existing surface.
    case 'PENDING_REVIEWS':
    case 'OVERDUE_REVIEWS':
    case 'UNFINALIZED_REVIEWS':
    case 'DRAFT_STUCK':
    case 'HR_FEED_MISSING':
    case 'MANAGER_REVIEW_OVERDUE':
    case 'OPS_SCORING_OVERDUE':
    case 'FINANCE_SCORING_OVERDUE':
    case 'FINALIZATION_OVERDUE':
    case 'MISSING_BONUS_SLABS':
      return AppRoutes.hrReviews;
    case 'UNASSIGNED_EMPLOYEES':
    case 'INACTIVE_EMPLOYEES':
      return AppRoutes.hrEmployees;
    case 'MISSING_KRA_TEMPLATES':
      return AppRoutes.hrTemplates;
    case 'AUDIT_REVIEW_REQUIRED':
      return AppRoutes.hrAuditLog;
    default:
      return null;
  }
}

// ── Pipeline ──

class _PipelineSection extends ConsumerWidget {
  final String cycleId;
  const _PipelineSection({required this.cycleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pipelineAsync = ref.watch(hrPipelineProvider(cycleId));

    return pipelineAsync.when(
      loading: () => const ShimmerBox(height: 120, borderRadius: 14),
      error: (e, _) => _ErrorPanel(
        message: e.toString(),
        onRetry: () => ref.invalidate(hrPipelineProvider(cycleId)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const Text('No pipeline data.',
              style: TextStyle(color: AppColors.textMuted));
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: items.map((p) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        p.displayLabel,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        p.count.toString(),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (p.stuck > 0)
                      Expanded(
                        flex: 1,
                        child: Text(
                          '${p.stuck} stuck',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.error,
                          ),
                        ),
                      )
                    else
                      const Spacer(flex: 1),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Recent Activity
// ─────────────────────────────────────────────────────────────────────

class _RecentActivitySection extends ConsumerWidget {
  const _RecentActivitySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync = ref.watch(hrRecentActivityProvider);

    return activityAsync.when(
      loading: () => Column(
        children: List.generate(
          3,
          (i) => const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: ShimmerBox(height: 60, borderRadius: 14),
          ),
        ),
      ),
      error: (e, _) => _ErrorPanel(
        message: e.toString(),
        onRetry: () => ref.invalidate(hrRecentActivityProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.notifications_none_rounded,
            title: AppStrings.hrHomeNoActivity,
            message: 'Activity will appear here as your team uses the app.',
            compact: true,
          );
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                // We use a simplified ListTile here instead of ActivityFeedItem
                // because ActivityFeedItem was designed for a different model.
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor:
                        AppColors.primaryPurple.withValues(alpha: 0.1),
                    child: const Icon(Icons.history_rounded,
                        color: AppColors.primaryPurple, size: 20),
                  ),
                  title: Text(
                    items[i].actionLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    '${items[i].user?.name ?? 'System'} • ${HrFormatters.relativeTime(items[i].createdAt)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                if (i != items.length - 1)
                  Divider(
                    height: 1,
                    color: AppColors.divider.withValues(alpha: 0.6),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 3.4,
      children: [
        QuickActionButton(
          icon: Icons.person_add_alt_1_rounded,
          label: AppStrings.hrHomeQuickAddEmployee,
          iconBg: AppColors.primaryPurple.withValues(alpha: 0.10),
          iconFg: AppColors.primaryPurple,
          onTap: () => context.push(AppRoutes.hrEmployeeNew),
        ),
        QuickActionButton(
          icon: Icons.description_rounded,
          label: AppStrings.hrHomeQuickCreateTemplate,
          iconBg: AppColors.accentOrange.withValues(alpha: 0.12),
          iconFg: AppColors.accentOrange,
          onTap: () => context.push(AppRoutes.hrTemplateNew),
        ),
        QuickActionButton(
          icon: Icons.assignment_turned_in_rounded,
          label: AppStrings.hrHomeQuickAssignKra,
          iconBg: AppColors.accentYellow.withValues(alpha: 0.20),
          iconFg: AppColors.accentYellow,
          onTap: () => context.push(AppRoutes.hrAssign),
        ),
        QuickActionButton(
          icon: Icons.event_available_rounded,
          label: AppStrings.hrHomeQuickReviews,
          iconBg: AppColors.success.withValues(alpha: 0.12),
          iconFg: AppColors.success,
          onTap: () => context.push(AppRoutes.hrReviews),
        ),
      ],
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorPanel({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.error, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Could not load data',
                style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.error,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
