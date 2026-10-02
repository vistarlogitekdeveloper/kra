import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../../reviews/data/models/monthly_review.dart';
import '../../../reviews/data/models/rating_access.dart';
import '../../../reviews/presentation/providers/monthly_review_providers.dart';
import '../../../reviews/presentation/providers/rating_access_providers.dart';
import '../providers/organization_providers.dart';
import '../widgets/confirm_action_dialog.dart';
import '../widgets/rating_access/rating_access_copy.dart';
import '../widgets/rating_access/rating_access_handlers.dart';
import '../widgets/rating_access/rating_access_locked.dart';
import '../widgets/rating_access/rating_access_open_sheet.dart';
import '../widgets/rating_access/rating_access_view.dart';

/// When each rating stage of a month accepts entries, for one organisation,
/// and the super admin's overrides of that (docs/RATING_ACCESS.md §4.3).
///
/// By default the date decides: every stage closes at its own deadline in the
/// month after the one rated. A super admin may open a stage until a day —
/// rate AND edit, exactly like a normal open window — close it, or put it back
/// on its deadline. Every status line here is the server's resolution, never
/// the client's: the server enforces the same answer on every write.
///
/// SUPER_ADMIN only. The router bounces everyone else; the lock below is
/// defence in depth, since a role can change under an open screen.
class RatingAccessScreen extends ConsumerStatefulWidget {
  final String organizationId;

  /// The month from the route's `period` query parameter. Null opens the
  /// month currently being rated.
  final ReviewPeriod? initialPeriod;

  const RatingAccessScreen({
    super.key,
    required this.organizationId,
    this.initialPeriod,
  });

  @override
  ConsumerState<RatingAccessScreen> createState() => _RatingAccessScreenState();
}

