import '../../../../core/constants/app_strings.dart';
import '../../data/models/enums.dart';
import '../../data/models/transition_error.dart';

/// Maps backend error codes from `manager-rate` and bulk-approve
/// responses to user-friendly Indian-English copy. Always returns the
/// raw `message` from the error as a fallback so the user has *some*
/// detail even when the code isn't known yet.
class TransitionErrorMessageMapper {
  const TransitionErrorMessageMapper._();

  /// Maps a [TransitionError] (from the manager-rate response).
  static String managerRate(TransitionError? error) {
    if (error == null) return AppStrings.managerRateDeadlinePassed;
    switch (error.code) {
      case 'INCOMPLETE_AFTER_COPY':
        return AppStrings.managerRateErrorIncompleteAfterCopy;
      case 'MONTH_LOCKED':
        return AppStrings.managerRateErrorMonthLocked;
      case 'DEADLINE_PASSED':
        return AppStrings.managerRateErrorDeadlinePassed;
      default:
        return error.message;
    }
  }

  /// Maps a bulk-approve skip reason. Used by the result screen's
  /// per-row "plain English" line.
  static String bulkSkip(BulkSkipReason reason, {String? rawMessage}) {
    switch (reason) {
      case BulkSkipReason.incompleteAfterCopy:
        return AppStrings.bulkSkipReasonIncomplete;
      case BulkSkipReason.notEmployeeSubmitted:
        return AppStrings.bulkSkipReasonNotSubmitted;
      case BulkSkipReason.deadlinePassed:
        return AppStrings.bulkSkipReasonDeadlinePassed;
      case BulkSkipReason.other:
        return rawMessage ?? AppStrings.bulkSkipReasonOther;
    }
  }
}
