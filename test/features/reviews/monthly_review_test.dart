import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';
import 'package:vistar_app/features/reviews/data/models/incentive_snapshot.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review_summary.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/data/models/stage_record.dart';
import 'package:vistar_app/features/reviews/data/models/stage_status.dart';

/// Focused coverage for the derived state on [MonthlyReview]. The
/// aggregate is where per-stage progress, actionable role, and payout
/// math all live — those are the behaviours the UI relies on the most
/// and the easiest to break silently in a refactor.
void main() {
  MonthlyReview reviewAt(
    ReviewStage stage, {
    List<MonthlyKraRow>? rows,
    Map<ReviewStage, StageRecord>? records,
    IncentiveSnapshot? incentive,
    String? managerId,
  }) {
    return MonthlyReview(
      id: 'r1',
      employeeId: 'emp1',
      employeeName: 'Asha',
      managerId: managerId,
      period: const ReviewPeriod(2026, 6),
      currentStage: stage,
      stageRecords: records ?? const {},
      rows: rows ?? const [],
      incentive: incentive ?? const IncentiveSnapshot(),
    );
  }

  group('MonthlyReview.statusOf', () {
    test('a submitted stage (record present) reads as submitted', () {
      final r = reviewAt(
        ReviewStage.reportingManagerRating,
        records: {
          ReviewStage.selfRating: StageRecord(
            actorId: 'emp1',
            actorName: 'Asha',
            submittedAt: DateTime(2026, 6, 10),
          ),
        },
      );
      expect(r.statusOf(ReviewStage.selfRating), StageStatus.submitted);
    });

    test('the current stage reads as in-progress', () {
      final r = reviewAt(ReviewStage.reportingManagerRating);
      expect(
          r.statusOf(ReviewStage.reportingManagerRating),
          StageStatus.inProgress);
    });

    test('a future stage reads as pending', () {
      final r = reviewAt(ReviewStage.selfRating);
      expect(r.statusOf(ReviewStage.incentivePayout), StageStatus.pending);
    });

    test('the terminal completed stage reads as submitted once complete', () {
      final r = reviewAt(ReviewStage.completed);
      expect(r.statusOf(ReviewStage.completed), StageStatus.submitted);
    });

    test('a non-current stage without a record reads as pending, even '
        'when the review has moved past it (should never happen but is '
        'defensive)', () {
      final r = reviewAt(ReviewStage.incentivePayout);
      // No record for selfRating even though the review is 4 stages past.
      expect(r.statusOf(ReviewStage.selfRating), StageStatus.pending);
    });
  });

  // The two person-shaped rating stages are RELATIONSHIPS, not roles. EVERY
  // employee has a reporting manager — managers report to senior managers and
  // HR admins report to someone too — so who may act is decided by the review's
  // employeeId / managerId, never by the caller's role.
  group('MonthlyReview.isActionableBy — reporting-manager rating', () {
    test('the reporting manager can act whatever their OWN role is', () {
      final r = reviewAt(ReviewStage.reportingManagerRating, managerId: 'mgr1');
      expect(r.isActionableBy(UserRole.manager, userId: 'mgr1'), isTrue);
      // The case the old role gate wrongly rejected: an HR_ADMIN (or any other
      // role) who IS this employee's reporting manager.
      expect(r.isActionableBy(UserRole.hrAdmin, userId: 'mgr1'), isTrue);
      expect(r.isActionableBy(UserRole.employee, userId: 'mgr1'), isTrue);
    });

    test('a manager who is NOT this employee\'s reporting manager cannot act',
        () {
      final r = reviewAt(ReviewStage.reportingManagerRating, managerId: 'mgr1');
      expect(r.isActionableBy(UserRole.manager, userId: 'other-mgr'), isFalse);
    });

    test('fails closed when the employee has no manager mapped', () {
      final r = reviewAt(ReviewStage.reportingManagerRating); // managerId null
      expect(r.isActionableBy(UserRole.manager, userId: 'mgr1'), isFalse);
      expect(r.isActionableBy(UserRole.hrAdmin, userId: 'mgr1'), isFalse);
    });

    test('unresolvable without a userId', () {
      final r = reviewAt(ReviewStage.reportingManagerRating, managerId: 'mgr1');
      expect(r.isActionableBy(UserRole.manager), isFalse);
    });
  });

  group('MonthlyReview.isActionableBy — self rating', () {
    test('belongs to the review owner whatever their role', () {
      final r = reviewAt(ReviewStage.selfRating); // employeeId: emp1
      expect(r.isActionableBy(UserRole.employee, userId: 'emp1'), isTrue);
      // Managers and HR admins have their own KRA to self-rate; the old
      // {employee, ops} role gate locked them out of their own sheet.
      expect(r.isActionableBy(UserRole.manager, userId: 'emp1'), isTrue);
      expect(r.isActionableBy(UserRole.hrAdmin, userId: 'emp1'), isTrue);
    });

    test('nobody else can self-rate on your behalf', () {
      final r = reviewAt(ReviewStage.selfRating);
      expect(r.isActionableBy(UserRole.hrAdmin, userId: 'someone-else'),
          isFalse);
    });
  });

  group('MonthlyReview.isActionableBy — org-level stages stay role-gated', () {
    test('management review is for admin/HR-admin, not a relationship', () {
      final r = reviewAt(ReviewStage.managementReview, managerId: 'mgr1');
      expect(r.isActionableBy(UserRole.admin, userId: 'anyone'), isTrue);
      expect(r.isActionableBy(UserRole.hrAdmin, userId: 'anyone'), isTrue);
      // Being the reporting manager does NOT grant management review.
      expect(r.isActionableBy(UserRole.manager, userId: 'mgr1'), isFalse);
    });

    test('false on the terminal completed stage (no actor)', () {
      final r = reviewAt(ReviewStage.completed, managerId: 'mgr1');
      for (final role in UserRole.values) {
        expect(r.isActionableBy(role, userId: 'emp1'), isFalse,
            reason: '$role should not be able to act on a completed review');
        expect(r.isActionableBy(role, userId: 'mgr1'), isFalse,
            reason: '$role should not be able to act on a completed review');
      }
    });
  });

  group('MonthlyReview.weightedScorePct', () {
    const rows = [
      MonthlyKraRow(
          id: 'a', name: 'A', weightagePercent: 60, maxScore: 10),
      MonthlyKraRow(
          id: 'b', name: 'B', weightagePercent: 40, maxScore: 10),
    ];

    test('sums (value/max) × weight over rows with scores at the stage', () {
      final r = reviewAt(ReviewStage.selfRating, rows: [
        rows[0].withStageScore(
            ReviewStage.selfRating, const RowScore(value: 9)),
        rows[1].withStageScore(
            ReviewStage.selfRating, const RowScore(value: 5)),
      ]);
      // 60% × (9/10 × 100) + 40% × (5/10 × 100) = 54 + 20 = 74
      expect(r.weightedScorePct(ReviewStage.selfRating), closeTo(74, 1e-9));
    });

    test('drops rows without a score (or N/A) from both numerator and '
        'denominator so a partial rating doesn\'t under-count', () {
      final r = reviewAt(ReviewStage.selfRating, rows: [
        rows[0].withStageScore(
            ReviewStage.selfRating, const RowScore(value: 9)),
        // rows[1] has no score for selfRating.
      ]);
      // Only row A counts; 100% × (9/10 × 100) = 90
      expect(r.weightedScorePct(ReviewStage.selfRating), closeTo(90, 1e-9));
    });

    test('a N/A (value: null) row also drops out', () {
      final r = reviewAt(ReviewStage.selfRating, rows: [
        rows[0].withStageScore(
            ReviewStage.selfRating, const RowScore(value: 9)),
        rows[1].withStageScore(
            ReviewStage.selfRating, const RowScore(value: null)),
      ]);
      expect(r.weightedScorePct(ReviewStage.selfRating), closeTo(90, 1e-9));
    });

    test('returns 0 when no rows have a score for the stage', () {
      final r = reviewAt(ReviewStage.selfRating, rows: rows);
      expect(r.weightedScorePct(ReviewStage.selfRating), 0);
    });

    test('clamps to 100 even if scores exceed max (defensive)', () {
      final r = reviewAt(ReviewStage.selfRating, rows: [
        rows[0].withStageScore(
            ReviewStage.selfRating, const RowScore(value: 20)),
      ]);
      expect(r.weightedScorePct(ReviewStage.selfRating), 100);
    });
  });

  group('MonthlyReview derived display progress', () {
    const rows = [
      MonthlyKraRow(id: 'a', name: 'A', weightagePercent: 100, maxScore: 100),
    ];

    test('furthestScoredStage is null when nothing is scored', () {
      final r = reviewAt(ReviewStage.selfRating, rows: rows);
      expect(r.furthestScoredStage, isNull);
    });

    test('Yash case: every KRA reviewed but the cursor is frozen at selfRating '
        '(save-scores never advances it) — the display advances to Management '
        'Review as the pending next step', () {
      // Mirrors the live payload: currentStage SELF_RATING, but the (single)
      // KRA carries both a self and a reporting-manager (Review) score — so the
      // Review phase is complete and management is what's pending.
      final r = reviewAt(
        ReviewStage.selfRating,
        rows: [
          rows[0]
              .withStageScore(
                  ReviewStage.selfRating, const RowScore(value: 100))
              .withStageScore(
                  ReviewStage.reportingManagerRating,
                  const RowScore(value: 95)),
        ],
      );
      expect(r.furthestScoredStage, ReviewStage.reportingManagerRating);
      expect(r.reviewPhaseComplete, isTrue);
      expect(r.displayStage, ReviewStage.managementReview);
      expect(r.displayStatus, StageStatus.inProgress);
      // The summary the dashboard renders reflects it: Management Review
      // pending, with the Review average as the running score.
      final summary = MonthlyReviewSummary.fromReview(r);
      expect(summary.currentStage, ReviewStage.managementReview);
      expect(summary.currentStageStatus, StageStatus.inProgress);
      expect(summary.finalScorePct, closeTo(95, 1e-9));
    });

    test('a partly-reviewed sheet stays in the Review phase (in progress)', () {
      // Two KRAs, each owned by ONE reviewer: RM has rated theirs, Accounts
      // has NOT — the Review phase is not done, so it must not read as
      // "Management Review" (nor as submitted/green).
      final r = reviewAt(
        ReviewStage.selfRating,
        rows: [
          const MonthlyKraRow(
                  id: 'm',
                  name: 'M',
                  weightagePercent: 50,
                  maxScore: 100,
                  reviewerGroup: KraReviewer.reportingManager)
              .withStageScore(
                  ReviewStage.reportingManagerRating,
                  const RowScore(value: 90)),
          const MonthlyKraRow(
              id: 'a',
              name: 'A',
              weightagePercent: 50,
              maxScore: 100,
              reviewerGroup: KraReviewer.accounts),
        ],
      );
      expect(r.reviewPhaseComplete, isFalse);
      expect(r.displayStage.reviewCycle, 2); // still the Review phase
      expect(r.displayStatus, StageStatus.inProgress);
    });

    test('all assigned reviewers done → Management Review (pending)', () {
      final r = reviewAt(
        ReviewStage.selfRating,
        rows: [
          const MonthlyKraRow(
                  id: 'm',
                  name: 'M',
                  weightagePercent: 50,
                  maxScore: 100,
                  reviewerGroup: KraReviewer.reportingManager)
              .withStageScore(ReviewStage.reportingManagerRating,
                  const RowScore(value: 90)),
          const MonthlyKraRow(
                  id: 'a',
                  name: 'A',
                  weightagePercent: 50,
                  maxScore: 100,
                  reviewerGroup: KraReviewer.accounts)
              .withStageScore(
                  ReviewStage.financeRating, const RowScore(value: 100)),
        ],
      );
      expect(r.reviewPhaseComplete, isTrue);
      expect(r.displayStage, ReviewStage.managementReview);
      expect(r.displayStatus, StageStatus.inProgress);
    });

    test('once management scores, the stage reads Management Review (done)', () {
      final r = reviewAt(
        ReviewStage.selfRating,
        rows: [
          const MonthlyKraRow(
                  id: 'm',
                  name: 'M',
                  weightagePercent: 100,
                  maxScore: 100,
                  reviewerGroup: KraReviewer.reportingManager)
              .withStageScore(ReviewStage.reportingManagerRating,
                  const RowScore(value: 90))
              .withStageScore(
                  ReviewStage.managementReview, const RowScore(value: 80)),
        ],
      );
      expect(r.displayStage, ReviewStage.managementReview);
      expect(r.displayStatus, StageStatus.submitted);
    });

    test('with only self scored, display stage is self (submitted)', () {
      final r = reviewAt(
        ReviewStage.selfRating,
        rows: [
          rows[0].withStageScore(
              ReviewStage.selfRating, const RowScore(value: 80)),
        ],
      );
      expect(r.displayStage, ReviewStage.selfRating);
      expect(r.displayStatus, StageStatus.submitted);
    });

    test('respects a pipeline cursor that has advanced past the scores', () {
      // No scores anywhere, but the review is formally at management review.
      final r = reviewAt(ReviewStage.managementReview, rows: rows);
      expect(r.furthestScoredStage, isNull);
      expect(r.displayStage, ReviewStage.managementReview);
    });
  });

  group('MonthlyReview.finalScorePct', () {
    const rows = [
      MonthlyKraRow(
          id: 'a', name: 'A', weightagePercent: 100, maxScore: 10),
    ];

    test('prefers the reporting manager stage when it has any score', () {
      final r = reviewAt(
        ReviewStage.reportingManagerRating,
        rows: [
          rows[0]
              .withStageScore(
                  ReviewStage.selfRating, const RowScore(value: 5))
              .withStageScore(
                  ReviewStage.reportingManagerRating,
                  const RowScore(value: 9)),
        ],
      );
      expect(r.finalScorePct, closeTo(90, 1e-9));
    });

    test('falls back to account/HR when manager stage has no scores', () {
      final r = reviewAt(
        ReviewStage.reportingManagerRating,
        rows: [
          rows[0]
              .withStageScore(
                  ReviewStage.selfRating, const RowScore(value: 5))
              .withStageScore(
                  ReviewStage.accountHrRating, const RowScore(value: 8)),
        ],
      );
      expect(r.finalScorePct, closeTo(80, 1e-9));
    });

    test('falls back to self-rating when both later stages are empty', () {
      final r = reviewAt(
        ReviewStage.reportingManagerRating,
        rows: [
          rows[0].withStageScore(
              ReviewStage.selfRating, const RowScore(value: 5)),
        ],
      );
      expect(r.finalScorePct, closeTo(50, 1e-9));
    });

    test('returns 0 when nothing has been scored yet', () {
      final r = reviewAt(ReviewStage.selfRating, rows: rows);
      expect(r.finalScorePct, 0);
    });
  });

  group('MonthlyReview Review-cycle scoring', () {
    const rows = [
      MonthlyKraRow(id: 'a', name: 'A', weightagePercent: 100, maxScore: 10),
    ];

    test('reviewPctForRow averages whichever of RM/HR/Finance are present', () {
      // RM 100%, HR 80%, Finance 60% → mean 80%.
      final r = reviewAt(ReviewStage.reportingManagerRating, rows: [
        rows[0]
            .withStageScore(
                ReviewStage.reportingManagerRating, const RowScore(value: 10))
            .withStageScore(
                ReviewStage.accountHrRating, const RowScore(value: 8))
            .withStageScore(
                ReviewStage.financeRating, const RowScore(value: 6)),
      ]);
      expect(r.reviewPctForRow(r.rows.first), closeTo(80, 1e-9));
      expect(r.reviewWeightedPct, closeTo(80, 1e-9));
      expect(r.finalScorePct, closeTo(80, 1e-9));
    });

    test('a single Review rater present is the row average (no zero-fill)', () {
      final r = reviewAt(ReviewStage.reportingManagerRating, rows: [
        rows[0].withStageScore(
            ReviewStage.accountHrRating, const RowScore(value: 9)),
      ]);
      expect(r.reviewPctForRow(r.rows.first), closeTo(90, 1e-9));
    });

    test('reviewPctForRow is null until a Review rater scores the row', () {
      final r = reviewAt(ReviewStage.selfRating, rows: [
        rows[0]
            .withStageScore(ReviewStage.selfRating, const RowScore(value: 10)),
      ]);
      expect(r.reviewPctForRow(r.rows.first), isNull);
    });

    test('management override wins over the Review average as the final', () {
      final r = reviewAt(ReviewStage.managementReview, rows: [
        rows[0]
            .withStageScore(
                ReviewStage.reportingManagerRating, const RowScore(value: 10))
            .withStageScore(
                ReviewStage.accountHrRating, const RowScore(value: 10))
            .withStageScore(
                ReviewStage.managementReview, const RowScore(value: 5)),
      ]);
      // Review average would be 100%, but management reworked it to 50%.
      expect(r.reviewWeightedPct, closeTo(100, 1e-9));
      expect(r.finalScorePct, closeTo(50, 1e-9));
    });

    test('furthestScoredStage tracks self → RM → HR → Finance → management',
        () {
      final r = reviewAt(ReviewStage.selfRating, rows: [
        rows[0]
            .withStageScore(ReviewStage.selfRating, const RowScore(value: 10))
            .withStageScore(
                ReviewStage.financeRating, const RowScore(value: 8)),
      ]);
      expect(r.furthestScoredStage, ReviewStage.financeRating);
    });

    test('an ASSIGNED KRA uses only its reviewer, ignoring other raters', () {
      // KRA assigned to HR. HR rated 8/10; a stray RM rating must NOT blend in.
      final r = reviewAt(ReviewStage.reportingManagerRating, rows: [
        const MonthlyKraRow(
                id: 'a',
                name: 'A',
                weightagePercent: 100,
                maxScore: 10,
                reviewerGroup: KraReviewer.hr)
            .withStageScore(
                ReviewStage.reportingManagerRating, const RowScore(value: 10))
            .withStageScore(
                ReviewStage.accountHrRating, const RowScore(value: 8)),
      ]);
      expect(r.reviewPctForRow(r.rows.first), closeTo(80, 1e-9));
      expect(r.reviewWeightedPct, closeTo(80, 1e-9));
    });

    test('an ASSIGNED KRA is null until ITS reviewer scores it', () {
      // Assigned to Accounts, but only RM has scored → no Review score yet.
      final r = reviewAt(ReviewStage.reportingManagerRating, rows: [
        const MonthlyKraRow(
                id: 'a',
                name: 'A',
                weightagePercent: 100,
                maxScore: 10,
                reviewerGroup: KraReviewer.accounts)
            .withStageScore(
                ReviewStage.reportingManagerRating, const RowScore(value: 9)),
      ]);
      expect(r.reviewPctForRow(r.rows.first), isNull);
    });

    test('finalScorePct blends each KRA\'s OWN furthest stage (per-row)', () {
      // Regression: a partial management rework must not collapse Final onto
      // only the reworked KRAs. 2 KRAs, weight 50 each, max 10.
      //   A: self8 / RM9 / mgmt6  → final 60%
      //   B (assigned RM): self7 / RM8 / no mgmt → final 80%
      final r = reviewAt(ReviewStage.managementReview, rows: [
        const MonthlyKraRow(
                id: 'a',
                name: 'A',
                weightagePercent: 50,
                maxScore: 10,
                reviewerGroup: KraReviewer.reportingManager)
            .withStageScore(ReviewStage.selfRating, const RowScore(value: 8))
            .withStageScore(
                ReviewStage.reportingManagerRating, const RowScore(value: 9))
            .withStageScore(
                ReviewStage.managementReview, const RowScore(value: 6)),
        const MonthlyKraRow(
                id: 'b',
                name: 'B',
                weightagePercent: 50,
                maxScore: 10,
                reviewerGroup: KraReviewer.reportingManager)
            .withStageScore(ReviewStage.selfRating, const RowScore(value: 7))
            .withStageScore(
                ReviewStage.reportingManagerRating, const RowScore(value: 8)),
      ]);
      expect(r.finalPctForRow(r.rows[0]), closeTo(60, 1e-9));
      expect(r.finalPctForRow(r.rows[1]), closeTo(80, 1e-9));
      // (60×50 + 80×50) / 100 = 70 — NOT 60 (the old whole-review mgmt-only bug).
      expect(r.finalScorePct, closeTo(70, 1e-9));
    });

    test('finalScorePct blends reviewed rows with self-only rows', () {
      // A reviewed at 80%; B only self-rated at 60% → weighted 70%, no row dropped.
      final r = reviewAt(ReviewStage.reportingManagerRating, rows: [
        const MonthlyKraRow(
                id: 'a',
                name: 'A',
                weightagePercent: 50,
                maxScore: 10,
                reviewerGroup: KraReviewer.reportingManager)
            .withStageScore(
                ReviewStage.reportingManagerRating, const RowScore(value: 8)),
        const MonthlyKraRow(
                id: 'b',
                name: 'B',
                weightagePercent: 50,
                maxScore: 10,
                reviewerGroup: KraReviewer.hr)
            .withStageScore(ReviewStage.selfRating, const RowScore(value: 6)),
      ]);
      expect(r.finalScorePct, closeTo(70, 1e-9));
    });
  });

  group('MonthlyReview.projectedPayout', () {
    test('is eligibleAmount × finalScorePct / 100', () {
      final r = reviewAt(
        ReviewStage.reportingManagerRating,
        rows: [
          const MonthlyKraRow(
              id: 'a', name: 'A', weightagePercent: 100, maxScore: 10)
              .withStageScore(
                  ReviewStage.reportingManagerRating,
                  const RowScore(value: 7)),
        ],
        incentive: const IncentiveSnapshot(eligibleAmount: 10000),
      );
      // 70% of ₹10 000 = ₹7 000
      expect(r.projectedPayout, closeTo(7000, 1e-9));
    });

    test('is 0 when nothing has been scored', () {
      final r = reviewAt(
        ReviewStage.selfRating,
        incentive: const IncentiveSnapshot(eligibleAmount: 10000),
      );
      expect(r.projectedPayout, 0);
    });
  });

  group('MonthlyReview.isComplete', () {
    test('true only on the terminal stage', () {
      expect(reviewAt(ReviewStage.completed).isComplete, isTrue);
      for (final s in ReviewStage.values.where((s) => !s.isTerminal)) {
        expect(reviewAt(s).isComplete, isFalse,
            reason: '$s should not read as complete');
      }
    });
  });

  group('IncentiveSnapshot.computedPayable', () {
    test('returns null until computedScorePct is set', () {
      const snap = IncentiveSnapshot(eligibleAmount: 5000);
      expect(snap.computedPayable, isNull);
    });

    test('is amount × pct / 100 once the score lands', () {
      const snap = IncentiveSnapshot(
          eligibleAmount: 5000, computedScorePct: 82);
      expect(snap.computedPayable, closeTo(4100, 1e-9));
    });
  });
}
