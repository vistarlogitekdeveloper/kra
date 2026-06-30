import '../../../auth/data/models/user.dart';

/// The five-stage monthly review pipeline. Every employee's review for a
/// calendar month advances through these stages in order, each gated to a
/// role and carrying a fixed day-of-month deadline.
///
///   Self-Rating            → Employee            → 10th
///   Account & HR Rating    → HR / Finance        → 12th
///   Reporting Manager      → Manager             → 13th
///   Management Review      → Admin / HR-Admin     → 15th
///   Incentive Payout       → Finance / HR         → 20th
///
/// [completed] is the terminal state once payout is marked.
enum ReviewStage {
  selfRating,
  accountHrRating,
  reportingManagerRating,
  managementReview,
  incentivePayout,
  completed;

  /// Human-facing stage name.
  String get label {
    switch (this) {
      case ReviewStage.selfRating:
        return 'Self-Rating';
      case ReviewStage.accountHrRating:
        return 'Account & HR Rating';
      case ReviewStage.reportingManagerRating:
        return 'Reporting Manager Rating';
      case ReviewStage.managementReview:
        return 'Management Review';
      case ReviewStage.incentivePayout:
        return 'Incentive Payout';
      case ReviewStage.completed:
        return 'Completed';
    }
  }

  /// Day-of-month this stage is due. `null` for the terminal state.
  int? get deadlineDay {
    switch (this) {
      case ReviewStage.selfRating:
        return 10;
      case ReviewStage.accountHrRating:
        return 12;
      case ReviewStage.reportingManagerRating:
        return 13;
      case ReviewStage.managementReview:
        return 15;
      case ReviewStage.incentivePayout:
        return 20;
      case ReviewStage.completed:
        return null;
    }
  }

  /// True when this stage captures per-KRA scores (vs. an approve/sign-off
  /// or payout action). Drives whether the stage screen shows a rating
  /// matrix.
  bool get isRatingStage =>
      this == ReviewStage.selfRating ||
      this == ReviewStage.accountHrRating ||
      this == ReviewStage.reportingManagerRating;

  bool get isTerminal => this == ReviewStage.completed;

  /// Position in the pipeline (0-based), used for timeline UI. `completed`
  /// sits past the last actionable stage.
  int get pipelineIndex => index;

  /// The next stage in the pipeline. `completed` stays `completed`.
  ReviewStage get next {
    switch (this) {
      case ReviewStage.selfRating:
        return ReviewStage.accountHrRating;
      case ReviewStage.accountHrRating:
        return ReviewStage.reportingManagerRating;
      case ReviewStage.reportingManagerRating:
        return ReviewStage.managementReview;
      case ReviewStage.managementReview:
        return ReviewStage.incentivePayout;
      case ReviewStage.incentivePayout:
        return ReviewStage.completed;
      case ReviewStage.completed:
        return ReviewStage.completed;
    }
  }

  /// Roles allowed to ACT on this stage. Self-rating is additionally
  /// owner-scoped (only the review's own employee) and the manager stage
  /// is scoped to the employee's reporting manager — that finer-grained
  /// gating lives in the repository's list filters; this set is the coarse
  /// role check used for routing and `MonthlyReview.isActionableBy`.
  Set<UserRole> get actorRoles {
    switch (this) {
      case ReviewStage.selfRating:
        // Any authenticated user can self-rate their own review.
        return UserRole.values.toSet();
      case ReviewStage.accountHrRating:
        return {
          UserRole.hr,
          UserRole.finance,
          UserRole.hrAdmin,
          UserRole.admin,
        };
      case ReviewStage.reportingManagerRating:
        return {
          UserRole.manager,
          UserRole.bdManager,
          UserRole.warehouseMgr,
          UserRole.hrAdmin,
          UserRole.admin,
        };
      case ReviewStage.managementReview:
        return {UserRole.admin, UserRole.hrAdmin};
      case ReviewStage.incentivePayout:
        return {
          UserRole.finance,
          UserRole.hr,
          UserRole.hrAdmin,
          UserRole.admin,
        };
      case ReviewStage.completed:
        return const {};
    }
  }

  String toApiString() => name;

  /// Tolerant parse from the wire (UPPER_SNAKE or camelCase). Falls back to
  /// [selfRating] on anything unknown rather than throwing.
  static ReviewStage fromApi(String? value) {
    if (value == null) return ReviewStage.selfRating;
    final n = value.trim().toUpperCase().replaceAll('-', '_');
    switch (n) {
      case 'SELF_RATING':
      case 'SELFRATING':
        return ReviewStage.selfRating;
      case 'ACCOUNT_HR_RATING':
      case 'ACCOUNTHRRATING':
      case 'ACCOUNT_AND_HR':
        return ReviewStage.accountHrRating;
      case 'REPORTING_MANAGER_RATING':
      case 'REPORTINGMANAGERRATING':
      case 'MANAGER_RATING':
        return ReviewStage.reportingManagerRating;
      case 'MANAGEMENT_REVIEW':
      case 'MANAGEMENTREVIEW':
        return ReviewStage.managementReview;
      case 'INCENTIVE_PAYOUT':
      case 'INCENTIVEPAYOUT':
        return ReviewStage.incentivePayout;
      case 'COMPLETED':
        return ReviewStage.completed;
      default:
        return ReviewStage.selfRating;
    }
  }
}

/// Status of an individual stage within a review.
enum StageStatus {
  /// Not yet reached (an upstream stage is still open).
  notStarted,

  /// This is the current stage and it's awaiting its actor.
  pending,

  /// Actor has begun but not submitted (e.g. a saved draft).
  inProgress,

  /// Actor has submitted / approved — the review has moved on.
  done,

  /// Stage was skipped (e.g. management returned without changes).
  skipped;

  String toApiString() => name;

  static StageStatus fromApi(String? value) {
    switch ((value ?? '').trim().toUpperCase()) {
      case 'PENDING':
        return StageStatus.pending;
      case 'IN_PROGRESS':
      case 'INPROGRESS':
        return StageStatus.inProgress;
      case 'DONE':
      case 'SUBMITTED':
      case 'APPROVED':
        return StageStatus.done;
      case 'SKIPPED':
        return StageStatus.skipped;
      default:
        return StageStatus.notStarted;
    }
  }
}
