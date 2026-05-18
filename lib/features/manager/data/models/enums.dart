// Manager-module enums. Most of the review-state lifecycle lives in
// `lib/features/employee/data/models/enums.dart` (single source of
// truth across modules) — this file only adds enums that are
// manager-specific.

/// Filter buckets used by the team list. Matches the `filterState`
/// query param on GET /manager/team. Falls back to [all] on unknown
/// values rather than throwing so a future backend addition doesn't
/// crash older clients.
enum ManagerTeamFilter {
  /// All team members regardless of review state.
  all,

  /// Reviews where state=EMPLOYEE_SUBMITTED_ALL — the manager's
  /// action queue.
  pendingMyReview,

  /// Reviews the manager has already rated (state=MANAGER_RATED_ALL
  /// or further).
  completed,

  /// Employee hasn't started self-rating yet (state=DRAFT).
  notSubmitted,

  /// Past the manager review deadline and still not finalised.
  overdue;

  /// Wire form used by the API's `filterState` query param. `all`
  /// resolves to omitting the parameter entirely, but having a
  /// string here keeps the call-site uniform.
  String? toApiString() {
    switch (this) {
      case ManagerTeamFilter.all:
        return null;
      case ManagerTeamFilter.pendingMyReview:
        return 'PENDING_MY_REVIEW';
      case ManagerTeamFilter.completed:
        return 'COMPLETED';
      case ManagerTeamFilter.notSubmitted:
        return 'NOT_SUBMITTED';
      case ManagerTeamFilter.overdue:
        return 'OVERDUE';
    }
  }

  static ManagerTeamFilter fromApi(String? value) {
    switch ((value ?? '').trim().toUpperCase()) {
      case 'PENDING_MY_REVIEW':
        return ManagerTeamFilter.pendingMyReview;
      case 'COMPLETED':
        return ManagerTeamFilter.completed;
      case 'NOT_SUBMITTED':
        return ManagerTeamFilter.notSubmitted;
      case 'OVERDUE':
        return ManagerTeamFilter.overdue;
      default:
        return ManagerTeamFilter.all;
    }
  }

  /// Human-readable chip label.
  String get displayName {
    switch (this) {
      case ManagerTeamFilter.all:
        return 'All';
      case ManagerTeamFilter.pendingMyReview:
        return 'Pending My Review';
      case ManagerTeamFilter.completed:
        return 'Completed';
      case ManagerTeamFilter.notSubmitted:
        return 'Not Submitted';
      case ManagerTeamFilter.overdue:
        return 'Overdue';
    }
  }
}

/// Top-level mode for the manager shell: managing the team vs.
/// self-rating. Persisted in [managerModeProvider] so switching
/// modes preserves each subtree's nav stack via `IndexedStack`.
enum ManagerMode {
  myTeam,
  myReview;

  String get displayName {
    switch (this) {
      case ManagerMode.myTeam:
        return 'My Team';
      case ManagerMode.myReview:
        return 'My Review';
    }
  }
}

/// Reasons the backend may return for skipping a review in a bulk
/// approve operation. Mapped to plain-English copy via
/// `transition_error_message_mapper.dart` so the result screen reads
/// well without leaking backend internals.
enum BulkSkipReason {
  /// Ops or Finance haven't filled their scores yet — the
  /// employee-self → manager copy left holes the manager couldn't fix.
  incompleteAfterCopy,

  /// Employee hasn't moved to state=EMPLOYEE_SUBMITTED_ALL yet.
  notEmployeeSubmitted,

  /// Manager-review deadline has passed.
  deadlinePassed,

  /// Any other reason the backend reports — surfaces the raw message.
  other;

  static BulkSkipReason fromApi(String value) {
    switch (value.trim().toUpperCase()) {
      case 'INCOMPLETE_AFTER_COPY':
        return BulkSkipReason.incompleteAfterCopy;
      case 'NOT_EMPLOYEE_SUBMITTED':
        return BulkSkipReason.notEmployeeSubmitted;
      case 'DEADLINE_PASSED':
        return BulkSkipReason.deadlinePassed;
      default:
        return BulkSkipReason.other;
    }
  }
}
