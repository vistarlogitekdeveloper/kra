import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/enums/review_flow.dart';
import '../../../../reviews/data/models/monthly_review.dart';
import '../../../../reviews/data/models/rating_access.dart';
import '../../../../reviews/data/models/review_flow.dart';
import 'rating_access_copy.dart';
import 'rating_access_message.dart';
import 'rating_access_skeleton.dart';

/// The organisation's overrides, newest first, as a sliver. Tapping one opens
/// its month.
class RatingAccessHistorySliver extends StatelessWidget {
  final AsyncValue<List<RatingAccessOverride>> history;
  final ReviewPeriod selected;

  /// The organisation's flow once the month has loaded; null until then, when
  /// no row is marked as outside it.
  final ReviewFlow? flow;
  final DateTime now;
  final bool busy;
  final ValueChanged<ReviewPeriod> onSelect;
  final VoidCallback onRetry;

  const RatingAccessHistorySliver({
    super.key,
    required this.history,
    required this.selected,
    required this.flow,
    required this.now,
    required this.busy,
    required this.onSelect,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final state = history;
    return switch (state) {
      AsyncData(:final value) when value.isEmpty => const SliverToBoxAdapter(
          child: RatingAccessMessage(
            icon: Icons.history_rounded,
            title: AppStrings.ratingAccessHistoryEmptyTitle,
            message: AppStrings.ratingAccessHistoryEmptyBody,
          ),
        ),
      AsyncData(:final value) => SliverList.separated(
          itemCount: value.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _HistoryRow(
            entry: value[i],
            flow: flow,
            now: now,
            selected: value[i].period == selected,
            onTap: busy ? null : () => onSelect(value[i].period),
          ),
        ),
      AsyncError(:final error) when !state.isLoading => SliverToBoxAdapter(
          child: RatingAccessMessage(
            icon: Icons.cloud_off_rounded,
            title: AppStrings.ratingAccessHistoryLoadFailed,
            message: ratingAccessErrorText(error),
            accent: AppColors.error,
            onRetry: onRetry,
          ),
        ),
      _ => const SliverToBoxAdapter(
          child: RatingAccessSkeleton(count: 3, itemHeight: 76),
        ),
    };
  }
}

class _HistoryRow extends StatelessWidget {
  final RatingAccessOverride entry;
  final ReviewFlow? flow;
  final DateTime now;
  final bool selected;
  final VoidCallback? onTap;

  const _HistoryRow({
    required this.entry,
    required this.flow,
    required this.now,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final knownFlow = flow;
    final outsideFlow =
        knownFlow != null && !stageIsInFlow(entry.stage, knownFlow);
    final reason = entry.reason;
    final updated = ratingAccessUpdatedLine(entry);
    // Announced as a button: tapping a row opens its month.
    return Semantics(
      button: true,
      enabled: onTap != null,
      selected: selected,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected
                ? AppColors.primaryPurple.withValues(alpha: 0.55)
                : AppColors.divider,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppStrings.ratingAccessHistoryRowTitle(
                          ratingAccessStageLabel(
                            entry.stage,
                            knownFlow ?? ReviewFlow.standard,
                          ),
                          entry.period.label,
                        ),
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (outsideFlow) const _NotInFlowTag(),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  ratingAccessOverrideSummary(entry, now),
                  style:
                      TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
                if (reason != null)
                  Text(
                    AppStrings.ratingAccessReason(reason),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                if (updated != null)
                  Text(
                    updated,
                    style:
                        TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An override on a stage the organisation's flow does not use — the rollout
/// seeds all five stages for every organisation, self-rating included.
class _NotInFlowTag extends StatelessWidget {
  const _NotInFlowTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.textMuted.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        AppStrings.ratingAccessNotInFlow,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
