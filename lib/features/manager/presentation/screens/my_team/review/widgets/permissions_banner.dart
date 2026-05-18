import 'package:flutter/material.dart';

import '../../../../../../../core/constants/app_colors.dart';
import '../../../../../../../core/constants/app_strings.dart';
import '../../../../../../employee/data/models/enums.dart';
import '../../../../../data/models/review_permissions.dart';

/// Compact informational banner that explains *why* the manager can't
/// rate (yet) when the rate-CTA is hidden. Two flavours:
///   - Pre-rate states (DRAFT / IN_PROGRESS) → "Employee hasn't
///     submitted yet"
///   - Post-rate, post-deadline → "Editing window has closed"
///   - Final / acknowledged → "Read-only" copy
///
/// Hidden whenever `canRate` is `true` — the rate CTA tells its own
/// story on those states.
class PermissionsBanner extends StatelessWidget {
  final ReviewState state;
  final ReviewPermissions permissions;

  const PermissionsBanner({
    super.key,
    required this.state,
    required this.permissions,
  });

  @override
  Widget build(BuildContext context) {
    // When the manager CAN rate or edit, the rate button is doing the
    // talking — no banner needed.
    if (permissions.canRate || permissions.canEdit) {
      return const SizedBox.shrink();
    }

    final palette = _palette();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(palette.icon, color: palette.foreground, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                palette.message,
                style: TextStyle(
                  fontSize: 12.5,
                  color: palette.foreground,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _BannerPalette _palette() {
    switch (state) {
      case ReviewState.draft:
      case ReviewState.inProgress:
        return _BannerPalette(
          icon: Icons.hourglass_top_rounded,
          foreground: AppColors.textSecondary,
          border: AppColors.divider,
          background: AppColors.divider.withValues(alpha: 0.45),
          message: AppStrings.managerReviewDetailWaitingForEmployee,
        );
      case ReviewState.employeeSubmittedAll:
      case ReviewState.managerRatedAll:
        // Manager could rate / edit in principle but `canRate` /
        // `canEdit` came back false — almost always a closed deadline.
        return _BannerPalette(
          icon: Icons.lock_clock_rounded,
          foreground: AppColors.accentRed,
          border: AppColors.accentRed.withValues(alpha: 0.30),
          background: AppColors.accentRed.withValues(alpha: 0.08),
          message: AppStrings.managerReviewDetailWindowClosed,
        );
      case ReviewState.finalized:
      case ReviewState.acknowledged:
        return _BannerPalette(
          icon: Icons.lock_rounded,
          foreground: AppColors.success,
          border: AppColors.success.withValues(alpha: 0.30),
          background: AppColors.success.withValues(alpha: 0.10),
          message: AppStrings.managerReviewDetailFinalisedReadOnly,
        );
    }
  }
}

class _BannerPalette {
  final IconData icon;
  final Color foreground;
  final Color border;
  final Color background;
  final String message;
  const _BannerPalette({
    required this.icon,
    required this.foreground,
    required this.border,
    required this.background,
    required this.message,
  });
}
