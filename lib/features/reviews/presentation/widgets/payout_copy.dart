import '../../../../core/constants/app_strings.dart';
import '../../data/models/monthly_review_summary.dart';

/// The sentence shown when a quarter's incentive cannot be settled yet, or
/// null when the blocker draws no control at all.
///
/// Kept apart from the widget that renders it so the mapping is testable on
/// its own: the strings ARE the feature here. The control used to disappear
/// when a condition was unmet, which is indistinguishable from an app that
/// cannot mark incentives paid — which is how it was reported.
///
/// [month] names the month standing in the way ("September 2026"). It is
/// required for the three waitable blockers, because a quarter is three
/// months and "this month is still running" does not say which.
String? markPaidBlockerMessage(MarkPaidBlocker blocker, {String? month}) {
  switch (blocker) {
    // Facts about the VIEWER, not the quarter: no waiting changes them, and a
    // greyed control for someone who can never pay is permanent noise.
    case MarkPaidBlocker.notPayoutRole:
    case MarkPaidBlocker.ownReview:
    // A settled quarter shows its Paid badge instead.
    case MarkPaidBlocker.alreadyPaid:
      return null;
    case MarkPaidBlocker.monthNotEnded:
      return AppStrings.quarterPayoutMonthNotEnded(month ?? 'This month');
    case MarkPaidBlocker.managementNotDone:
      return AppStrings.quarterPayoutManagementNotDone(month ?? 'this month');
    case MarkPaidBlocker.notSignedOff:
      return AppStrings.quarterPayoutNotSignedOff(month ?? 'this month');
  }
}
