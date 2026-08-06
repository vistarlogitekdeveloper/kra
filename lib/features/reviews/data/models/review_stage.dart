import '../../../auth/data/models/user.dart';

/// Stages of a single monthly review.
///
/// Conceptually the review runs in FOUR cycles (see [reviewCycle]):
///   1. **Self** — the employee rates every KRA.
///   2. **Review** — three INDEPENDENT ratings entered in parallel by the
///      reporting manager, HR and Finance. Their per-KRA average is the
///      Review score (see [MonthlyReview.reviewAvgPct]).
///   3. **Management** — management (the founder/CEO tier, held as
///      [UserRole.admin]) either approves (the Review average stands) or, on
///      rework, enters a rating that OVERRIDES it and becomes final.
///   4. **Payout** — Finance/HR mark the incentive paid.
///
/// The three Review-cycle raters are separate enum values so each stores its
/// own per-KRA score, but they belong to the same cycle and are surfaced as a
/// single "Review" column on the sheet.
enum ReviewStage {
  /// Cycle 1 — the employee scores every KRA on their own review.
  selfRating,

  /// Cycle 2 — the employee's reporting manager scores each KRA (relationship,
  /// whatever the manager's role).
  reportingManagerRating,

  /// Cycle 2 — HR scores each KRA.
  accountHrRating,

  /// Cycle 2 — Finance / Accounts scores each KRA.
  financeRating,

  /// Cycle 3 — management (HR) approves the Review average, or overrides it
  /// per KRA on rework. That override is the final score.
  managementReview,

  /// Cycle 4 — Finance / HR mark the computed incentive as paid.
  incentivePayout,

  /// Terminal state. No actor, no deadline, loops to itself as [next].
  completed;

  /// UPPER_SNAKE wire form. Round-trips via [fromApi] / [toApiString].
  static ReviewStage fromApi(String? value) {
    final raw = (value ?? '').trim();
    switch (raw.toUpperCase().replaceAll('-', '_')) {
      case 'SELF_RATING':
        return ReviewStage.selfRating;
      case 'REPORTING_MANAGER_RATING':
        return ReviewStage.reportingManagerRating;
      case 'ACCOUNT_HR_RATING':
      case 'HR_RATING':
        return ReviewStage.accountHrRating;
      case 'FINANCE_RATING':
      case 'ACCOUNTS_RATING':
        return ReviewStage.financeRating;
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
      case ReviewStage.reportingManagerRating:
        return 'REPORTING_MANAGER_RATING';
      case ReviewStage.accountHrRating:
        return 'ACCOUNT_HR_RATING';
      case ReviewStage.financeRating:
        return 'FINANCE_RATING';
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
      case ReviewStage.reportingManagerRating:
        return 'Reporting Manager';
      case ReviewStage.accountHrRating:
        return 'HR';
      case ReviewStage.financeRating:
        return 'Finance';
      case ReviewStage.managementReview:
        return 'Management Review';
      case ReviewStage.incentivePayout:
        return 'Incentive Payout';
      case ReviewStage.completed:
        return 'Completed';
    }
  }

  /// Dashboard PHASE label — collapses the three Review-cycle raters (Reporting
  /// Manager / HR / Finance) into a single "Review", so a status badge reflects
  /// the conceptual Self → Review → Management → Payout pipeline rather than
  /// whichever individual rater happens to be furthest along. The rating flows
  /// keep [label] (the specific rater) for clarity.
  String get phaseLabel {
    switch (this) {
      case ReviewStage.selfRating:
        return 'Self-Rating';
      case ReviewStage.reportingManagerRating:
      case ReviewStage.accountHrRating:
      case ReviewStage.financeRating:
        return 'Review';
      case ReviewStage.managementReview:
        return 'Management Review';
      case ReviewStage.incentivePayout:
        return 'Incentive Payout';
      case ReviewStage.completed:
        return 'Completed';
    }
  }

  /// Which of the four conceptual review cycles this stage belongs to
  /// (1 = Self, 2 = Review, 3 = Management, 4 = Payout). Drives the sheet's
  /// column grouping. [completed] returns 4 so a finished review sorts last.
  int get reviewCycle {
    switch (this) {
      case ReviewStage.selfRating:
        return 1;
      case ReviewStage.reportingManagerRating:
      case ReviewStage.accountHrRating:
      case ReviewStage.financeRating:
        return 2;
      case ReviewStage.managementReview:
        return 3;
      case ReviewStage.incentivePayout:
      case ReviewStage.completed:
        return 4;
    }
  }

  /// The three raters that make up the Review cycle (cycle 2). Their per-KRA
  /// scores are averaged into the Review score.
  static const Set<ReviewStage> reviewRaters = {
    ReviewStage.reportingManagerRating,
    ReviewStage.accountHrRating,
    ReviewStage.financeRating,
  };

