import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/constants/feature_flags.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';
import 'package:vistar_app/features/reviews/data/models/incentive_snapshot.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review_summary.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/stage_status.dart';

/// The dashboard reaches for [MonthlyReviewSummary.needsActionBy] on
/// every row it renders to decide the "needs your action" badge. That
/// predicate is deceptively subtle — it has to consider stage, status,
/// AND role. Missing any of the three quietly under- or over-badges the
/// dashboard.
void main() {
  MonthlyReviewSummary summary({
    required ReviewStage stage,
    StageStatus status = StageStatus.inProgress,
    String? managerId,
    PayoutStatus payoutStatus = PayoutStatus.pending,
    double? selfScorePct,
    double? managementReviewPct,
    double finalScorePct = 0,
    String employeeId = 'emp1',
  }) {
    return MonthlyReviewSummary(
      id: 'r1',
      employeeId: employeeId,
      employeeName: 'Asha',
      employeeCode: 'VIS-1',
      managerId: managerId,
      year: 2026,
      month: 6,
      monthLabel: 'June 2026',
      currentStage: stage,
      currentStageStatus: status,
      finalScorePct: finalScorePct,
      payoutStatus: payoutStatus,
      selfScorePct: selfScorePct,
      managementReviewPct: managementReviewPct,
    );
  }

  // The two person-shaped rating stages badge off a RELATIONSHIP, not a role:
  // every employee has a reporting manager (managers and HR admins included),
  // so the badge follows employeeId / managerId, not the caller's role.
  group('MonthlyReviewSummary.needsActionBy — relationship stages', () {
    // These fixtures carry a self score because the badge resolves against
    // displayStage: a cursor sitting at the manager's stage is only credible once
    // the self-rating that advanced it exists. Without one the review is treated
    // as never started and belongs to the employee — covered separately below.
    test('reporting-manager rating badges for the reporting manager, '
        'whatever their own role', () {
      final s = summary(
        stage: ReviewStage.reportingManagerRating,
        managerId: 'mgr1',
        selfScorePct: 70,
      );
      expect(s.needsActionBy(UserRole.manager, userId: 'mgr1'), isTrue);
      // An HR_ADMIN who IS the reporting manager — previously role-blocked.
      expect(s.needsActionBy(UserRole.hrAdmin, userId: 'mgr1'), isTrue);
    });

    test('reporting-manager rating does not badge for anyone else', () {
      final s = summary(
        stage: ReviewStage.reportingManagerRating,
        managerId: 'mgr1',
        selfScorePct: 70,
      );
      expect(s.needsActionBy(UserRole.manager, userId: 'other-mgr'), isFalse);
      expect(s.needsActionBy(UserRole.employee, userId: 'emp1'), isFalse);
      expect(s.needsActionBy(UserRole.finance, userId: 'fin1'), isFalse);
    });

    test('reporting-manager rating fails closed with no manager mapped', () {
      final s = summary(
        stage: ReviewStage.reportingManagerRating,
        selfScorePct: 70,
      );
      expect(s.needsActionBy(UserRole.manager, userId: 'mgr1'), isFalse);
    });

    test('self rating badges only for the owner, whatever their role', () {
      final s = summary(stage: ReviewStage.selfRating);
      expect(s.needsActionBy(UserRole.employee, userId: 'emp1'), isTrue);
      // Managers/HR admins self-rate their own KRA too.
      expect(s.needsActionBy(UserRole.manager, userId: 'emp1'), isTrue);
      expect(s.needsActionBy(UserRole.hrAdmin, userId: 'emp1'), isTrue);
      expect(s.needsActionBy(UserRole.employee, userId: 'other'), isFalse);
    });
  });

  group('MonthlyReviewSummary.needsActionBy — status/terminal', () {
    test('false once the stage has been submitted (badge should clear)', () {
      final s = summary(
        stage: ReviewStage.reportingManagerRating,
        status: StageStatus.submitted,
        managerId: 'mgr1',
      );
      expect(s.needsActionBy(UserRole.manager, userId: 'mgr1'), isFalse);
    });

    test('false on the terminal completed stage for every role', () {
      final s = summary(
        stage: ReviewStage.completed,
        status: StageStatus.submitted,
        managerId: 'mgr1',
      );
      for (final role in UserRole.values) {
        expect(s.needsActionBy(role, userId: 'mgr1'), isFalse,
            reason: 'completed reviews should never badge — $role');
      }
    });
  });

  group('MonthlyReviewSummary payout / mark-paid', () {
    test('Accounts can mark paid once the management review is done', () {
      final s = summary(
        stage: ReviewStage.managementReview,
        status: StageStatus.submitted,
      );
      expect(s.managementReviewDone, isTrue);
      expect(s.canMarkPaidBy(UserRole.finance), isTrue);
      // HR / HR-admin are payout actors too.
      expect(s.canMarkPaidBy(UserRole.hr), isTrue);
      expect(s.canMarkPaidBy(UserRole.hrAdmin), isTrue);
    });

    test('not markable before the management review is done', () {
      // Review phase still in progress → management not done → no payout yet.
      final s = summary(
        stage: ReviewStage.reportingManagerRating,
        status: StageStatus.inProgress,
      );
      expect(s.managementReviewDone, isFalse);
      expect(s.canMarkPaidBy(UserRole.finance), isFalse);
    });

    test('a manager or employee can never mark paid', () {
      final s = summary(
        stage: ReviewStage.managementReview,
        status: StageStatus.submitted,
      );
      expect(s.canMarkPaidBy(UserRole.manager), isFalse);
      expect(s.canMarkPaidBy(UserRole.employee), isFalse);
    });

    test('already-paid reviews show as paid and are not markable again', () {
      final s = summary(
        stage: ReviewStage.completed,
        status: StageStatus.submitted,
        payoutStatus: PayoutStatus.paid,
      );
      expect(s.payoutPaid, isTrue);
      expect(s.canMarkPaidBy(UserRole.finance), isFalse);
    });
  });

  // The dashboard chip reads [displayStage]/[displayStatus], which repair a
  // stage cursor that in-place score saves left frozen at Self-Rating — while
  // NEVER regressing (or over-riding) a cursor the backend already advanced.
  group('MonthlyReviewSummary.displayStage — scores repair a frozen cursor', () {
    test('cursor stuck at Self-Rating but management scored → Management '
        'Review (submitted)', () {
      final s = summary(
        stage: ReviewStage.selfRating,
        status: StageStatus.inProgress,
        selfScorePct: 85,
        managementReviewPct: 90,
      );
      expect(s.displayStage, ReviewStage.managementReview);
      expect(s.displayStatus, StageStatus.submitted);
    });

    test('cursor at Self-Rating with only a self score → Self-Rating, but '
        'submitted (self is in)', () {
      final s = summary(
        stage: ReviewStage.selfRating,
        status: StageStatus.inProgress,
        selfScorePct: 70,
      );
      expect(s.displayStage, ReviewStage.selfRating);
      expect(s.displayStatus, StageStatus.submitted);
    });

    test('nothing scored yet → the cursor stage and its own status', () {
      final s = summary(
        stage: ReviewStage.selfRating,
        status: StageStatus.inProgress,
      );
      expect(s.displayStage, ReviewStage.selfRating);
      expect(s.displayStatus, StageStatus.inProgress);
    });

    test('a cursor already advanced past Self-Rating is authoritative — a '
        'partial Review average never bumps it to Management Review', () {
      final s = summary(
        stage: ReviewStage.reportingManagerRating,
        status: StageStatus.inProgress,
        selfScorePct: 80,
        managementReviewPct: 88, // Review average, management not done yet
      );
      expect(s.displayStage, ReviewStage.reportingManagerRating);
      expect(s.displayStatus, StageStatus.inProgress);
    });

    test('a completed / paid review shows Completed (submitted)', () {
      // Carries scores, as a genuinely completed review must: reaching payout
      // requires the management sign-off, which leaves a score behind. The
      // score-less variant of this fixture was not a state the pipeline can
      // produce, and asserting on it is what let "Completed · Paid · 0%" over
      // an empty sheet look correct — see the payout-flag group below.
      final s = summary(
        stage: ReviewStage.completed,
        status: StageStatus.submitted,
        payoutStatus: PayoutStatus.paid,
        selfScorePct: 82,
        managementReviewPct: 85,
        finalScorePct: 85,
      );
      expect(s.displayStage, ReviewStage.completed);
      expect(s.displayStatus, StageStatus.submitted);
    });
  });

  // The monthly dashboard opens on the newest month worth showing rather than
  // blindly on the current calendar month — otherwise, early in a month, every
  // row reads "Self-Rating / 0%" and the whole quarter looks like it never
  // started (which is exactly how a manager misread a real review as untouched
  // while HR's quarter-aggregated dashboard showed it mid-pipeline).
  // A stale payout flag on a review nobody ever rated used to render as
  // "Completed · Paid · 0%" on the team list, while the KRA sheet behind it was
  // completely empty — it read as an incentive already paid out for work that
  // was never assessed. Payout is bookkeeping, not evidence of a rating.
  group('MonthlyReviewSummary — a payout flag is not proof of a rating', () {
    test('paid with NO scores anywhere does not read as Completed or settled',
        () {
      final s = summary(
        stage: ReviewStage.selfRating,
        status: StageStatus.inProgress,
        payoutStatus: PayoutStatus.paid,
      );
      expect(s.hasAnyScore, isFalse);
      expect(s.displayStage, ReviewStage.selfRating);
      expect(s.displayStatus, StageStatus.inProgress);
      expect(s.payoutSettled, isFalse, reason: 'no Paid badge without a score');
      // The raw flag is untouched — the incentive report still sees it.
      expect(s.payoutPaid, isTrue);
    });

    test('paid with NO scores is not counted as rating activity', () {
      final s = summary(
        stage: ReviewStage.selfRating,
        payoutStatus: PayoutStatus.paid,
      );
      expect(s.hasRatingActivity, isFalse,
          reason: 'routing through displayStatus made this circular');
    });

    test('a stale COMPLETED cursor with no scores is refused, not echoed', () {
      // The row's status columns outlived its score rows. Echoing the cursor
      // put "Completed" in green over a sheet with nothing in a single cell.
      final s = summary(
        stage: ReviewStage.completed,
        status: StageStatus.submitted,
        payoutStatus: PayoutStatus.paid,
      );
      expect(s.displayStage, ReviewStage.selfRating);
      expect(s.displayStatus, StageStatus.inProgress);
      expect(s.payoutSettled, isFalse);
    });

    test('a MID-PIPELINE cursor with no scores is refused too — this is how the '
        'quarter dashboard read "Management Review · 0%" while the monthly list '
        'correctly read Self-Rating', () {
      // The pipeline only advances off the back of a score: save-scores moves the
      // cursor to REPORTING_MANAGER_RATING *because* self scores landed, and the
      // server only surfaces MANAGEMENT_REVIEW once every KRA has been scored by
      // its assigned reviewer. So either cursor with zero scores means the header
      // outlived its score rows.
      for (final stage in [
        ReviewStage.reportingManagerRating,
        ReviewStage.accountHrRating,
        ReviewStage.financeRating,
        ReviewStage.managementReview,
      ]) {
        final s = summary(stage: stage, status: StageStatus.submitted);
        expect(s.displayStage, ReviewStage.selfRating,
            reason: '$stage with no score must not claim progress');
        expect(s.displayStatus, StageStatus.inProgress, reason: '$stage');
      }
    });

    test('the needs-action badge follows the SHOWN stage, not the stale cursor',
        () {
      // A header stuck at MANAGEMENT_REVIEW with nothing scored used to badge
      // every HR admin with "needs your action", while the chip on the same row
      // read Self-Rating — the badge and the chip disagreeing about one review.
      final s = summary(
        stage: ReviewStage.managementReview,
        employeeId: 'emp1',
        managerId: 'mgr1',
      );
      expect(s.displayStage, ReviewStage.selfRating);
      expect(s.needsActionBy(UserRole.hrAdmin, userId: 'hr1'), isFalse);
      expect(s.needsActionBy(UserRole.admin, userId: 'boss1'), isFalse);
      expect(s.needsActionBy(UserRole.management, userId: 'boss1'), isFalse);
      // It belongs to the employee, which is what the chip now says.
      expect(s.needsActionBy(UserRole.employee, userId: 'emp1'), isTrue);
    });

    test('a REAL management review still badges the management tier', () {
      final s = summary(
        stage: ReviewStage.managementReview,
        selfScorePct: 80,
        managementReviewPct: 84,
        finalScorePct: 84,
      );
      expect(s.displayStage, ReviewStage.managementReview);
      expect(s.needsActionBy(UserRole.management, userId: 'boss1'), isTrue);
    });

    test('a mid-pipeline cursor WITH a score is trusted — awaiting the manager '
        'after a self-rating is the normal state', () {
      final s = summary(
        stage: ReviewStage.reportingManagerRating,
        status: StageStatus.inProgress,
        selfScorePct: 74,
      );
      expect(s.displayStage, ReviewStage.reportingManagerRating);
    });

    test('a genuinely completed review with scores is unaffected', () {
      final s = summary(
        stage: ReviewStage.completed,
        status: StageStatus.submitted,
        payoutStatus: PayoutStatus.paid,
        selfScorePct: 88,
        managementReviewPct: 91,
        finalScorePct: 91,
      );
      expect(s.displayStage, ReviewStage.completed);
      expect(s.displayStatus, StageStatus.submitted);
      expect(s.payoutSettled, isTrue);
    });

    test('paid WITH a score still reads as Completed and settled', () {
      final s = summary(
        stage: ReviewStage.selfRating,
        payoutStatus: PayoutStatus.paid,
        selfScorePct: 80,
        finalScorePct: 76,
      );
      expect(s.displayStage, ReviewStage.completed);
      expect(s.displayStatus, StageStatus.submitted);
      expect(s.payoutSettled, isTrue);
    });

    test('a genuine ZERO score is not mistaken for never-rated — the employee '
        'self-rated 0, which is a real assessment', () {
      final s = summary(
        stage: ReviewStage.selfRating,
        payoutStatus: PayoutStatus.paid,
        selfScorePct: 0,
        finalScorePct: 0,
      );
      expect(s.hasAnyScore, isTrue);
      expect(s.payoutSettled, isTrue);
      expect(s.displayStage, ReviewStage.completed);
    });
  });

  group('MonthlyReviewSummary.hasRatingActivity — has this month started?', () {
    test('a freshly generated month with nothing rated has no activity', () {
      expect(summary(stage: ReviewStage.selfRating).hasRatingActivity, isFalse);
    });

    test('a saved self-rating counts as activity', () {
      final s = summary(stage: ReviewStage.selfRating, selfScorePct: 70);
      expect(s.hasRatingActivity, isTrue);
    });

    test('a non-zero agreed score counts, even with the cursor at Self-Rating',
        () {
      final s = summary(stage: ReviewStage.selfRating, finalScorePct: 96);
      expect(s.hasRatingActivity, isTrue);
    });

    test('any stage past Self-Rating counts', () {
      final s = summary(stage: ReviewStage.reportingManagerRating);
      expect(s.hasRatingActivity, isTrue);
    });

    test('a completed / paid month counts', () {
      final s = summary(
        stage: ReviewStage.completed,
        status: StageStatus.submitted,
        payoutStatus: PayoutStatus.paid,
      );
      expect(s.hasRatingActivity, isTrue);
    });
  });

  group('MonthlyReviewSummary.anyWorthLanding — which month to open on', () {
    test('an untouched month is not worth landing on for a manager', () {
      final rows = [summary(stage: ReviewStage.selfRating, managerId: 'mgr1')];
      expect(
        MonthlyReviewSummary.anyWorthLanding(rows,
            roles: {UserRole.manager}, userId: 'mgr1'),
        isFalse,
      );
    });

    test('an untouched month IS worth landing on for the employee who still '
        'owes the self-rating — never skip past their pending work', () {
      final rows = [summary(stage: ReviewStage.selfRating)];
      expect(
        MonthlyReviewSummary.anyWorthLanding(rows,
            roles: {UserRole.employee}, userId: 'emp1'),
        isTrue,
      );
    });

    test('one rated row makes the month worth landing on for everybody', () {
      final rows = [
        summary(stage: ReviewStage.selfRating, employeeId: 'emp1'),
        summary(stage: ReviewStage.managementReview, employeeId: 'emp2'),
      ];
      expect(
        MonthlyReviewSummary.anyWorthLanding(rows,
            roles: {UserRole.manager}, userId: 'mgr1'),
        isTrue,
      );
    });

    test('a month with no reviews at all is never worth landing on', () {
      expect(
        MonthlyReviewSummary.anyWorthLanding(const [],
            roles: {UserRole.hrAdmin}, userId: 'hr1'),
        isFalse,
      );
    });
  });

  group('MonthlyReviewSummary.needsActionBy — org-level stages', () {
    test('still light up for exactly the roles agreed in the pipeline spec, '
        'independent of any reporting relationship', () {
      const table = <ReviewStage, Set<UserRole>>{
        // HR and Finance are now SEPARATE Review raters.
        ReviewStage.accountHrRating: {
          UserRole.hr,
          UserRole.hrAdmin,
        },
        // HR_ADMIN holds the Accounts seat too — one UserRole can't say
        // "HR Admin AND Accounts", and that post covers both.
        ReviewStage.financeRating: {UserRole.finance, UserRole.hrAdmin},
        // Management approval/override. MANAGEMENT is the intended holder;
        // HR_ADMIN is here only until the backend's employees enum can store
        // MANAGEMENT, at which point it drops out. See ReviewStage.actorRoles.
        ReviewStage.managementReview: {
          UserRole.management,
          // HR_ADMIN shares the seat only while the backend cannot store
          // MANAGEMENT — see FeatureFlags.roleTiers.
          if (!FeatureFlags.roleTiers) UserRole.hrAdmin,
        },
        ReviewStage.incentivePayout: {
          UserRole.finance,
          UserRole.hr,
          UserRole.hrAdmin,
        },
      };
      for (final entry in table.entries) {
        // managerId set + a userId that is NOT it: org stages must ignore both.
        // Scores present so the cursor is credible — the badge resolves against
        // displayStage, and an org stage with nothing scored is treated as never
        // started (see the payout-flag group).
        final s = summary(
          stage: entry.key,
          managerId: 'mgr1',
          selfScorePct: 70,
          managementReviewPct: 75,
        );
        for (final role in UserRole.values) {
          final shouldBadge = entry.value.contains(role);
          expect(
            s.needsActionBy(role, userId: 'somebody-else'),
            shouldBadge,
            reason:
                '${entry.key.name} for role $role — expected $shouldBadge',
          );
        }
      }
    });
  });
}
