import 'package:flutter/material.dart';

import '../../../../../../../core/constants/app_colors.dart';
import '../../../../../../../core/constants/app_strings.dart';

/// AppBar variant shown while the team list is in multi-select mode.
/// Replaces the normal "My Team" AppBar with the selection count, a
/// Cancel action, and an Approve action that's disabled until at
/// least one reviewable row is selected.
class BulkSelectAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final int selectedCount;
  final VoidCallback onCancel;
  final VoidCallback? onApprove;

  const BulkSelectAppBar({
    super.key,
    required this.selectedCount,
    required this.onCancel,
    required this.onApprove,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final canApprove = onApprove != null && selectedCount > 0;
    return AppBar(
      backgroundColor: AppColors.primaryPurple,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: AppStrings.commonCancel,
        onPressed: onCancel,
      ),
      title: Text(
        '$selectedCount ${AppStrings.managerTeamBulkSelectedCount}',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      actions: [
        TextButton(
          onPressed: canApprove ? onApprove : null,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          child: const Text(
            AppStrings.managerTeamBulkApproveCta,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}
