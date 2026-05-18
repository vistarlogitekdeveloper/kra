/// Lifecycle of a single per-cycle review.
///
/// Mirrors the Prisma `ReviewState` enum on the backend. State
/// transitions are server-driven — the client never moves a review
/// backwards. `fromApi` falls back to [draft] on any unknown value
/// rather than throwing, so a future state added on the backend
/// won't crash older clients.
///
/// State machine:
///   DRAFT
///     └─→ IN_PROGRESS  (employee scores any cell)
///           └─→ EMPLOYEE_SUBMITTED_ALL  (every applicable cell rated, autoSubmit=true)
///                 └─→ MANAGER_RATED_ALL  (manager has scored all rows)
///                       └─→ FINALIZED  (HR locks the cycle)
///                             └─→ ACKNOWLEDGED  (employee acknowledges the result)
enum ReviewState {
  draft,
  inProgress,
  employeeSubmittedAll,
  managerRatedAll,
  finalized,
  acknowledged;

  static ReviewState fromApi(String value) {
    switch (value.trim().toUpperCase()) {
      case 'DRAFT':
        return ReviewState.draft;
      case 'IN_PROGRESS':
        return ReviewState.inProgress;
      case 'EMPLOYEE_SUBMITTED_ALL':
        return ReviewState.employeeSubmittedAll;
      case 'MANAGER_RATED_ALL':
        return ReviewState.managerRatedAll;
      case 'FINALIZED':
        return ReviewState.finalized;
      case 'ACKNOWLEDGED':
        return ReviewState.acknowledged;
      default:
        return ReviewState.draft;
    }
  }

  String toApiString() {
    switch (this) {
      case ReviewState.draft:
        return 'DRAFT';
      case ReviewState.inProgress:
        return 'IN_PROGRESS';
      case ReviewState.employeeSubmittedAll:
        return 'EMPLOYEE_SUBMITTED_ALL';
      case ReviewState.managerRatedAll:
        return 'MANAGER_RATED_ALL';
      case ReviewState.finalized:
        return 'FINALIZED';
      case ReviewState.acknowledged:
        return 'ACKNOWLEDGED';
    }
  }

  /// Display label used by the state badge / pill.
  String get displayName {
    switch (this) {
      case ReviewState.draft:
        return 'Draft';
      case ReviewState.inProgress:
        return 'In progress';
      case ReviewState.employeeSubmittedAll:
        return 'Submitted';
      case ReviewState.managerRatedAll:
        return 'Manager rated';
      case ReviewState.finalized:
        return 'Finalized';
      case ReviewState.acknowledged:
        return 'Acknowledged';
    }
  }

  /// Position in the 6-step pipeline (1-indexed). Used by the timeline
  /// indicator on the review detail screen (Stage 4).
  int get pipelineStep {
    switch (this) {
      case ReviewState.draft:
        return 1;
      case ReviewState.inProgress:
        return 2;
      case ReviewState.employeeSubmittedAll:
        return 3;
      case ReviewState.managerRatedAll:
        return 4;
      case ReviewState.finalized:
        return 5;
      case ReviewState.acknowledged:
        return 6;
    }
  }

  /// True if the employee can still record / edit self-ratings.
  /// The POST self-rate endpoint accepts state ∈
  /// {DRAFT, IN_PROGRESS, EMPLOYEE_SUBMITTED_ALL}; any further
  /// progression locks the employee out.
  bool get isSelfEditable =>
      this == ReviewState.draft ||
      this == ReviewState.inProgress ||
      this == ReviewState.employeeSubmittedAll;

  /// True once the employee has marked their submission complete
  /// (every applicable cell rated). UI uses this to switch the
  /// current-month CTA from "Start rating" to "View submission".
  bool get hasSubmittedAll =>
      this != ReviewState.draft && this != ReviewState.inProgress;

  /// True once the manager has finished their pass — controls
  /// whether the home card surfaces a manager total.
  bool get isManagerComplete =>
      this == ReviewState.managerRatedAll ||
      this == ReviewState.finalized ||
      this == ReviewState.acknowledged;
}

