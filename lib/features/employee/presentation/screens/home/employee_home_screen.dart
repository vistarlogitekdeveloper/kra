import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/router/app_router.dart';
import '../../../../../core/widgets/shimmer_skeletons.dart';
import '../../../../../core/widgets/workspace_drawer.dart';
import '../../../../../core/widgets/workspace_switcher.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';
import '../../../../hr/presentation/widgets/confirm_action_dialog.dart';
import '../../../../reviews/data/models/monthly_review.dart';
import '../../../../reviews/presentation/providers/monthly_review_providers.dart';
import '../../../data/models/employee_dashboard.dart';
import '../../../data/models/enums.dart';
import '../../providers/employee_dashboard_providers.dart';
import '../../providers/my_profile_providers.dart';
import '../../widgets/empty_my_dashboard.dart';
import 'widgets/current_month_card.dart';
import 'widgets/deadline_banner.dart';
import 'widgets/greeting_header.dart';
import 'widgets/history_strip.dart';
import 'widgets/incentive_snapshot_card.dart';
import 'widgets/my_kras_summary_card.dart';

/// The employee's personal home screen — six stacked sections, each
/// with its own loading / error story so a single slow query doesn't
/// blank out the whole tab.
///
/// User identity (name, employee code, role) comes from the auth
/// provider — the dashboard endpoint doesn't carry a `user` block on
/// the new contract, and refetching what's already in memory would
/// just be wasteful.
///
/// Composition: the dashboard-driven sections (deadline banner, current
/// month card, incentive snapshot) each watch
/// [employeeDashboardProvider] and render their own loading skeleton
/// independently. The KRA summary and history strip already own their
/// own providers, so they continue to render in parallel even while
/// the dashboard call is in flight.
class EmployeeHomeScreen extends ConsumerWidget {
  const EmployeeHomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(employeeDashboardProvider);
    try {
      await ref.read(employeeDashboardProvider.future);
    } catch (_) {
      // Each section surfaces its own error via the listenable.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final user = authState is AuthAuthenticated ? authState.user : null;
    final fullName = user?.fullName ?? 'there';
    // Auth's User model doesn't carry employeeCode (the dashboard
    // contract dropped its `user` block, and /auth/me doesn't expose
    // the code either). Pull it from the profile provider when
    // available; fall back to empty so the greeting renders cleanly
    // during the first-paint window before the profile call lands.
    final employeeCode = ref.watch(
      myProfileProvider.select(
        (a) => a.maybeWhen(
          data: (p) => p.employeeCode,
          orElse: () => '',
        ),
      ),
    );
    final roleLabel = user?.role.displayName ?? '';

    // Empty self-view is a normal state, not an error: when the signed-in
    // user has no active cycle (`/employee/dashboard` returns 200 with a null
    // cycle), show a clear "No active KRA yet" empty state instead of the
    // populated sections. Only a SUCCESSFUL null-cycle payload triggers this —
    // loading still shows shimmers and a real network error still shows the
    // per-section retry card (see the sections below).
    final showEmptyKra = ref.watch(
      employeeDashboardProvider.select(
        (a) => a.maybeWhen(
          data: (d) => !d.hasActiveCycle,
          orElse: () => false,
        ),
      ),
    );

    // The "☰" workspace switcher is HR-admin only. HR admins genuinely span
    // every area (My KRA / My Team / HR Admin), so they need a picker. Everyone
    // else has at most one place to go back to, which the back button already
    // handles (a manager's back returns them to My Team) — a menu there was
    // just a second, redundant way to do the same thing.
    final hasWorkspaceMenu = user != null && AppRoutes.canAccessHr(user.role);
    final header = GreetingHeader(
      name: _firstName(fullName),
      employeeCode: employeeCode,
      roleLabel: roleLabel,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _HomeBackButton(),
          if (hasWorkspaceMenu) const _WorkspaceMenuButton(),
        ],
      ),
      trailing: const _HomeLogoutButton(),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: workspaceDrawerFor(ref),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primaryPurple,
          onRefresh: () => _refresh(ref),
          child: showEmptyKra
              ? _EmptyKraBody(header: header, onRetry: () => _refresh(ref))
              : ListView(
                  // Always-scrollable so RefreshIndicator works even when the
                  // body would otherwise be too short to overscroll.
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    header,
                    const _DeadlineBannerSection(),
                    const _CurrentMonthSection(),
                    const _MyKrasSection(),
                    const _HistoryStripSection(),
                    const _IncentiveSection(),
                  ],
                ),
        ),
      ),
    );
  }

  String _firstName(String fullName) {
    if (fullName.trim().isEmpty) return 'there';
    return fullName.trim().split(' ').first;
  }
}

