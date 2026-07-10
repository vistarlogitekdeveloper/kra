/// Per-stage progress state on a `MonthlyReview`.
///
/// The full "who acted on which stage" story is in `StageRecord`; this
/// enum is the coarse indicator the UI reaches for on list rows and
/// stage chips. It's *derived* from the review (record presence + the
/// current stage) rather than stored — see `MonthlyReview.statusOf`.
enum StageStatus {
  /// The review's current stage is earlier than this one — not reached.
  pending,

  /// The review is sitting on this stage and the actor hasn't submitted.
  inProgress,

  /// Actor has submitted / approved and the review has moved past.
  submitted,

  /// Explicitly skipped — e.g. an incentive-payout stage on a review
  /// with a zero eligible amount.
  skipped;

  String toApiString() {
    switch (this) {
      case StageStatus.pending:
        return 'PENDING';
      case StageStatus.inProgress:
        return 'IN_PROGRESS';
      case StageStatus.submitted:
        return 'SUBMITTED';
      case StageStatus.skipped:
        return 'SKIPPED';
    }
  }

  static StageStatus fromApi(String? value) {
    switch ((value ?? '').trim().toUpperCase()) {
      case 'IN_PROGRESS':
        return StageStatus.inProgress;
      case 'SUBMITTED':
      case 'APPROVED':
      case 'DONE':
        return StageStatus.submitted;
      case 'SKIPPED':
        return StageStatus.skipped;
      case 'PENDING':
      default:
        return StageStatus.pending;
    }
  }
}
