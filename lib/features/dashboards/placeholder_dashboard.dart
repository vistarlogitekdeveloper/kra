import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/widgets/connectivity_wrapper.dart';
import '../auth/data/models/user.dart';
import '../auth/presentation/providers/auth_providers.dart';

/// Single placeholder used by all 6 role dashboards while the real
/// screens are built out in future steps. Confirms that:
///   - login → role-aware redirect works
///   - logout clears state and routes back to /login
///   - the offline banner overlays the screen correctly
class PlaceholderDashboard extends ConsumerWidget {
  final UserRole role;

  const PlaceholderDashboard({super.key, required this.role});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authStateProvider);
    final user = state is AuthAuthenticated ? state.user : null;

    return ConnectivityWrapper(
      child: Scaffold(
        appBar: AppBar(
          title: Text('${role.displayName} ${AppStrings.dashboardTitleSuffix}'),
          backgroundColor: AppColors.primaryPurple,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              onPressed: () =>
                  ref.read(authStateProvider.notifier).logout(),
              tooltip: AppStrings.dashboardLogoutTooltip,
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryPurple.withValues(alpha: 0.08),
                  ),
                  child: Icon(
                    _iconForRole(role),
                    size: 56,
                    color: AppColors.primaryPurple,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '${AppStrings.dashboardGreeting} ${user?.fullName ?? 'there'}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${AppStrings.dashboardLoggedInAs} ${role.displayName}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 28),
                if (user != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      children: [
                        _InfoRow(label: 'Email', value: user.email),
                        const SizedBox(height: 8),
                        _InfoRow(label: 'Role', value: user.role.displayName),
                        if (user.projectLocationId != null) ...[
                          const SizedBox(height: 8),
                          _InfoRow(
                            label: 'Location',
                            value: user.projectLocationId!,
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconForRole(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return Icons.admin_panel_settings_outlined;
      case UserRole.hrAdmin:
        return Icons.manage_accounts_outlined;
      case UserRole.employee:
        return Icons.person_outline_rounded;
      case UserRole.manager:
        return Icons.supervisor_account_rounded;
      case UserRole.ops:
        return Icons.analytics_outlined;
      case UserRole.hr:
        return Icons.groups_outlined;
      case UserRole.finance:
        return Icons.account_balance_wallet_outlined;
      case UserRole.bdManager:
        return Icons.business_center_outlined;
      case UserRole.warehouseMgr:
        return Icons.warehouse_outlined;
    }
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            color: AppColors.textMuted,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}
