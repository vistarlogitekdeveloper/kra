import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../../../../core/router/app_router.dart';
import '../../../../../../core/widgets/paged_list_view.dart';
import '../../../../../../core/widgets/shimmer_skeletons.dart';
import '../../../../../employee/presentation/widgets/_formatters.dart';
import '../../../../../employee/presentation/widgets/score_pill.dart';
import '../../../../data/models/team_member_profile.dart';
import '../../../providers/manager_team_providers.dart';
import '../../../providers/team_history_providers.dart';
import '../history/widgets/history_review_tile.dart';

/// Three-tab employee profile for managers. Tabs: Profile | Current
/// Review | History.
///
/// The "Current Review" tab is intentionally a thin redirect rather
/// than embedded — the review detail is complex enough that nesting
/// it inside the profile screen's tab body would make the route
/// graph confusing. Tap the tab → push the review-detail route.
class TeamMemberProfileScreen extends ConsumerStatefulWidget {
  final String employeeId;
  const TeamMemberProfileScreen({super.key, required this.employeeId});

  @override
  ConsumerState<TeamMemberProfileScreen> createState() =>
      _TeamMemberProfileScreenState();
}

class _TeamMemberProfileScreenState
    extends ConsumerState<TeamMemberProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(teamHistoryFilterProvider.notifier)
          .setEmployee(widget.employeeId);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(
        managerTeamMemberProfileProvider(widget.employeeId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          AppStrings.managerProfileTabProfile,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go(AppRoutes.managerTeamList),
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primaryPurple,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primaryPurple,
          indicatorWeight: 2.4,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            letterSpacing: 0.3,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          tabs: const [
            Tab(text: AppStrings.managerProfileTabProfile),
            Tab(text: AppStrings.managerProfileTabCurrent),
            Tab(text: AppStrings.managerProfileTabHistory),
          ],
        ),
      ),
      body: async.when(
        loading: () => const _ProfileLoading(),
        error: (e, _) => _ProfileError(
          message: e.toString(),
          onRetry: () => ref.invalidate(
              managerTeamMemberProfileProvider(widget.employeeId)),
        ),
        data: (profile) => TabBarView(
          controller: _tabs,
          children: [
            _ProfileTab(profile: profile),
            _CurrentReviewTab(profile: profile),
            _HistoryTab(employeeId: profile.employeeId),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Profile tab
// ─────────────────────────────────────────────────────────────────────

class _ProfileTab extends StatelessWidget {
  final TeamMemberProfile profile;
  const _ProfileTab({required this.profile});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _Header(profile: profile),
        const SizedBox(height: 16),
        if (profile.fyReviewSummary != null) ...[
          _FySummaryCard(profile: profile),
          const SizedBox(height: 16),
        ],
        _Section(
          title: 'Contact',
          rows: [
            _FieldRow(label: 'Email', value: profile.email),
            _FieldRow(label: 'Phone', value: profile.phone),
          ],
        ),
        const SizedBox(height: 14),
        _Section(
          title: 'Organisation',
          rows: [
            _FieldRow(label: 'Department', value: profile.department),
            _FieldRow(label: 'Grade', value: profile.grade),
            _FieldRow(label: 'Position', value: profile.position),
            _FieldRow(
                label: 'Project location',
                value: profile.projectLocation),
          ],
        ),
        const SizedBox(height: 14),
        _Section(
          title: 'Other',
          rows: [
            _FieldRow(
              label: 'Joined',
              value: profile.joinedDate == null
                  ? null
                  : EmployeeFormatters.date(profile.joinedDate!),
            ),
            _FieldRow(
              label: 'Monthly incentive',
              value: profile.monthlyIncentiveAmount == null
                  ? null
                  : EmployeeFormatters.currencyInr(
                      profile.monthlyIncentiveAmount!),
            ),
          ],
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final TeamMemberProfile profile;
  const _Header({required this.profile});

  String _initials() {
    final parts = profile.fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '·';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primaryPurple.withValues(alpha: 0.14),
              border: Border.all(
                color:
                    AppColors.primaryPurple.withValues(alpha: 0.40),
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryPurple,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  profile.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    _RolePill(role: profile.role),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        profile.employeeCode,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RolePill extends StatelessWidget {
  final String? role;
  const _RolePill({required this.role});

  @override
  Widget build(BuildContext context) {
    final label = (role ?? 'EMPLOYEE').replaceAll('_', ' ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primaryPurple.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: AppColors.primaryPurple,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _FySummaryCard extends StatelessWidget {
  final TeamMemberProfile profile;
  const _FySummaryCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final fy = profile.fyReviewSummary!;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            AppStrings.managerProfileFySummary,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _FyBlock(
                  label: AppStrings.managerProfileFyTotalReviews,
                  value: fy.totalReviews.toString(),
                ),
              ),
              Expanded(
                child: _FyBlock(
                  label: AppStrings.managerProfileFyFinalized,
                  value: fy.finalizedCount.toString(),
                  accent: AppColors.success,
                ),
              ),
              Expanded(
                child: _FyBlock(
                  label: AppStrings.managerProfileFyPending,
                  value: fy.pendingCount.toString(),
                  accent: AppColors.accentOrange,
                ),
              ),
            ],
          ),
          if (fy.averageFinalScore != null) ...[
            const Divider(color: AppColors.divider, height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    AppStrings.managerProfileFyAverage,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                ScorePill(
                  score: fy.averageFinalScore,
                  maxScore: null,
                  asPercentage: true,
                  tone: ScorePillTone.finalised,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FyBlock extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  const _FyBlock({
    required this.label,
    required this.value,
    this.accent = AppColors.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            color: AppColors.textSecondary,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: accent,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> rows;
  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: [
              for (int i = 0; i < rows.length; i++) ...[
                rows[i],
                if (i != rows.length - 1)
                  const Divider(
                    color: AppColors.divider,
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FieldRow extends StatelessWidget {
  final String label;
  final String? value;
  const _FieldRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            child: Text(
              (value == null || value!.isEmpty) ? '—' : value!,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: (value == null || value!.isEmpty)
                    ? AppColors.textMuted
                    : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Current Review tab
// ─────────────────────────────────────────────────────────────────────

class _CurrentReviewTab extends StatelessWidget {
  final TeamMemberProfile profile;
  const _CurrentReviewTab({required this.profile});

  @override
  Widget build(BuildContext context) {
    final reviewId = profile.currentReviewId;
    if (reviewId == null || reviewId.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              AppStrings.managerProfileNoCurrentReview,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
        ),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.fact_check_rounded,
                color: AppColors.primaryPurple,
                size: 48,
              ),
              const SizedBox(height: 14),
              const Text(
                'Open this employee\'s current quarterly review',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () =>
                    context.go(AppRoutes.managerReviewDetail(reviewId)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text(
                  'Open review',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// History tab — embedded paginated list (no AppBar)
// ─────────────────────────────────────────────────────────────────────

class _HistoryTab extends ConsumerWidget {
  final String employeeId;
  const _HistoryTab({required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(teamHistoryListProvider);
    return PagedListView(
      items: list.reviews,
      isInitialLoading: list.isInitialLoading,
      isLoadingMore: list.isLoadingMore,
      hasMore: list.hasMore,
      initialError: list.error,
      onLoadMore: () =>
          ref.read(teamHistoryListProvider.notifier).loadMore(),
      onRefresh: () async =>
          ref.read(teamHistoryListProvider.notifier).refresh(),
      emptyBuilder: (_) => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            AppStrings.managerHistoryEmptyMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemBuilder: (_, __, review) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: HistoryReviewTile(
          review: review,
          onTap: () =>
              context.go(AppRoutes.managerReviewDetail(review.reviewId)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Loading + error
// ─────────────────────────────────────────────────────────────────────

class _ProfileLoading extends StatelessWidget {
  const _ProfileLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        ProfileHeaderSkeleton(),
        SizedBox(height: 14),
        DashboardCardSkeleton(),
        SizedBox(height: 12),
        DashboardCardSkeleton(),
      ],
    );
  }
}

class _ProfileError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ProfileError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 44,
              color: AppColors.error,
            ),
            const SizedBox(height: 12),
            const Text(
              AppStrings.errorGeneric,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(AppStrings.commonRetry),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryPurple,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
