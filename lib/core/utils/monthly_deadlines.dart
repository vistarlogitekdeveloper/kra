/// Fixed monthly rating deadlines, applied app-wide.
///
/// Self-rating is due on the [selfRatingDay] of every month; manager
/// rating on the [managerRatingDay]. These are reminder / countdown cues
/// only — actual submission is still governed by the backend (canRate and
/// the review state). The deadline anchors to the current calendar month.
///
/// Centralised here so every surface (home banner, self-rate screen,
/// manager-rate screen, review detail) counts down to the same dates.
class MonthlyDeadlines {
  MonthlyDeadlines._();

  /// Day-of-month the self-rating is due.
  static const int selfRatingDay = 7;

  /// Day-of-month the manager rating is due.
  static const int managerRatingDay = 10;

  /// The self-rating deadline for the month containing [reference]
  /// (defaults to today).
  static DateTime selfRating([DateTime? reference]) =>
      _forMonth(selfRatingDay, reference);

  /// The manager-rating deadline for the month containing [reference]
  /// (defaults to today).
  static DateTime managerRating([DateTime? reference]) =>
      _forMonth(managerRatingDay, reference);

  static DateTime _forMonth(int day, DateTime? reference) {
    final r = reference ?? DateTime.now();
    return DateTime(r.year, r.month, day);
  }

  /// Whole days from today to [deadline], compared date-only so the
  /// answer doesn't flip with the time of day. Negative once the
  /// deadline has passed; 0 on the deadline day itself.
  static int daysRemaining(DateTime deadline, [DateTime? today]) {
    final t = today ?? DateTime.now();
    return DateTime(deadline.year, deadline.month, deadline.day)
        .difference(DateTime(t.year, t.month, t.day))
        .inDays;
  }

  static bool isOverdue(DateTime deadline, [DateTime? today]) =>
      daysRemaining(deadline, today) < 0;
}
