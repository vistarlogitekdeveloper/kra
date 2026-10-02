import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/widgets/slow_load_hint.dart';
import '../../../../reviews/data/models/monthly_review.dart';
import '../../../../reviews/data/models/rating_access.dart';
import '../../../../reviews/presentation/providers/monthly_review_providers.dart';
import '../../../../reviews/presentation/providers/rating_access_providers.dart';
import 'rating_access_copy.dart';
import 'rating_access_handlers.dart';
import 'rating_access_header.dart';
import 'rating_access_history.dart';
import 'rating_access_message.dart';
import 'rating_access_month_chips.dart';
import 'rating_access_month_section.dart';
import 'rating_access_skeleton.dart';

/// The rating-access screen's content for one organisation and month: header,
/// month chips, one card per stage, and the override history.
class RatingAccessView extends ConsumerWidget {
  final String organizationId;
  final ReviewPeriod period;

  /// A write is in flight: every control is disabled and the bar runs.
  final bool busy;
  final RatingAccessHandlers handlers;

  const RatingAccessView({
    super.key,
    required this.organizationId,
    required this.period,
    required this.busy,
    required this.handlers,
  });

  static const double _maxContentWidth = 960;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(ratingAccessMonthProvider(
      (organizationId: organizationId, period: period),
    ));
    final history = ref.watch(ratingAccessOverridesProvider(organizationId));
    final chips =
        ratingAccessChipPeriods(ref.watch(availablePeriodsProvider), period);
    final now = ref.watch(ratingAccessClockProvider)();
    final gutter = math.max(
      16.0,
      (MediaQuery.sizeOf(context).width - _maxContentWidth) / 2,
    );

    return Column(
      children: [
        _WorkingBar(
          visible: busy || month.isRefreshing || history.isRefreshing,
        ),
        Expanded(
          child: CustomScrollView(
            slivers: [
              _Gutter(gutter: gutter, top: 16, child: _HeaderSlot(month)),
              _Gutter(
                gutter: gutter,
                top: 12,
                child: RatingAccessMonthChips(
                  periods: chips,
                  selected: period,
                  enabled: !busy,
                  onSelect: handlers.onSelectPeriod,
                ),
              ),
              _Gutter(
                gutter: gutter,
                top: 16,
                child: _MonthSlot(
                  month: month,
                  now: now,
                  busy: busy,
                  handlers: handlers,
                ),
              ),
              _Gutter(gutter: gutter, top: 12, child: const _HistoryTitle()),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 0),
                sliver: RatingAccessHistorySliver(
                  history: history,
                  selected: period,
                  flow: month.valueOrNull?.reviewFlow,
                  now: now,
                  busy: busy,
                  onSelect: handlers.onSelectPeriod,
                  onRetry: handlers.onRetryHistory,
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 32 + MediaQuery.paddingOf(context).bottom,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Centres a box child at [RatingAccessView._maxContentWidth] by padding it,
/// so the scroll view itself stays full width and scrolls from anywhere.
class _Gutter extends StatelessWidget {
  final double gutter;
  final double top;
  final Widget child;

  const _Gutter({required this.gutter, required this.top, required this.child});

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(gutter, top, gutter, 0),
      sliver: SliverToBoxAdapter(child: child),
    );
  }
}

/// A 2 px bar, reserved even when idle so the content never shifts.
class _WorkingBar extends StatelessWidget {
  final bool visible;
  const _WorkingBar({required this.visible});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2,
      child: visible
          ? LinearProgressIndicator(
              minHeight: 2,
              semanticsLabel: AppStrings.ratingAccessWorking,
              color: AppColors.primaryPurple,
              backgroundColor: AppColors.primaryPurple.withValues(alpha: 0.12),
            )
          : null,
    );
  }
}

class _HeaderSlot extends StatelessWidget {
  final AsyncValue<RatingAccessMonth> month;
  const _HeaderSlot(this.month);

  @override
  Widget build(BuildContext context) {
    final state = month;
    return switch (state) {
      AsyncData(:final value) => RatingAccessHeader(month: value),
      // The month slot below explains the failure; a second panel here would
      // only repeat it.
      AsyncError() when !state.isLoading => const SizedBox.shrink(),
      _ => const RatingAccessSkeleton(count: 1, itemHeight: 112),
    };
  }
}

class _MonthSlot extends StatelessWidget {
  final AsyncValue<RatingAccessMonth> month;
  final DateTime now;
  final bool busy;
  final RatingAccessHandlers handlers;

  const _MonthSlot({
    required this.month,
    required this.now,
    required this.busy,
    required this.handlers,
  });

  @override
  Widget build(BuildContext context) {
    final state = month;
    final Widget child = switch (state) {
      AsyncData(:final value) => RatingAccessMonthSection(
          key: ValueKey('month-${value.period.key}'),
          month: value,
          now: now,
          busy: busy,
          handlers: handlers,
        ),
      AsyncError(:final error) when !state.isLoading => RatingAccessMessage(
          key: const ValueKey('month-error'),
          icon: Icons.cloud_off_rounded,
          title: AppStrings.ratingAccessLoadFailed,
          message: ratingAccessErrorText(error),
          accent: AppColors.error,
          onRetry: handlers.onRetryMonth,
        ),
      _ => const Column(
          key: ValueKey('month-loading'),
          children: [
            SlowLoadHint(),
            RatingAccessSkeleton(count: 4, itemHeight: 168),
          ],
        ),
    };
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, if (current != null) current],
      ),
      child: child,
    );
  }
}

class _HistoryTitle extends StatelessWidget {
  const _HistoryTitle();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.ratingAccessHistoryTitle,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          AppStrings.ratingAccessHistorySubtitle,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
