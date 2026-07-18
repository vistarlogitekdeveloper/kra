import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../../../../core/router/app_router.dart';
import '../../../../../../core/widgets/adaptive_leading.dart';
import '../../../../../../core/widgets/workspace_drawer.dart';
import '../../../../../auth/presentation/providers/auth_providers.dart';
import '../../../../../employee/presentation/screens/profile/widgets/profile_header.dart';
import '../../../../../employee/presentation/screens/profile/widgets/profile_field_row.dart';
import '../../../../../hr/presentation/widgets/confirm_action_dialog.dart';

/// Manager-shell Profile tab. Lighter than the employee profile —
/// the manager-mode user is the same person who owns the employee
/// /employee/profile route, so we just surface the logged-in
/// identity, a "View as Employee" deep link into /employee/* for
/// self-rate, and the logout affordance.
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

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: workspaceDrawerFor(ref),
      appBar: AppBar(
        leading: adaptiveLeading(context),
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
              onTap: () => context.go(AppRoutes.employeeHome),
              child: const ProfileFieldRow(
                label: AppStrings.workspaceMyKra,
                value: AppStrings.workspaceMyKraSubtitle,
                icon: Icons.assignment_ind_rounded,
                isLast: false,
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.go(AppRoutes.employeeProfile),
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