/// The "☰" workspace-menu button in the greeting header. The home screen has
/// no AppBar, so it opens the Scaffold's drawer manually. The [Builder] gives
/// a context beneath the home Scaffold so `Scaffold.of` finds the drawer.
/// Only rendered for roles with more than one workspace.
class _WorkspaceMenuButton extends StatelessWidget {
  const _WorkspaceMenuButton();

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (ctx) => IconButton(
        icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
        tooltip: AppStrings.workspaceSwitchTooltip,
        visualDensity: VisualDensity.compact,
        onPressed: () => Scaffold.of(ctx).openDrawer(),
      ),
    );
  }
}

/// Top-left back button on the home hero.
///
/// Home (My KRA) is a bottom-nav root, so "back" only means something when
/// there's actually somewhere to return to:
///   * drilled in from another route → pop it;
///   * a manager/HR who switched into My KRA → return to their own workspace
///     (My Team / HR Admin);
///   * a plain employee, whose only workspace IS My KRA → nothing to go back
///     to, so no dead button is rendered.
class _HomeBackButton extends ConsumerWidget {
  const _HomeBackButton();

  Widget _btn({required String tooltip, required VoidCallback onTap}) =>
      IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (context.canPop()) {
      return _btn(tooltip: AppStrings.commonBack, onTap: () => context.pop());
    }
    final authState = ref.watch(authStateProvider);
    final user = authState is AuthAuthenticated ? authState.user : null;
    if (user == null) return const SizedBox.shrink();
    // Everything past index 0 is a workspace beyond My KRA; the last one is the
    // user's most specific area (HR Admin for admins, My Team for managers).
    final extras = WorkspaceSwitcher.workspacesFor(user).skip(1).toList();
    if (extras.isEmpty) return const SizedBox.shrink();
    final target = extras.last;
    return _btn(
      tooltip: '${AppStrings.commonBack} · ${target.label}',
      onTap: () => context.go(target.route),
    );
  }
}

/// Top-right "log out" button on the home hero. White to read on the purple
/// gradient; confirms before ending the session.
class _HomeLogoutButton extends ConsumerWidget {
  const _HomeLogoutButton();

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
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
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.logout_rounded, color: Colors.white),
      tooltip: AppStrings.dashboardLogoutTooltip,
      visualDensity: VisualDensity.compact,
      onPressed: () => _confirmLogout(context, ref),
    );
  }
}

