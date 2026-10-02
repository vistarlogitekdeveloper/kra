import 'package:intl/intl.dart';

import '../../../../../core/api/api_error.dart';
import '../../../../../core/api/error_text.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/enums/review_flow.dart';
import '../../../../reviews/data/models/monthly_review.dart';
import '../../../../reviews/data/models/rating_access.dart';
import '../../../../reviews/data/models/rating_window.dart';
import '../../../../reviews/data/models/review_flow.dart';
import '../../../../reviews/data/models/review_stage.dart';
import '../_formatters.dart';

// Copy for the rating-access screen: pure functions of the server's answer and
// the clock, so every line a super admin reads is testable without a widget.

final DateFormat _dateParam = DateFormat('yyyy-MM-dd');

/// Where a stage's window stands at an instant, derived only from what the
/// server resolved.
enum RatingAccessPhase {
  /// The month has not ended; nothing opens before it does.
  notYetOpen,

  /// Open on the stage's own deadline.
  deadlineOpen,

  /// Past the deadline, and nothing reopened it.
  deadlineClosed,

  /// A super admin reopened it, and it is open now.
  reopened,

  /// A super admin's reopen that has run out.
  reopenEnded,

  /// A super admin closed it.
  closedByAdmin,
}

/// The phase of [window] at [now].
///
/// A window the server marked CLOSED reads as closed even if its `closed` flag
/// disagrees — the display fails closed, as the server does.
RatingAccessPhase ratingAccessPhase(RatingWindow window, DateTime now) {
  if (window.closed || window.source == RatingWindowSource.closed) {
    return RatingAccessPhase.closedByAdmin;
  }
  if (now.isBefore(window.opensAt)) return RatingAccessPhase.notYetOpen;
  final open = window.isOpenAt(now);
  if (window.source == RatingWindowSource.opened) {
    return open ? RatingAccessPhase.reopened : RatingAccessPhase.reopenEnded;
  }
  return open
      ? RatingAccessPhase.deadlineOpen
      : RatingAccessPhase.deadlineClosed;
}

/// An instant as the app writes dates, `d MMM yyyy`, on the IST calendar —
/// the timezone every window is defined in, so a 23:59 IST deadline never
/// reads as the next day on a device elsewhere.
String ratingAccessDate(DateTime instant) =>
    HrFormatters.date(RatingWindow.toIst(instant));

/// The IST calendar day of [instant], as a date with no time.
DateTime ratingAccessIstDay(DateTime instant) {
  final ist = RatingWindow.toIst(instant);
  return DateTime(ist.year, ist.month, ist.day);
}

/// The first day worth picking for a stage whose own deadline is
/// [deadlineAt]: the day after it, or [today] when that is later. A reopen
/// ending on or before the deadline changes nothing, and the server refuses
/// it (docs/RATING_ACCESS.md §3.5).
DateTime ratingAccessFirstOpenDay(DateTime? deadlineAt, DateTime today) {
  if (deadlineAt == null) return today;
  final afterDeadline =
      ratingAccessIstDay(deadlineAt).add(const Duration(days: 1));
  return afterDeadline.isAfter(today) ? afterDeadline : today;
}

/// [day] as the `YYYY-MM-DD` the server reads as the END of that day, IST.
String ratingAccessDateParam(DateTime day) => _dateParam.format(day);

/// The latest day the open sheet offers: a year from [today].
DateTime ratingAccessLastOpenDay(DateTime today) =>
    DateTime(today.year + 1, today.month, today.day);

/// The day the open sheet starts on: the stage's current end when it is still
/// ahead, otherwise [today] — always within what the date picker allows.
DateTime ratingAccessDefaultOpenDay(DateTime? currentEnd, DateTime today) {
  if (currentEnd == null) return today;
  final endDay = ratingAccessIstDay(currentEnd);
  if (endDay.isBefore(today)) return today;
  final last = ratingAccessLastOpenDay(today);
  return endDay.isAfter(last) ? last : endDay;
}

/// The month chips: [available] (newest first), plus [selected] when a deep
/// link or a history row named a month outside them, so the month on screen
/// is always one of the chips.
List<ReviewPeriod> ratingAccessChipPeriods(
  List<ReviewPeriod> available,
  ReviewPeriod selected,
) {
  if (available.contains(selected)) return available;
  return [...available, selected]..sort((a, b) => b.compareTo(a));
}

/// A failure as the user reads it. The server names an unknown organisation
/// with its own code (RES_ORG_NOT_FOUND); any other 404 / RES_001 means the
/// endpoints are not deployed yet — a known state, not a fault.
String ratingAccessErrorText(Object error) {
  if (error is ApiError && error.code == 'RES_ORG_NOT_FOUND') {
    return AppStrings.ratingAccessOrgNotFound;
  }
  if (error is ApiError &&
      (error.statusCode == 404 || error.code == 'RES_001')) {
    return AppStrings.ratingAccessApiMissing;
  }
  return userFacingError(error);
}

