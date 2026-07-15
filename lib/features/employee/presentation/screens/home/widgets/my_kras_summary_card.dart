import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../../../../core/widgets/shimmer_box.dart';
import '../../../../data/models/my_kra_assignment.dart';
import '../../../providers/my_kra_providers.dart';
import '../../../widgets/_formatters.dart';

/// Collapsed list of the employee's KRAs for the active cycle.
///
/// Shows the first 4 items inline; "View all" expands the rest below
/// in-place rather than navigating away (the user came to the home
/// tab to glance, not to drill down — keeping it on-screen respects
/// that intent).
class MyKrasSummaryCard extends ConsumerStatefulWidget {
  /// Active cycle id from the dashboard payload. Null means we
  /// haven't determined a cycle yet (no active cycle / still loading);
  /// the card hides its body in that case.
  final String? cycleId;

  const MyKrasSummaryCard({super.key, this.cycleId});

  @override
  ConsumerState<MyKrasSummaryCard> createState() =>
      _MyKrasSummaryCardState();
}

class _MyKrasSummaryCardState extends ConsumerState<MyKrasSummaryCard> {
  static const int _collapsedCount = 4;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final assignmentAsync =
        ref.watch(myActiveAssignmentProvider(widget.cycleId));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.divider),
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        child: assignmentAsync.when(
          loading: _buildLoading,
          error: (e, _) => _buildError(e.toString()),
          data: _buildLoaded,
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShimmerBox(height: 14, width: 140, borderRadius: 6),
        SizedBox(height: 8),
        ShimmerBox(height: 12, width: 220, borderRadius: 6),
        SizedBox(height: 16),
        ShimmerBox(height: 14, borderRadius: 6),
        SizedBox(height: 10),
        ShimmerBox(height: 14, borderRadius: 6),
        SizedBox(height: 10),
        ShimmerBox(height: 14, borderRadius: 6),
      ],
    );
  }

  Widget _buildError(String message) {
    return _Header(
      title: AppStrings.homeMyKrasTitle,
      subtitle: message,
      subtitleColor: AppColors.error,
    );
  }

  Widget _buildLoaded(MyKraAssignment? assignment) {
    final items = assignment?.items ?? const [];
    if (items.isEmpty) {
      return const _Header(
        title: AppStrings.homeMyKrasTitle,
        subtitle: AppStrings.homeMyKrasEmpty,
        subtitleColor: AppColors.textSecondary,
      );
    }

    // Subtitle shows the assigned template only — the review-cycle name is
    // intentionally omitted now that reviews are monthly.
    final subtitle = assignment?.template?.name ?? '';

    final visible = _expanded ? items : items.take(_collapsedCount).toList();
    final hasMore = items.length > _collapsedCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          title: '${AppStrings.homeMyKrasTitle} (${items.length} '
              '${items.length == 1 ? 'item' : 'items'})',
          subtitle: subtitle,
          subtitleColor: AppColors.textSecondary,
        ),
        const SizedBox(height: 4),
        for (int i = 0; i < visible.length; i++)
          _KraRow(
            item: visible[i],
            showDivider: i != visible.length - 1,
          ),
        if (hasMore)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryPurple,
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                minimumSize: const Size(0, 32),
              ),
              child: Text(
                _expanded
                    ? '— ${items.length - _collapsedCount} fewer'
                    : '+ ${items.length - _collapsedCount} more',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color subtitleColor;
  const _Header({
    required this.title,
    required this.subtitle,
    required this.subtitleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: subtitleColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _KraRow extends StatelessWidget {
  final MyKraAssignmentItem item;
  final bool showDivider;
  const _KraRow({required this.item, required this.showDivider});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(
                bottom: BorderSide(color: AppColors.divider, width: 0.6),
              )
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primaryPurple.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              EmployeeFormatters.weightagePercent(item.weightagePercent),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryPurple,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