/// Full-height, pull-to-refreshable body shown when the user has no active
/// KRA. Keeps the greeting header on top and centres [EmptyMyDashboard] in
/// the remaining space.
class _EmptyKraBody extends StatelessWidget {
  final Widget header;
  final VoidCallback onRetry;
  const _EmptyKraBody({required this.header, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    // ConstrainedBox(minHeight) + IntrinsicHeight is the scroll-safe idiom for
    // "header on top, empty state centred in the space below": on a tall
    // viewport the Expanded fills and centres; on a short one (landscape /
    // split-screen) the content keeps its intrinsic height and the whole body
    // scrolls instead of overflowing. A fixed SizedBox(height: maxHeight)
    // would clamp and overflow the empty card on short viewports.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Column(
              children: [
                header,
                Expanded(
                  child: EmptyMyDashboard(
                    title: AppStrings.myKraEmptyTitle,
                    message: AppStrings.myKraEmptyMessage,
                    onRetry: onRetry,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Section 1: Deadline banner (dashboard-driven, conditional)
// ─────────────────────────────────────────────────────────────────────

class _DeadlineBannerSection extends ConsumerWidget {
  static const int _bannerThresholdDays = 3;

  const _DeadlineBannerSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(employeeDashboardProvider);
    return dashboardAsync.maybeWhen(
      data: (dashboard) {
        // Don't nag once the employee has already submitted everything for
        // the cycle — the monthly deadline only matters while work is open.
        // Same legacy-vs-monthly mismatch as the current-month card: without
        // the monthly cross-check this nags "Self-rating overdue — submit now"
        // at someone who has already rated every KRA.
        final selfDone = ref
                .watch(myMonthlyReviewProvider(
                    _CurrentMonthSection._periodFor(dashboard)))
                .maybeWhen(data: (r) => r?.selfRatingSubmitted, orElse: () => null) ??
            false;
        final submittedAll =
            selfDone || (dashboard.scorecard?.state.hasSubmittedAll ?? false);
        final days = dashboard.selfRatingDaysRemaining;
        final showBanner = !submittedAll &&
            days != null &&
            (dashboard.isSelfRatingOverdue || days <= _bannerThresholdDays);
        if (!showBanner) return const SizedBox.shrink();
        return DeadlineBanner(
          daysRemaining: days,
          isOverdue: dashboard.isSelfRatingOverdue,
          onTap: () => context.go(AppRoutes.employeeSelfRate),
        );
      },
      // Loading / error states for the banner don't add value — the
      // banner is conditional anyway, so an absence is the same UX as
      // a shimmer. Keep it quiet.
      orElse: () => const SizedBox.shrink(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Section 2: Current month card (dashboard-driven, always rendered)
// ─────────────────────────────────────────────────────────────────────

class _CurrentMonthSection extends ConsumerWidget {
  const _CurrentMonthSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(employeeDashboardProvider);
    return dashboardAsync.when(
      loading: () => const _SectionLoading(),
      error: (e, _) => _SectionError(
        message: e.toString(),
        onRetry: () => ref.invalidate(employeeDashboardProvider),
      ),
      data: (dashboard) {
        // `/employee/dashboard` derives its state from the LEGACY kra.reviews
        // table, which a monthly self-rating never updates — so a fully-rated
        // month still reports DRAFT and the card reads "Self-rating pending".
        // Cross-check against the monthly review the KRA sheet actually writes
        // to, and promote the state when the self-rating really is in.
        final period = _periodFor(dashboard);
        final selfDone = ref
                .watch(myMonthlyReviewProvider(period))
                .maybeWhen(data: (r) => r?.selfRatingSubmitted, orElse: () => null) ??
            false;
        final legacyState = dashboard.scorecard?.state ?? ReviewState.draft;
        final promote = selfDone && !legacyState.hasSubmittedAll;
        return CurrentMonthCard(
          cycle: dashboard.cycle,
          currentMonth: dashboard.currentMonth,
          scorecard: dashboard.scorecard,
          stateOverride: promote ? ReviewState.employeeSubmittedAll : null,
          onPrimaryAction: () => _onCurrentMonthAction(context, dashboard),
        );
      },
    );
  }

  /// The month this dashboard is showing, as a [ReviewPeriod].
  static ReviewPeriod _periodFor(EmployeeDashboard dashboard) {
    final d = dashboard.currentMonth?.monthDate ?? DateTime.now();
    return ReviewPeriod(d.year, d.month);
  }

  /// Routes the current-month CTA to whichever screen makes sense for
  /// the active state.
  void _onCurrentMonthAction(
      BuildContext context, EmployeeDashboard dashboard) {
    final scorecard = dashboard.scorecard;
    if (scorecard == null) {
      context.go(AppRoutes.employeeSelfRate);
      return;
    }
    if (!scorecard.state.hasSubmittedAll) {
      context.go(AppRoutes.employeeSelfRate);
      return;
    }
    if (scorecard.reviewId.isEmpty) {
      context.go(AppRoutes.employeeHistory);
      return;
    }
    context.go(AppRoutes.employeeReviewDetail(scorecard.reviewId));
  }
}

// ─────────────────────────────────────────────────────────────────────
// Section 3: My KRAs (independent provider — renders without dashboard)
// ─────────────────────────────────────────────────────────────────────

class _MyKrasSection extends ConsumerWidget {
  const _MyKrasSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Pull the cycle id from the dashboard payload when it lands —
    // otherwise pass `null` and let MyKrasSummaryCard fall back to a
    // shimmer. The KRA list does its own loading state once it has an id.
    final cycleId = ref.watch(
      employeeDashboardProvider.select(
        (a) => a.maybeWhen(data: (d) => d.cycle?.id, orElse: () => null),
      ),
    );
    return MyKrasSummaryCard(cycleId: cycleId);
  }
}

// ─────────────────────────────────────────────────────────────────────
// Section 4: History strip (independent provider)
// ─────────────────────────────────────────────────────────────────────

class _HistoryStripSection extends ConsumerWidget {
  const _HistoryStripSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return HistoryStrip(
      onTapReview: (id) => context.go(AppRoutes.employeeReviewDetail(id)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Section 5: Incentive snapshot (dashboard-driven, conditional)
// ─────────────────────────────────────────────────────────────────────

class _IncentiveSection extends ConsumerWidget {
  const _IncentiveSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(employeeDashboardProvider);
    return dashboardAsync.when(
      loading: () => const _SectionLoading(),
      // The incentive section's failure is non-fatal — silently hide
      // rather than block the rest of the home screen.
      error: (_, __) => const SizedBox.shrink(),
      data: (dashboard) {
        if (dashboard.incentive == null) return const SizedBox.shrink();
        return IncentiveSnapshotCard(
          incentive: dashboard.incentive!,
          onTap: () => context.go(AppRoutes.employeeHistory),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Shared per-section placeholders
// ─────────────────────────────────────────────────────────────────────

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: DashboardCardSkeleton(),
    );
  }
}

class _SectionError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _SectionError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.error,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    AppStrings.errorGeneric,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: const Text(
                AppStrings.commonRetry,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
