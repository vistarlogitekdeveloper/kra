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
// Overview Section (Greeting + Stats)
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
            _GreetingCard(name: fullName),
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
  const _GreetingCard({required this.name});

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

/// Maps a dashboard action-item `key` to the best-fit registered HR route.
///
/// Top-level (rather than a private method on the widget) so the mapping
/// can be unit-tested directly — see `hr_action_item_routing_test.dart`.
/// Retained for the audit-log / action routing helpers even though the
/// dashboard's cycle-scoped action-items panel has been removed.
///
/// Backend ships SCREAMING_SNAKE and snake_case interchangeably — the live
/// `/hr/dashboard/action-items` response uses `hr_feed_missing` /
/// `draft_stuck`, while older payloads used `PENDING_REVIEWS`. We
/// normalise to UPPER then match.
String? routeForActionKey(String key) {
  switch (key.toUpperCase()) {
    // Review-remediation work (feeds, stuck reviews, scoring overdue, etc.)
    // all lands on the reviews surface — the umbrella entry-point for any
    // mid-review remediation.
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
