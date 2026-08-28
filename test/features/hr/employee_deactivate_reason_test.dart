import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/api/api_error.dart';
import 'package:vistar_app/core/constants/app_strings.dart';
import 'package:vistar_app/features/hr/presentation/providers/employee_providers.dart';

/// Deleting an employee fails with a 409 naming what blocks it, and the message
/// the user sees has to be actionable.
///
/// This came from a real attempt to remove a test employee: the app said only
/// "Could not delete. Please try again." — retrying can never work — and the
/// server's own wording ("in-progress review(s). Finalize or close them first")
/// reads as if the shared review cycle is in the way. Deleting that cycle
/// cascades away every employee's KRA assignments, the cycle's months and the
/// bonus slabs, so the message must name the right review and warn off the
/// cycle.
void main() {
  ApiError conflict(String message) => ApiError(
        type: ApiErrorType.server,
        code: 'CONFLICT',
        message: message,
        statusCode: 409,
      );

  test('an in-progress review explains itself AND warns off the cycle', () {
    final reason = deactivateFailureReason(conflict(
      'Cannot deactivate: 1 in-progress review(s). Finalize or close them first.',
    ));

    expect(reason, AppStrings.employeesDeactivateBlockedReviews);
    // The two things that make it actionable rather than alarming.
    expect(reason, contains('their own'));
    expect(reason.toLowerCase(), contains('do not delete the review cycle'));
    expect(reason, isNot(AppStrings.employeesDeactivateFailed));
  });

  test('direct reports get their own instruction, not the review one', () {
    final reason = deactivateFailureReason(conflict(
      'Cannot deactivate: 3 active direct report(s). Reassign them first.',
    ));

    expect(reason, AppStrings.employeesDeactivateBlockedReports);
    expect(reason.toLowerCase(), contains('reporting manager'));
  });

  test('an unrecognised server message is shown verbatim, not swallowed', () {
    // Better a raw server sentence than "please try again" on something a
    // retry cannot fix.
    final reason = deactivateFailureReason(conflict('Employee is locked'));
    expect(reason, 'Employee is locked');
  });

  test('a non-API failure falls back to the generic message', () {
    expect(
      deactivateFailureReason(Exception('socket closed')),
      AppStrings.employeesDeactivateFailed,
    );
  });

  test('an empty server message falls back rather than showing nothing', () {
    expect(
      deactivateFailureReason(conflict('')),
      AppStrings.employeesDeactivateFailed,
    );
  });
}
