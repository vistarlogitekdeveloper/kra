import 'monthly_review.dart';

/// Months reopened so ratings still PENDING when their entry window closed can
/// be filled in — by the reporting manager, HR and Accounts, not only the
/// employee.
///
/// The window shuts a month to new ratings once the next month opens (see
/// [ReviewPeriod.isOpenForRatingOn]). Three things already reach back past it:
/// the employee's own blank KRAs, a self-rating returned for rework, and
/// management sign-off. Nothing reached back for the three reviewers, so a
/// review whose reviewer missed the window could never be finished by anyone.
///
/// A month listed here opens its BLANK reviewer cells to their assigned rater.
/// It finishes a month and never revises one: a cell that already carries a
/// score stays shut, which is the employee's backfill rule applied to the
/// reviewers. Who may rate, the self-first order per KRA, the manager's
/// ceiling, a completed review and management's lock are all still enforced,
/// on the client and on the server.
///
/// Held process-wide and adopted at boot, like `DeadlineSchedule`, because the
/// gates that read it are synchronous. Empty until adopted, so anywhere boot
/// has not run — including every test that does not opt in — sees the ordinary
/// window.
class RatingReopen {
  RatingReopen._();

  /// The months this build reopens, as [ReviewPeriod.key]s.
  ///
  /// 2 Oct 2026: July and August 2026, so self, reporting-manager, HR and
  /// Accounts ratings still pending in them can be completed. Temporary —
  /// remove a key to close that month again.
  static const Set<String> granted = {'2026-07', '2026-08'};

  /// The grant ends with the server's pre-open of the same months: migration
  /// 169 opens July and August 2026 until 31 Oct 2026, end of day IST. This
  /// client-side grant only matters on a backend that predates rating access
  /// (docs/RATING_ACCESS.md §4.2), and it must not outlive the server's —
  /// otherwise a new app on a lagging backend would keep those months open
  /// after the date the product owner agreed.
  static final DateTime grantEndsAt =
      DateTime.utc(2026, 10, 31, 18, 29, 59, 999);

  static Set<String> _months = const {};

  /// Reopens [monthKeys] for backfill.
  static void adopt(Set<String> monthKeys) =>
      _months = Set.unmodifiable(monthKeys);

  /// Back to the ordinary window. For tests.
  static void reset() => _months = const {};

  /// Whether [month]'s blank cells are open to their raters on [now].
  ///
  /// Only once the month has ENDED, so a listed month that is still running
  /// stays shut: a mistyped key must not open the live month. And only until
  /// [grantEndsAt].
  static bool allowsBackfill(ReviewPeriod month, DateTime now) =>
      _months.contains(month.key) &&
      month.isRatableOn(now) &&
      !now.isAfter(grantEndsAt);
}
