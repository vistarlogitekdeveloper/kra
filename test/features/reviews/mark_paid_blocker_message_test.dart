import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/constants/app_strings.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review_summary.dart';
import 'package:vistar_app/features/reviews/presentation/widgets/payout_copy.dart';

/// The payout control used to render nothing whenever a condition was unmet,
/// so "this incentive is not payable yet" and "this app has no way to mark
/// incentives paid" looked identical on screen — and the second is what got
/// reported. Every blocker the user can wait out must now name itself, and
/// name the MONTH, because the incentive is settled a quarter at a time.
void main() {
  const waitable = [
    MarkPaidBlocker.monthNotEnded,
    MarkPaidBlocker.managementNotDone,
    MarkPaidBlocker.notSignedOff,
  ];

  test('every waitable blocker has a message naming the month', () {
    for (final b in waitable) {
      final message = markPaidBlockerMessage(b, month: 'September 2026');
      expect(message, isNotNull, reason: '${b.name} must explain itself');
      expect(message, contains('September 2026'),
          reason: '${b.name} must say WHICH month blocks the quarter');
    }
  });

  test('each message names what clears it, not just what is wrong', () {
    // The reader is usually not the person who can clear the blocker:
    // Accounts waits on management. A message that only says "not yet" sends
    // them back to the same screen tomorrow.
    expect(
      AppStrings.quarterPayoutMonthNotEnded('September 2026').toLowerCase(),
      contains('signed it off'),
    );
    expect(
      AppStrings.quarterPayoutManagementNotDone('September 2026').toLowerCase(),
      contains('management'),
    );
    // The server's own refusal names Save & Lock; the client says the same
    // thing, so the two never read as different problems.
    expect(
      AppStrings.quarterPayoutNotSignedOff('September 2026'),
      contains('Save & Lock'),
    );
  });

  test('the viewer-fact blockers draw no control', () {
    // Nothing that happens to the quarter changes these, so a greyed control
    // would be permanent noise for anyone without a payout seat.
    expect(markPaidBlockerMessage(MarkPaidBlocker.notPayoutRole), isNull);
    expect(markPaidBlockerMessage(MarkPaidBlocker.ownReview), isNull);
    // A settled quarter shows the Paid badge instead.
    expect(markPaidBlockerMessage(MarkPaidBlocker.alreadyPaid), isNull);
  });

  test('a new blocker cannot be added without deciding what it says', () {
    // The switch is exhaustive over the enum, so adding a value breaks the
    // build rather than silently falling through to "render nothing" — the
    // exact failure this whole change exists to remove.
    expect(MarkPaidBlocker.values.length, 6);
    for (final b in MarkPaidBlocker.values) {
      markPaidBlockerMessage(b, month: 'September 2026');
    }
  });
}
