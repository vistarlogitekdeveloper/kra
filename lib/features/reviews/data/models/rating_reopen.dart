import 'monthly_review.dart';

/// Months reopened for rating on a backend that predates rating access.
///
/// With a current backend this class decides nothing: every review carries the
/// server's own windows (`ratingAccess`, docs/RATING_ACCESS.md), and migration
/// 169 seeds the same July/August reopen there. This is the client's copy of
/// that reopen for the case where the server sends no windows, so the two
/// behave alike: July and August 2026 are open to EVERY stage — self,
/// reporting manager, HR, Accounts and management — for rating AND editing,
/// ratings already given included, together with their reasons and proof
/// attachments, until 31 Oct 2026 end of day IST. The product owner confirmed
/// "rate and edit" for these two months.
///
/// Normally a month is open for entry only while it is the review month (see
/// [ReviewPeriod.isOpenForRatingOn]). A listed month is treated exactly like
/// that open month instead. Who may rate, the self-first order per KRA, the
/// manager's ceiling, a completed (paid) review and management's lock all
/// still apply, on the client and on the server.
///
/// Held process-wide and adopted at boot, like `DeadlineSchedule`, because the
/// gates that read it are synchronous. Empty until adopted, so anywhere boot
/// has not run — including every test that does not opt in — sees the ordinary
/// window.
class RatingReopen {
  RatingReopen._();

  /// The months this build reopens, as [ReviewPeriod.key]s.
  ///
  /// 2 Oct 2026: July and August 2026, so self, reporting-manager, HR,
  /// Accounts and management ratings — and their reasons and attachments — can
  /// be entered or corrected. Temporary — remove a key to close that month.
  static const Set<String> granted = {'2026-07', '2026-08'};

  /// The grant ends with the server's pre-open of the same months: migration
  /// 169 opens July and August 2026 until 31 Oct 2026, end of day IST. It must
  /// not outlive the server's — otherwise a new app on a lagging backend would
  /// keep those months open after the date the product owner agreed.
  static final DateTime grantEndsAt =
      DateTime.utc(2026, 10, 31, 18, 29, 59, 999);

  static Set<String> _months = const {};

  /// Reopens [monthKeys].
  static void adopt(Set<String> monthKeys) =>
      _months = Set.unmodifiable(monthKeys);

  /// Back to the ordinary window. For tests.
  static void reset() => _months = const {};

  /// Whether [month] is reopened — open for rating and editing at every stage,
  /// like the review month itself — on [now].
  ///
  /// Only once the month has ENDED, so a listed month that is still running
  /// stays shut: a mistyped key must not open the live month. And only until
  /// [grantEndsAt].
  static bool isReopened(ReviewPeriod month, DateTime now) =>
      _months.contains(month.key) &&
      month.isRatableOn(now) &&
      !now.isAfter(grantEndsAt);
}