class _RatingAccessScreenState extends ConsumerState<RatingAccessScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(canManageOrganizationsProvider);
    final period =
        widget.initialPeriod ?? ref.watch(availablePeriodsProvider).first;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.ratingAccessTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: AppStrings.commonBack,
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(AppRoutes.hrOrganizations),
        ),
        actions: [
          if (canManage)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: AppStrings.commonRefresh,
              onPressed: _busy ? null : () => _refresh(period),
            ),
        ],
      ),
      body: canManage
          ? RatingAccessView(
              organizationId: widget.organizationId,
              period: period,
              busy: _busy,
              handlers: _handlers(period),
            )
          : const RatingAccessLocked(),
    );
  }

  RatingAccessHandlers _handlers(ReviewPeriod period) => RatingAccessHandlers(
        onSelectPeriod: _selectPeriod,
        onOpenUntil: (month, entry) => _openUntil(period, month, entry),
        onClose: (month, entry) => _close(period, month, entry),
        onUseDeadline: (month, entry) => _useDeadline(period, month, entry),
        onOpenAll: (month) => _openAll(period, month),
        onResetAll: (month) => _resetAll(period, month),
        onRetryMonth: () => ref.invalidate(ratingAccessMonthProvider(
          (organizationId: widget.organizationId, period: period),
        )),
        onRetryHistory: () => ref
            .invalidate(ratingAccessOverridesProvider(widget.organizationId)),
      );

  void _refresh(ReviewPeriod period) {
    ref.invalidate(ratingAccessMonthProvider(
      (organizationId: widget.organizationId, period: period),
    ));
    ref.invalidate(ratingAccessOverridesProvider(widget.organizationId));
  }

  /// The month lives in the route, so it is replaced in place: no history
  /// entry per chip, and this page keeps its state.
  void _selectPeriod(ReviewPeriod period) => AppRoutes.replaceInPlace(
        context,
        AppRoutes.hrOrganizationRatingAccess(
          widget.organizationId,
          period: period.key,
        ),
      );

  DateTime _today() {
    final now = ref.read(ratingAccessClockProvider)();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _openUntil(
    ReviewPeriod period,
    RatingAccessMonth month,
    RatingAccessStage entry,
  ) async {
    final label = ratingAccessStageLabel(entry.stage, month.reviewFlow);
    final today = _today();
    final request = await RatingAccessOpenSheet.show(
      context,
      title: AppStrings.ratingAccessOpenTitle(label),
      subtitle: period.label,
      today: today,
      initialDay: ratingAccessDefaultOpenDay(entry.window.closesAt, today),
    );
    if (request == null || !mounted) return;
    final lastDay = request.lastDay;
    await _run(
      (actions) => actions.set(
        widget.organizationId,
        period,
        entry.stage,
        mode: RatingAccessMode.open,
        openUntilDate: lastDay == null ? null : ratingAccessDateParam(lastDay),
        reason: request.reason,
      ),
      success: lastDay == null
          ? AppStrings.ratingAccessOpenedNoEnd(label)
          : AppStrings.ratingAccessOpenedUntil(
              label, ratingAccessDate(lastDay)),
    );
  }

  Future<void> _close(
    ReviewPeriod period,
    RatingAccessMonth month,
    RatingAccessStage entry,
  ) async {
    final label = ratingAccessStageLabel(entry.stage, month.reviewFlow);
    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.ratingAccessCloseTitle(label, period.label),
      message: AppStrings.ratingAccessCloseMessage,
      confirmLabel: AppStrings.ratingAccessActionClose,
      icon: Icons.lock_rounded,
    );
    if (ok != true || !mounted) return;
    await _run(
      (actions) => actions.set(
        widget.organizationId,
        period,
        entry.stage,
        mode: RatingAccessMode.closed,
      ),
      success: AppStrings.ratingAccessClosedDone(label),
    );
  }

  Future<void> _useDeadline(
    ReviewPeriod period,
    RatingAccessMonth month,
    RatingAccessStage entry,
  ) async {
    final label = ratingAccessStageLabel(entry.stage, month.reviewFlow);
    final deadline = entry.window.deadlineAt;
    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.ratingAccessUseDeadlineTitle(label),
      message: deadline == null
          ? AppStrings.ratingAccessUseDeadlineMessageNoDate
          : AppStrings.ratingAccessUseDeadlineMessage(
              ratingAccessDate(deadline)),
      confirmLabel: AppStrings.ratingAccessActionUseDeadline,
      icon: Icons.restore_rounded,
      accentColor: AppColors.primaryPurple,
    );
    if (ok != true || !mounted) return;
    await _run(
      (actions) => actions.clear(widget.organizationId, period, entry.stage),
      success: AppStrings.ratingAccessDeadlineRestored(label),
    );
  }

  /// Opens the stages the flow uses — the cards on screen. A stage the flow
  /// has no seat for is never shown, so it is never changed from here either.
  Future<void> _openAll(ReviewPeriod period, RatingAccessMonth month) async {
    final stages = [for (final entry in month.stagesInFlow) entry.stage];
    final today = _today();
    final request = await RatingAccessOpenSheet.show(
      context,
      title: AppStrings.ratingAccessActionOpenAll,
      subtitle:
          AppStrings.ratingAccessOpenAllSubtitle(period.label, stages.length),
      today: today,
      initialDay: today,
    );
    if (request == null || !mounted) return;
    final lastDay = request.lastDay;
    await _run(
      (actions) => actions.openAll(
        widget.organizationId,
        period,
        stages,
        openUntilDate: lastDay == null ? null : ratingAccessDateParam(lastDay),
        reason: request.reason,
      ),
      success: lastDay == null
          ? AppStrings.ratingAccessAllOpenedNoEnd
          : AppStrings.ratingAccessAllOpenedUntil(ratingAccessDate(lastDay)),
    );
  }

  Future<void> _resetAll(ReviewPeriod period, RatingAccessMonth month) async {
    final stages = [
      for (final entry in month.stagesInFlow)
        if (entry.adminOverride != null) entry.stage,
    ];
    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.ratingAccessResetAllTitle,
      message: AppStrings.ratingAccessResetAllMessage(period.label),
      confirmLabel: AppStrings.ratingAccessActionUseDeadline,
      icon: Icons.restore_rounded,
      accentColor: AppColors.primaryPurple,
    );
    if (ok != true || !mounted) return;
    await _run(
      (actions) => actions.resetAll(widget.organizationId, period, stages),
      success: AppStrings.ratingAccessAllDeadlineRestored,
    );
  }

  /// One write at a time: everything is disabled until it lands, and the
  /// outcome is said in a snackbar. Only [ApiError] is caught — the repository
  /// lifts every failure into one, so anything else is a bug for the global
  /// handler, not a message for the user.
  Future<void> _run(
    Future<Object?> Function(RatingAccessActions actions) write, {
    required String success,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await write(ref.read(ratingAccessActionsProvider));
      if (!mounted) return;
      HapticFeedback.selectionClick();
      _snack(success);
    } on ApiError catch (e) {
      if (!mounted) return;
      _snack(AppStrings.ratingAccessSaveFailed(ratingAccessErrorText(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}
