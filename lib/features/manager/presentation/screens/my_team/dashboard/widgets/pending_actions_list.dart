import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../../../core/constants/app_colors.dart';
import '../../../../../../../core/constants/app_strings.dart';
import '../../../../../../../core/router/app_router.dart';
import '../../../../../data/models/pending_action.dart';
import 'pending_action_tile.dart';

/// Section on the manager dashboard listing reviews waiting for the
/// manager to rate. Shows the first 5 with a "View all (N)" link
/// below if more — the spec's compromise between "don't bury the
/// pending work" and "don't make the dashboard a list screen".
class PendingActionsList extends StatelessWidget {
  final List<PendingAction> actions;
  static const int _previewLimit = 5;

  const PendingActionsList({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const _AllCaughtUp();
    final visible = actions.take(_previewLimit).toList();
    final overflow = actions.length - visible.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${AppStrings.managerDashboardPendingTitle} '
                  '(${actions.length})',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final action in visible) ...[
            PendingActionTile(
              action: action,
              onTap: () => context.go(
                AppRoutes.managerReviewDetail(action.reviewId),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (overflow > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => context.go(AppRoutes.managerTeamList),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryPurple,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 4),
                ),
                child: Text(
                  '${AppStrings.managerDashboardViewAll} ($overflow)',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AllCaughtUp extends StatelessWidget {
  const _AllCaughtUp();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppColors.success.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppColors.success,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                AppStrings.managerDashboardAllCaughtUp,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.success,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
