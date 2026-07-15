import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/router/app_router.dart';
import '../../../../../core/widgets/shimmer_skeletons.dart';
import '../../../../../core/widgets/workspace_drawer.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';
import '../../../../hr/presentation/widgets/confirm_action_dialog.dart';
import '../../../data/models/employee_profile.dart';
import '../../providers/my_profile_providers.dart';
import '../../widgets/_formatters.dart';
import 'widgets/my_manager_card.dart';
import 'widgets/profile_field_row.dart';
import 'widgets/profile_header.dart';

/// Read-only profile screen with three sections (contact / reporting /
/// defaults). Edit affordance only on phone — the rest is HR-managed.
class MyProfileScreen extends ConsumerWidget {
  const MyProfileScreen({super.key});

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
    final async = ref.watch(myProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: workspaceDrawerFor(ref),
      appBar: AppBar(
        title: const Text(
          AppStrings.profileTitle,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          async.maybeWhen(
            data: (_) => IconButton(
              icon: const Icon(Icons.edit_rounded),
              tooltip: AppStrings.commonEdit,
              onPressed: () => context.go(AppRoutes.employeeProfileEdit),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primaryPurple,
          onRefresh: () async {
            ref.invalidate(myProfileProvider);
            try {
              await ref.read(myProfileProvider.future);
            } catch (_) {
              // Surface via the error branch.
            }
          },
          child: async.when(
            loading: () => const _ProfileLoading(),
            error: (e, _) => _ProfileError(
              message: e.toString(),
              onRetry: () => ref.invalidate(myProfileProvider),
            ),
            data: (profile) => _ProfileBody(
              profile: profile,
              onLogout: () => _confirmLogout(context, ref),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Body
// ─────────────────────────────────────────────────────────────────────

class _ProfileBody extends StatelessWidget {
  final EmployeeProfile profile;
  final VoidCallback onLogout;
  const _ProfileBody({required this.profile, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        ProfileHeader(profile: profile),

        // ── Contact section ──
        _Section(
          label: AppStrings.profileSectionContact,
          children: [
            ProfileFieldRow(
              label: AppStrings.profileFieldEmail,
              value: profile.email,
              icon: Icons.mail_outline_rounded,
            ),
            ProfileFieldRow(
              label: AppStrings.profileFieldPhone,
              value: profile.phone,
              icon: Icons.phone_outlined,
            ),
            ProfileFieldRow(
              label: AppStrings.profileFieldGrade,
              value: profile.grade,
              icon: Icons.grade_outlined,
              isLast: true,
            ),
          ],
        ),

        // ── Reporting section ──
        _Section(
          label: AppStrings.profileSectionReporting,
          children: [
            if (profile.manager != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                child: MyManagerCard(
                  manager: profile.manager!,
                  onTap: () =>
                      context.go(AppRoutes.employeeReportingTree),
                ),
              )
            else
              const ProfileFieldRow(
                label: AppStrings.profileFieldManager,
                value: null,
                icon: Icons.person_outline_rounded,
              ),
            ProfileFieldRow(
              label: AppStrings.profileFieldLocation,
              value: profile.projectLocation?.displayLabel,
              icon: Icons.business_outlined,
            ),
            ProfileFieldRow(
              label: AppStrings.profileFieldDepartment,
              value: profile.department,
              icon: Icons.apartment_outlined,
              isLast: true,
            ),
          ],
        ),

        // ── Defaults section ──
        _Section(
          label: AppStrings.profileSectionDefaults,
          children: [
            ProfileFieldRow(
              label: AppStrings.profileFieldDefaultTemplate,
              value: profile.defaultTemplate?.name,
              icon: Icons.assignment_outlined,
            ),
            ProfileFieldRow(
              label: AppStrings.profileFieldMonthlyIncentive,
              value: profile.monthlyIncentiveAmount == null
                  ? null
                  : EmployeeFormatters.currencyInr(
                      profile.monthlyIncentiveAmount!),
              icon: Icons.payments_outlined,
              isLast: true,
            ),
          ],
        ),

        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded),
            label: const Text(
              AppStrings.profileLogout,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: BorderSide(
                color: AppColors.error.withValues(alpha: 0.4),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  final List<Widget> children;
  const _Section({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
                letterSpacing: 0.7,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(children: children),
          ),
        ],
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
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      children: [
        const Icon(
          Icons.error_outline_rounded,
          size: 48,
          color: AppColors.error,
        ),
        const SizedBox(height: 14),
        const Text(
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
          style: const TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 22),
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