/// Whether management, not the reporting manager, holds the reporting-manager
/// seat — keyed off the relationship gate so the label follows whoever
/// actually rates, as the KRA sheet's seat labels do.
bool _managementHoldsManagerSeat(ReviewFlow flow) =>
    !stageIsRelationshipGated(ReviewStage.reportingManagerRating, flow);

/// The stage named for the seat that rates it under [flow].
String ratingAccessStageLabel(ReviewStage stage, ReviewFlow flow) {
  switch (stage) {
    case ReviewStage.selfRating:
      return AppStrings.ratingAccessStageSelf;
    case ReviewStage.reportingManagerRating:
      return _managementHoldsManagerSeat(flow)
          ? AppStrings.ratingAccessStageManagementRating
          : AppStrings.ratingAccessStageReportingManager;
    case ReviewStage.accountHrRating:
      return AppStrings.ratingAccessStageHr;
    case ReviewStage.financeRating:
      return AppStrings.ratingAccessStageAccounts;
    case ReviewStage.managementReview:
      return AppStrings.ratingAccessStageManagementReview;
    case ReviewStage.incentivePayout:
    case ReviewStage.completed:
      return stage.label;
  }
}

/// Who rates at [stage] under [flow], in one sentence.
String ratingAccessSeatDescription(ReviewStage stage, ReviewFlow flow) {
  switch (stage) {
    case ReviewStage.selfRating:
      return AppStrings.ratingAccessSeatSelf;
    case ReviewStage.reportingManagerRating:
      return _managementHoldsManagerSeat(flow)
          ? AppStrings.ratingAccessSeatManagementRating
          : AppStrings.ratingAccessSeatReportingManager;
    case ReviewStage.accountHrRating:
      return AppStrings.ratingAccessSeatHr;
    case ReviewStage.financeRating:
      return AppStrings.ratingAccessSeatAccounts;
    case ReviewStage.managementReview:
      return AppStrings.ratingAccessSeatManagementReview;
    case ReviewStage.incentivePayout:
    case ReviewStage.completed:
      return '';
  }
}

/// The stage card's status line for [window] at [now].
String ratingAccessStatusLine(RatingWindow window, DateTime now) {
  final until = window.closesAt;
  final untilText = until == null ? null : ratingAccessDate(until);
  switch (ratingAccessPhase(window, now)) {
    case RatingAccessPhase.closedByAdmin:
      return AppStrings.ratingAccessStatusClosedByAdmin;
    case RatingAccessPhase.notYetOpen:
      final opens = ratingAccessDate(window.opensAt);
      if (window.source != RatingWindowSource.opened) {
        return AppStrings.ratingAccessStatusOpens(opens);
      }
      return untilText == null
          ? AppStrings.ratingAccessStatusOpensReopenedNoEnd(opens)
          : AppStrings.ratingAccessStatusOpensReopenedUntil(opens, untilText);
    case RatingAccessPhase.reopened:
      return untilText == null
          ? AppStrings.ratingAccessStatusReopenedNoEnd
          : AppStrings.ratingAccessStatusReopenedUntil(untilText);
    case RatingAccessPhase.deadlineOpen:
      return untilText == null
          ? AppStrings.ratingAccessStatusOpenNoEnd
          : AppStrings.ratingAccessStatusDeadlineOpen(untilText);
    // Both time-closed phases carry an end: a window without one never closes.
    case RatingAccessPhase.reopenEnded:
      return AppStrings.ratingAccessStatusReopenEnded(untilText ?? '');
    case RatingAccessPhase.deadlineClosed:
      return AppStrings.ratingAccessStatusDeadlineClosed(untilText ?? '');
  }
}

/// What an override does, for the history list.
String ratingAccessOverrideSummary(RatingAccessOverride entry, DateTime now) {
  if (entry.mode == RatingAccessMode.closed) {
    return AppStrings.ratingAccessOverrideClosed;
  }
  final until = entry.openUntil;
  if (until == null) return AppStrings.ratingAccessOverrideOpenNoEnd;
  final date = ratingAccessDate(until);
  return entry.hasEndedAt(now)
      ? AppStrings.ratingAccessOverrideOpenEnded(date)
      : AppStrings.ratingAccessOverrideOpenUntil(date);
}

/// "by Asha · 2 Oct 2026", or as much of it as the server sent; null when it
/// sent neither.
String? ratingAccessUpdatedLine(RatingAccessOverride entry) {
  final trimmed = entry.updatedByName?.trim();
  final name = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  final at = entry.updatedAt;
  if (at == null) {
    return name == null ? null : AppStrings.ratingAccessUpdatedByName(name);
  }
  final date = ratingAccessDate(at);
  return name == null
      ? AppStrings.ratingAccessUpdatedOn(date)
      : AppStrings.ratingAccessUpdatedBy(name, date);
}