  /// True for a Review-cycle rater (RM / HR / Finance).
  bool get isReviewRater => reviewRaters.contains(this);

  /// Day of the reference month the stage is due. `null` for the terminal
  /// [completed] stage. See `MonthlyDeadlines.forStage`.
  int? get deadlineDay {
    switch (this) {
      case ReviewStage.selfRating:
        return 10;
      case ReviewStage.reportingManagerRating:
        return 13;
      case ReviewStage.accountHrRating:
        return 13;
      case ReviewStage.financeRating:
        return 13;
      case ReviewStage.managementReview:
        return 15;
      case ReviewStage.incentivePayout:
        return 20;
      case ReviewStage.completed:
        return null;
    }
  }

  /// Roles that can advance/act on this stage BY ROLE.
  ///
  /// The two RELATIONSHIP stages ([isRelationshipStage]) are NOT gated here —
  /// [MonthlyReview.isActionableBy] resolves them from the review's
  /// `employeeId` / `managerId` instead. The rest are org-level responsibilities
  /// keyed on role.
  Set<UserRole> get actorRoles {
    switch (this) {
      case ReviewStage.selfRating:
        // Relationship stage (the owner) — role set is a fallback only.
        return const {UserRole.employee, UserRole.ops};
      case ReviewStage.reportingManagerRating:
        // Relationship stage (the reporting manager, whatever their role) —
        // role set is a fallback only.
        return const {
          UserRole.manager,
          UserRole.bdManager,
          UserRole.warehouseMgr,
        };
      case ReviewStage.accountHrRating:
        // The HR rater in the Review cycle.
        return const {UserRole.hr, UserRole.hrAdmin};
      case ReviewStage.financeRating:
        // The Finance / Accounts rater in the Review cycle. HR_ADMIN holds this
        // seat too: the commercial/HR-admin post covers Accounts rating as well,
        // and a single [UserRole] can't express "HR Admin AND Accounts".
        return const {UserRole.finance, UserRole.hrAdmin};
      case ReviewStage.managementReview:
        // MANAGEMENT ONLY — the founder/CEO tier, held as ADMIN. Deliberately
        // NOT hrAdmin: HR administers the cycle and rates its HR seat, but the
        // management approval/override is the final word on an employee's score
        // and incentive, so it stays with management alone.
        return const {UserRole.admin};
      case ReviewStage.incentivePayout:
        return const {UserRole.finance, UserRole.hr, UserRole.hrAdmin};
      case ReviewStage.completed:
        return const {};
    }
  }

  /// Next stage in the pipeline. [completed] loops to itself so callers never
  /// have to null-check the terminal edge. The Review-cycle raters are entered
  /// in parallel in practice (edit-in-place), so this linear order only matters
  /// to the formal submit-stage cursor.
  ReviewStage get next {
    switch (this) {
      case ReviewStage.selfRating:
        return ReviewStage.reportingManagerRating;
      case ReviewStage.reportingManagerRating:
        return ReviewStage.accountHrRating;
      case ReviewStage.accountHrRating:
        return ReviewStage.financeRating;
      case ReviewStage.financeRating:
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

  /// The stages that capture per-KRA scores: self, the three Review raters, and
  /// management (its rework override is a per-KRA score too). Incentive payout
  /// does not.
  bool get isRatingStage =>
      this == ReviewStage.selfRating ||
      isReviewRater ||
      this == ReviewStage.managementReview;

  /// 1-based position in the pipeline for ordering. [completed] returns 7 so a
  /// finished review still sorts last.
  int get pipelineIndex {
    switch (this) {
      case ReviewStage.selfRating:
        return 1;
      case ReviewStage.reportingManagerRating:
        return 2;
      case ReviewStage.accountHrRating:
        return 3;
      case ReviewStage.financeRating:
        return 4;
      case ReviewStage.managementReview:
        return 5;
      case ReviewStage.incentivePayout:
        return 6;
      case ReviewStage.completed:
        return 7;
    }
  }

  /// Total pipeline length (excluding [completed]).
  static const int pipelineLength = 6;

  /// True when [role] is one of [actorRoles].
  ///
  /// Authority for the ORG-LEVEL stages only. For the relationship stages
  /// ([isRelationshipStage]) see [MonthlyReview.isActionableBy].
  bool isActionableBy(UserRole role) => actorRoles.contains(role);

  /// Stages decided by WHO the caller is to a review rather than by role:
  ///   * [selfRating] — the review's owner, whatever their role.
  ///   * [reportingManagerRating] — the review's reporting manager, whatever
  ///     THEIR role.
  bool get isRelationshipStage =>
      this == ReviewStage.selfRating ||
      this == ReviewStage.reportingManagerRating;
}