/// Status of a single month inside a review cycle. Server flips these
/// as cycles progress — clients should treat them as read-only.
///
/// Wire values (per Prisma `MonthStatus`):
///   OPEN   — month is editable (self + manager can score)
///   CLOSED — month is no longer accepting edits but not yet locked
///   LOCKED — HR has locked the month; no further changes allowed
enum ReviewMonthStatus {
  open,
  closed,
  locked;

  static ReviewMonthStatus fromApi(String value) {
    switch (value.trim().toUpperCase()) {
      case 'OPEN':
        return ReviewMonthStatus.open;
      case 'CLOSED':
        return ReviewMonthStatus.closed;
      case 'LOCKED':
        return ReviewMonthStatus.locked;
      default:
        return ReviewMonthStatus.open;
    }
  }

  String toApiString() {
    switch (this) {
      case ReviewMonthStatus.open:
        return 'OPEN';
      case ReviewMonthStatus.closed:
        return 'CLOSED';
      case ReviewMonthStatus.locked:
        return 'LOCKED';
    }
  }
}

/// Per-month status returned by the incentive-summary endpoint.
/// Distinct from [ReviewMonthStatus] because it captures the rating
/// progress (not just the month's open/closed state) — used by the
/// incentive snapshot to colour-code rows.
enum MonthlyIncentiveStatus {
  /// No Review row exists for this cycle yet.
  noReview,

  /// Month is open, but the employee hasn't self-rated any of it yet.
  pendingSelf,

  /// Employee has self-rated; manager hasn't scored.
  pendingManager,

  /// Manager has rated all applicable rows for the month — earnings
  /// from this row contribute to `earnedSoFar`.
  complete,

  /// HR has locked the month — no edits possible.
  locked;

  static MonthlyIncentiveStatus fromApi(String value) {
    switch (value.trim().toUpperCase()) {
      case 'NO_REVIEW':
        return MonthlyIncentiveStatus.noReview;
      case 'PENDING_SELF':
        return MonthlyIncentiveStatus.pendingSelf;
      case 'PENDING_MANAGER':
        return MonthlyIncentiveStatus.pendingManager;
      case 'COMPLETE':
        return MonthlyIncentiveStatus.complete;
      case 'LOCKED':
        return MonthlyIncentiveStatus.locked;
      default:
        return MonthlyIncentiveStatus.noReview;
    }
  }

  String toApiString() {
    switch (this) {
      case MonthlyIncentiveStatus.noReview:
        return 'NO_REVIEW';
      case MonthlyIncentiveStatus.pendingSelf:
        return 'PENDING_SELF';
      case MonthlyIncentiveStatus.pendingManager:
        return 'PENDING_MANAGER';
      case MonthlyIncentiveStatus.complete:
        return 'COMPLETE';
      case MonthlyIncentiveStatus.locked:
        return 'LOCKED';
    }
  }

  String get displayName {
    switch (this) {
      case MonthlyIncentiveStatus.noReview:
        return 'No review';
      case MonthlyIncentiveStatus.pendingSelf:
        return 'Pending self';
      case MonthlyIncentiveStatus.pendingManager:
        return 'Pending manager';
      case MonthlyIncentiveStatus.complete:
        return 'Complete';
      case MonthlyIncentiveStatus.locked:
        return 'Locked';
    }
  }
}

/// Score source for a review row. Not all rows are self-rateable;
/// some come from a feed (attendance, sales numbers) or are
/// manager-only. The self-rate form filters by this value.
enum ScoreSource {
  self,
  manager,
  feed;

  static ScoreSource fromApi(String value) {
    switch (value.trim().toUpperCase()) {
      case 'SELF':
        return ScoreSource.self;
      case 'FEED':
        return ScoreSource.feed;
      case 'MANAGER':
      default:
        return ScoreSource.manager;
    }
  }

  String toApiString() {
    switch (this) {
      case ScoreSource.self:
        return 'SELF';
      case ScoreSource.manager:
        return 'MANAGER';
      case ScoreSource.feed:
        return 'FEED';
    }
  }
}
