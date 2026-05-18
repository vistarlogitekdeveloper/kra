import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../../../core/constants/app_colors.dart';
import '../../../../../../../core/constants/app_strings.dart';
import '../../../../../../../core/router/app_router.dart';
import '../../../../../data/models/bulk_skipped_item.dart';
import '../../../../../data/models/enums.dart';

/// Section list rendered alongside [ApprovedList] when at least one
/// review was skipped. Each row shows the employee + a human-readable
/// reason + an expand-for-technical-detail accordion.
class SkippedList extends StatelessWidget {
  final List<BulkSkippedItem> items;
  const SkippedList({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              const Icon(
                Icons.report_problem_rounded,
                size: 16,
                color: AppColors.accentOrange,
              ),
              const SizedBox(width: 6),
              Text(
                '${AppStrings.managerBulkApproveSkippedCount} '
                '(${items.length})',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accentOrange,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
            ),
            child: Column(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  _Tile(item: items[i]),
                  if (i != items.length - 1)
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
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final BulkSkippedItem item;
  const _Tile({required this.item});

  String _reasonMessage() {
    switch (item.reason) {
      case BulkSkipReason.incompleteAfterCopy:
        return AppStrings.bulkSkipReasonIncomplete;
      case BulkSkipReason.notEmployeeSubmitted:
        return AppStrings.bulkSkipReasonNotSubmitted;
      case BulkSkipReason.deadlinePassed:
        return AppStrings.bulkSkipReasonDeadlinePassed;
      case BulkSkipReason.other:
        return AppStrings.bulkSkipReasonOther;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      childrenPadding:
          const EdgeInsets.fromLTRB(16, 0, 16, 12),
      iconColor: AppColors.accentOrange,
      collapsedIconColor: AppColors.textSecondary,
      title: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.accentOrange.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.warning_amber_rounded,
              size: 16,
              color: AppColors.accentOrange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.employeeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _reasonMessage(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      children: [
        if (item.detail != null && item.detail!.isNotEmpty) ...[
          Container(
            padding:
                const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              item.detail!,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
                height: 1.45,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.go(
              AppRoutes.managerRate(item.reviewId),
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryPurple,
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            icon: const Icon(Icons.rate_review_rounded, size: 16),
            label: const Text(
              'Open review',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}
