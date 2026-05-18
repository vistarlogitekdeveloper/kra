import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/router/app_router.dart';
import '../../../../../core/widgets/shimmer_skeletons.dart';
import '../../../data/models/employee_profile.dart';
import '../../providers/my_profile_providers.dart';
import 'widgets/profile_header.dart';

/// Vertical chain showing the user's manager (above) and themselves
/// (highlighted). "My reports" would render below — currently the
/// /employee/profile endpoint doesn't carry direct-reports data, so
/// the section shows an empty state. (Reserved for a future stage
/// when the manager module lands.)
class MyReportingTreeScreen extends ConsumerWidget {
  const MyReportingTreeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myProfileProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          AppStrings.profileReportingTreeTitle,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go(AppRoutes.employeeProfile),
        ),
      ),
      body: async.when(
        loading: () => const _Loading(),
        error: (e, _) => _Error(
          message: e.toString(),
          onRetry: () => ref.invalidate(myProfileProvider),
        ),
        data: (profile) => _TreeBody(profile: profile),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Body
// ─────────────────────────────────────────────────────────────────────

class _TreeBody extends StatelessWidget {
  final EmployeeProfile profile;
  const _TreeBody({required this.profile});

  @override
  Widget build(BuildContext context) {
    final manager = profile.manager;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        const _SectionLabel(text: AppStrings.profileReportingTreeMyManager),
        const SizedBox(height: 8),
        if (manager == null)
          const _EmptyHint(
            icon: Icons.supervisor_account_outlined,
            message: AppStrings.profileReportingTreeNoManager,
          )
        else
          _PersonNode(
            name: manager.name,
            code: manager.employeeCode ?? '',
            role: manager.role,
          ),

        const SizedBox(height: 16),
        const _Connector(),
        const SizedBox(height: 16),

        const _SectionLabel(text: 'You'),
        const SizedBox(height: 8),
        _PersonNode(
          name: profile.name,
          code: profile.employeeCode,
          role: profile.role,
          isCurrentUser: true,
        ),

        const SizedBox(height: 24),
        const _SectionLabel(text: AppStrings.profileReportingTreeMyReports),
        const SizedBox(height: 8),
        // The /employee/profile endpoint doesn't carry direct-reports
        // — that view is a manager-module surface. Stage 5 wires it in.
        const _EmptyHint(
          icon: Icons.people_outline_rounded,
          message: AppStrings.profileReportingTreeNoReports,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Pieces
// ─────────────────────────────────────────────────────────────────────

class _PersonNode extends StatelessWidget {
  final String name;
  final String code;
  final String? role;
  final bool isCurrentUser;
  const _PersonNode({
    required this.name,
    required this.code,
    required this.role,
    this.isCurrentUser = false,
  });

  @override
  Widget build(BuildContext context) {
    final swatch =
        ProfileHeader.colourFor(code.isNotEmpty ? code : name);
    final initials = ProfileHeader.initialsOf(name);
    final roleLabel = role?.replaceAll('_', ' ');

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrentUser
              ? AppColors.primaryPurple
              : AppColors.divider,
          width: isCurrentUser ? 1.4 : 1,
        ),
        boxShadow: isCurrentUser
            ? [
                BoxShadow(
                  color:
                      AppColors.primaryPurple.withValues(alpha: 0.12),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: swatch.withValues(alpha: 0.15),
              border: Border.all(
                color: swatch.withValues(alpha: 0.4),
                width: 1.6,
              ),
            ),
            child: Center(
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: swatch,
                  letterSpacing: 0.4,
                ),
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
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (roleLabel != null && roleLabel.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryPurple
                              .withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          roleLabel.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryPurple,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    const SizedBox(width: 6),
                    if (code.isNotEmpty)
                      Text(
                        code,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
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

class _Connector extends StatelessWidget {
  const _Connector();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 2,
        height: 32,
        color: AppColors.divider,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppColors.textSecondary,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyHint({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.divider.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Loading + error
// ─────────────────────────────────────────────────────────────────────

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        ProfileHeaderSkeleton(),
        SizedBox(height: 14),
        ProfileHeaderSkeleton(),
      ],
    );
  }
}

class _Error extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _Error({required this.message, required this.onRetry});

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
