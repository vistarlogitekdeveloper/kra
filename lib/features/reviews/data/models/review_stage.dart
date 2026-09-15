import '../../../../core/constants/feature_flags.dart';
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
  ///
  /// THE single source for the official schedule — every countdown, banner and
  /// notice in the app resolves here, so a date changed here changes
  /// everywhere:
  ///
  ///   Self-Rating .............. 10th
  ///   Account & HR Rating ...... 12th
  ///   Reporting Manager Rating . 13th
  ///   Management Review ........ 15th
  ///   Incentive Payout ......... 20th
  ///
  /// The Account/HR side falls due BEFORE the reporting manager, which is why
  /// the three Review raters no longer share one date. `accountHrRating` is the
  /// HR rater and `financeRating` the Accounts one; together they are the
  /// schedule's single "Account & HR Rating" line, so both carry the 12th.
  int? get deadlineDay => DeadlineSchedule.dayFor(this);

  /// The circulated table, frozen in the client.
  ///
  /// Used whenever the server has not told us otherwise — offline, an older
  /// backend, or a failed fetch — so the app always has an answer and never
  /// shows a blank deadline.
  int? get publishedDeadlineDay {
    switch (this) {
      case ReviewStage.selfRating:
        return 10;
      case ReviewStage.accountHrRating:
        return 12;
      case ReviewStage.financeRating:
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
        // The management tier signs off (approve, or override per KRA on
        // rework) — the last gate before the incentive is paid, so it is
        // deliberately NOT the same seat as the HR rater: HR would otherwise
        // approve its own input.
        //
        // Until the backend's employees enum accepts `MANAGEMENT`, nobody can
        // be assigned it and gating on it alone would leave this stage with no
        // eligible actor, so HR_ADMIN shares it. See [FeatureFlags.roleTiers].
        return FeatureFlags.roleTiers
            ? const {UserRole.management}
            : const {UserRole.management, UserRole.hrAdmin};
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

  /// True when ANY of [roles] may act on this stage — the multi-role form.
  /// Someone holding both the HR and Accounts seats can act on either.
  bool isActionableByAny(Set<UserRole> roles) => roles.any(actorRoles.contains);

  /// Stages decided by WHO the caller is to a review rather than by role:
  ///   * [selfRating] — the review's owner, whatever their role.
  ///   * [reportingManagerRating] — the review's reporting manager, whatever
  ///     THEIR role.
  bool get isRelationshipStage =>
      this == ReviewStage.selfRating ||
      this == ReviewStage.reportingManagerRating;
}

/// The deadline schedule actually in force.
///
/// The days are a published business rule, but the backend allows per-instance
/// env overrides (`KRA_*_DEADLINE_DAY`) and serves the resolved table from
/// `GET /config/deadlines`. Its startup log states that the app follows those
/// values, so the app has to actually read them — otherwise an override moves
/// the reminder emails and leaves every screen counting to the old date, which
/// is the drift this whole exercise removed.
///
/// Resolved ONCE at boot and held process-wide rather than passed around,
/// because [ReviewStage.deadlineDay] and [MonthlyDeadlines] are synchronous and
/// read from a dozen widgets. Empty until [adopt] is called, so behaviour is
/// identical to the frozen table unless the server disagrees.
class DeadlineSchedule {
  DeadlineSchedule._();

  static Map<ReviewStage, int> _resolved = const {};

  /// True once the server schedule has been adopted.
  static bool get isResolved => _resolved.isNotEmpty;

  /// Stages whose server day differs from the published table — non-empty only
  /// when an override is in play, which is worth surfacing in diagnostics.
  static Map<ReviewStage, int> get overrides => {
        for (final e in _resolved.entries)
          if (e.key.publishedDeadlineDay != e.value) e.key: e.value,
      };

  /// Adopt the server-resolved schedule. Ignores days outside 1–31 rather than
  /// trusting the payload blindly: a bad value here would land in user-facing
  /// copy and in every countdown.
  static void adopt(Map<ReviewStage, int> days) {
    _resolved = {
      for (final e in days.entries)
        if (e.value >= 1 && e.value <= 31) e.key: e.value,
    };
  }

  /// Back to the frozen table. For tests, and for a sign-out that might be
  /// followed by a sign-in against a different backend.
  static void reset() => _resolved = const {};

  /// The day [stage] is due: the server value if we have one, else the
  /// published table. Null only for the terminal stage.
  static int? dayFor(ReviewStage stage) =>
      _resolved[stage] ?? stage.publishedDeadlineDay;
}
