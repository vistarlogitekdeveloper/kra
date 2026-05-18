import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../../../../core/router/app_router.dart';
import '../../../../../auth/presentation/providers/auth_providers.dart';
import '../../../../../employee/presentation/screens/profile/widgets/profile_header.dart';
import '../../../../../employee/presentation/screens/profile/widgets/profile_field_row.dart';
import '../../../../../hr/presentation/widgets/confirm_action_dialog.dart';
import '../../../../data/models/enums.dart';
import '../../../providers/manager_mode_provider.dart';

/// Manager-shell Profile tab. Lighter than the employee profile —
/// the manager-mode user is the same person who owns the employee
/// /employee/profile route, so we just surface the logged-in
/// identity, a manager-mode toggle, and the logout affordance.
///
/// Tapping "Switch to My Review" flips the mode and re-routes the
/// shell to /manager/my-review/home (handled by the parent shell's
/// IndexedStack). Tapping "View as Employee" deep-links to the
/// dedicated /employee surface for full profile editing.
class ManagerProfileScreen extends ConsumerWidget {
  const ManagerProfileScreen({super.key});

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
    final authState = ref.watch(authStateProvider);
    final user =
        authState is AuthAuthenticated ? authState.user : null;
    final mode = ref.watch(managerModeProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          AppStrings.managerProfileTitle,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            if (user != null)
              _IdentityHeader(name: user.fullName, role: user.role.displayName),
            const SizedBox(height: 16),
            _ModeSection(
              currentMode: mode,
              onPickMode: (m) =>
                  ref.read(managerModeProvider.notifier).setMode(m),
            ),
            const SizedBox(height: 16),
            _LinksSection(),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: OutlinedButton.icon(
                onPressed: () => _confirmLogout(context, ref),
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
        ),
      ),
    );
  }
}

class _IdentityHeader extends StatelessWidget {
  final String name;
  final String role;
  const _IdentityHeader({required this.name, required this.role});

  String _initials() {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '·';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final swatch = ProfileHeader.colourFor(name);
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
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: swatch.withValues(alpha: 0.15),
              border: Border.all(
                color: swatch.withValues(alpha: 0.4),
                width: 1.8,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: swatch,
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
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryPurple.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    role.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryPurple,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSection extends StatelessWidget {
  final ManagerMode currentMode;
  final ValueChanged<ManagerMode> onPickMode;
  const _ModeSection({
    required this.currentMode,
    required this.onPickMode,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            AppStrings.managerProfileModeSectionLabel,
            style: TextStyle(
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
              _ModeTile(
                icon: Icons.groups_rounded,
                label: AppStrings.managerProfileModeMyTeam,
                isActive: currentMode == ManagerMode.myTeam,
                onTap: () => onPickMode(ManagerMode.myTeam),
              ),
              const Divider(
                color: AppColors.divider,
                height: 1,
                indent: 16,
                endIndent: 16,
              ),
              _ModeTile(
                icon: Icons.person_rounded,
                label: AppStrings.managerProfileModeMyReview,
                isActive: currentMode == ManagerMode.myReview,
                onTap: () => onPickMode(ManagerMode.myReview),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  const _ModeTile({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isActive
                    ? AppColors.primaryPurple
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isActive
                        ? AppColors.primaryPurple
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              if (isActive)
                const Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: AppColors.primaryPurple,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinksSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () =>
                  context.go(AppRoutes.employeeProfile),
              child: const ProfileFieldRow(
                label: 'View as Employee',
                value: 'Open the employee profile (self-rate / history)',
                icon: Icons.open_in_new_rounded,
                isLast: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
