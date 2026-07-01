import '../../features/reviews/data/models/review_stage.dart';

/// Fixed monthly deadlines for the 5-stage review pipeline, applied
/// app-wide.
///
/// Every stage of a monthly review is due on a fixed day of the review's
/// calendar month (see [ReviewStage.deadlineDay]):
///
///   Self-Rating .............. 10th
///   Account & HR Rating ...... 12th
///   Reporting Manager Rating . 13th
///   Management Review ........ 15th
///   Incentive Payout ......... 20th
///
/// These are reminder / countdown cues only — actual submission is still
/// governed by the review's `currentStage` and role gating. Deadlines
/// anchor to the calendar month of the supplied reference date (defaults
/// to today).
class MonthlyDeadlines {
  MonthlyDeadlines._();

  /// The deadline date for [stage] in the month containing [reference]
  /// (defaults to today). Returns `null` for [ReviewStage.completed].
  static DateTime? forStage(ReviewStage stage, [DateTime? reference]) {
    final day = stage.deadlineDay;
    if (day == null) return null;
    return _forMonth(day, reference);
  }

  /// The deadline anchored at an explicit [day] of the reference month.
  static DateTime forDay(int day, [DateTime? reference]) =>
      _forMonth(day, reference);

  static DateTime _forMonth(int day, DateTime? reference) {
    final r = reference ?? DateTime.now();
    return DateTime(r.year, r.month, day);
  }

  /// Whole days from today to [deadline], compared date-only so the
  /// answer doesn't flip with the time of day. Negative once passed;
  /// 0 on the deadline day itself.
  static int daysRemaining(DateTime deadline, [DateTime? today]) {
    final t = today ?? DateTime.now();
    return DateTime(deadline.year, deadline.month, deadline.day)
        .difference(DateTime(t.year, t.month, t.day))
        .inDays;
  }

  static bool isOverdue(DateTime deadline, [DateTime? today]) =>
      daysRemaining(deadline, today) < 0;

  // ───────────────────────────────────────────────────────────────
  // Legacy convenience accessors.
  //
  // The employee self-rate and manager-rate screens predate the 5-stage
  // pipeline and call these directly. They delegate to the pipeline
  // schedule (self → 10th, reporting-manager → 13th) so those screens
  // count down to the new dates without each needing an edit. Prefer
  // [forStage] in new code.
  // ───────────────────────────────────────────────────────────────

  static int get selfRatingDay => ReviewStage.selfRating.deadlineDay!;

  static int get managerRatingDay =>
      ReviewStage.reportingManagerRating.deadlineDay!;

  static DateTime selfRating([DateTime? reference]) =>
      forStage(ReviewStage.selfRating, reference)!;

  static DateTime managerRating([DateTime? reference]) =>
      forStage(ReviewStage.reportingManagerRating, reference)!;
}
