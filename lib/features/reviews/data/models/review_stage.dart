import '../../../auth/data/models/user.dart';

/// Ordered stages of a single monthly review.
///
/// Every calendar month, every employee runs through this pipeline in
/// order. Only the roles in [actorRoles] can advance a stage, and only
/// when the review's `currentStage` equals that stage. Submitting a
/// stage moves the review to [next]; the terminal [completed] stage has
/// no actor and loops to itself.
///
/// Deadlines are fixed to the same day of every month — see
/// [deadlineDay] and `MonthlyDeadlines.forStage`.
enum ReviewStage {
  /// Employee scores every KRA row on their own review — the 10th.
  selfRating,

  /// HR + Finance/Account provide a first-pass numerical check on the
  /// self scores — the 12th.
  accountHrRating,

  /// The employee's reporting manager writes the final per-row scores
  /// and comments — the 13th.
  reportingManagerRating,

  /// Admin / HR-Admin approves or returns the manager's rating with a
  /// comment — the 15th.
  managementReview,

  /// Finance / HR mark the computed incentive as paid — the 20th.
  incentivePayout,

  /// Terminal state. No actor, no deadline, loops to itself as [next].
  completed;

  /// UPPER_SNAKE wire form. Round-trips via [fromApi] / [toApiString].
  static ReviewStage fromApi(String? value) {
    final raw = (value ?? '').trim();
    switch (raw.toUpperCase().replaceAll('-', '_')) {
      case 'SELF_RATING':
        return ReviewStage.selfRating;
      case 'ACCOUNT_HR_RATING':
        return ReviewStage.accountHrRating;
      case 'REPORTING_MANAGER_RATING':
        return ReviewStage.reportingManagerRating;
      case 'MANAGEMENT_REVIEW':
        return ReviewStage.managementReview;
      case 'INCENTIVE_PAYOUT':
        return ReviewStage.incentivePayout;
      case 'COMPLETED':
        return ReviewStage.completed;
      default:
        // Also tolerate camelCase (enum .name) from a newer backend,
        // then pin unknowns to the earliest safe stage so the review
        // still surfaces instead of taking out a whole dashboard.
        for (final s in ReviewStage.values) {
          if (s.name.toUpperCase() == raw.toUpperCase()) return s;
        }
        return ReviewStage.selfRating;
    }
  }

  String toApiString() {
    switch (this) {
      case ReviewStage.selfRating:
        return 'SELF_RATING';
      case ReviewStage.accountHrRating:
        return 'ACCOUNT_HR_RATING';
      case ReviewStage.reportingManagerRating:
        return 'REPORTING_MANAGER_RATING';
      case ReviewStage.managementReview:
        return 'MANAGEMENT_REVIEW';
      case ReviewStage.incentivePayout:
        return 'INCENTIVE_PAYOUT';
      case ReviewStage.completed:
        return 'COMPLETED';
    }
  }

  /// Human label for chips, tiles, breadcrumbs.
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

  /// Day of the reference month the stage is due. `null` for the
  /// terminal [completed] stage. See `MonthlyDeadlines.forStage`.
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

  /// Roles that can advance this stage. A stage is actionable by a role
  /// only when the review's current stage equals this stage AND the
  /// caller's role is in this set.
  Set<UserRole> get actorRoles {
    switch (this) {
      case ReviewStage.selfRating:
        // Owner-scoped: anyone who has their own review self-rates it. The
        // roster layer treats ops as a self-scope participant, so ops must
        // be able to submit their own self-rating too.
        return const {UserRole.employee, UserRole.ops};
      case ReviewStage.accountHrRating:
        // HR_ADMIN is the live HR persona (UserRole.fromApi maps HR_ADMIN →
        // hrAdmin), so it must be able to act here or the pipeline stalls
        // at stage 2. Matches docs/BACKEND_HANDOFF.md (HR_ADMIN, FINANCE).
        return const {UserRole.hr, UserRole.hrAdmin, UserRole.finance};
      case ReviewStage.reportingManagerRating:
        // Any manager-tier role gets a team roster from the provider, so
        // BD / warehouse managers must be able to rate their reports too.
        return const {
          UserRole.manager,
          UserRole.bdManager,
          UserRole.warehouseMgr,
        };
      case ReviewStage.managementReview:
        return const {UserRole.admin, UserRole.hrAdmin};
      case ReviewStage.incentivePayout:
        // HR_ADMIN again — same reason as accountHrRating (stall at stage 5
        // otherwise). Matches docs/BACKEND_HANDOFF.md (FINANCE, HR_ADMIN).
        return const {UserRole.finance, UserRole.hr, UserRole.hrAdmin};
      case ReviewStage.completed:
        return const {};
    }
  }

  /// Next stage in the pipeline. [completed] loops to itself so callers
  /// never have to null-check the terminal edge.
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

  bool get isTerminal => this == ReviewStage.completed;

  /// The three stages that capture per-row scores (self, account/HR,
  /// reporting manager). Management review and incentive payout don't.
  bool get isRatingStage =>
      this == ReviewStage.selfRating ||
      this == ReviewStage.accountHrRating ||
      this == ReviewStage.reportingManagerRating;

  /// 1-based position in the pipeline for the UI's "Step N / 5" chip.
  /// [completed] returns 6 so a finished review still sorts last.
  int get pipelineIndex {
    switch (this) {
      case ReviewStage.selfRating:
        return 1;
      case ReviewStage.accountHrRating:
        return 2;
      case ReviewStage.reportingManagerRating:
        return 3;
      case ReviewStage.managementReview:
        return 4;
      case ReviewStage.incentivePayout:
        return 5;
      case ReviewStage.completed:
        return 6;
    }
  }

  /// Total pipeline length (excluding [completed]).
  static const int pipelineLength = 5;

  /// True when [role] is one of [actorRoles].
  ///
  /// NOTE: this is only the authority for the ORG-LEVEL stages. For the two
  /// relationship stages ([isRelationshipStage]) the caller's role is NOT the
  /// gate — see [MonthlyReview.isActionableBy], which resolves them from the
  /// review's `employeeId` / `managerId` instead.
  bool isActionableBy(UserRole role) => actorRoles.contains(role);

  /// True for the stages decided by WHO the caller is to a given review rather
  /// than by their role:
  ///   * [selfRating] — the review's owner, whatever their role. Every employee
  ///     has their own KRA, managers and HR admins included.
  ///   * [reportingManagerRating] — the review's reporting manager, whatever
  ///     THEIR role. Managers report to senior managers and HR admins report to
  ///     someone too, so the rater is not necessarily a manager-tier role.
  ///
  /// The remaining stages (account/HR rating, management review, incentive
  /// payout) are org-level responsibilities and stay keyed on [actorRoles].
  bool get isRelationshipStage =>
      this == ReviewStage.selfRating ||
      this == ReviewStage.reportingManagerRating;
}
