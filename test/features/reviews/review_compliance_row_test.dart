import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/core/enums/kra_reviewer.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_compliance_row.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/data/models/stage_record.dart';

/// The compliance report is a chase-list: HR acts on it. A wrong "Yes" means
/// nobody chases work that is actually outstanding, and a wrong "No" sends
/// someone after work that does not exist — so the derivation is worth pinning.
void main() {
  MonthlyKraRow row({
    required String id,
    required KraReviewer reviewer,
    double? selfValue,
    double? reviewerValue,
    double? mgmtValue,
  }) {
    return MonthlyKraRow(
      id: id,
      name: 'KRA $id',
      weightagePercent: 25,
      maxScore: 100,
      displayOrder: 0,
      reviewerGroup: reviewer,
      stageScores: {
        if (selfValue != null)
          ReviewStage.selfRating: RowScore(value: selfValue),
        if (reviewerValue != null)
          _stageOf(reviewer): RowScore(value: reviewerValue),
        if (mgmtValue != null)
          ReviewStage.managementReview: RowScore(value: mgmtValue),
      },
    );
  }

  MonthlyReview review({
    required List<MonthlyKraRow> rows,
    ReviewStage stage = ReviewStage.selfRating,
    Map<ReviewStage, StageRecord>? records,
    DateTime? managementLockedAt,
  }) {
    return MonthlyReview(
      id: 'r1',
      employeeId: 'emp1',
      employeeName: 'Asha',
      employeeCode: 'VIS-1',
      period: const ReviewPeriod(2026, 8),
      currentStage: stage,
      rows: rows,
      stageRecords: records ?? const {},
      managementLockedAt: managementLockedAt,
    );
  }

  StageRecord record() => StageRecord(
        actorId: 'emp1',
        actorName: 'Asha',
        submittedAt: DateTime.utc(2026, 8, 11),
      );

  group('self-rating status', () {
    test('a Self-Rating stage record means submitted', () {
      final r = ReviewComplianceRow.from(review(
        rows: [row(id: '1', reviewer: KraReviewer.reportingManager)],
        records: {ReviewStage.selfRating: record()},
      ));
      expect(r.selfSubmitted, isTrue);
    });

    test(
        'every KRA carrying a self score counts — that is what a finished '
        'rating looks like when the backend advances the cursor on save '
        'without writing a stage record', () {
      final r = ReviewComplianceRow.from(review(
        rows: [
          row(id: '1', reviewer: KraReviewer.reportingManager, selfValue: 80),
          row(id: '2', reviewer: KraReviewer.hr, selfValue: 60),
        ],
      ));
      expect(r.selfSubmitted, isTrue);
    });

    test('a cursor past Self-Rating is NOT proof on its own', () {
      // The stored stage can outrun the work — the same mismatch that makes
      // dashboards elsewhere resolve through displayStage rather than the raw
      // cursor. Trusting it here reported "Submitted" for employees who had
      // rated nothing, which is the one thing a chase-list must not get wrong.
      final r = ReviewComplianceRow.from(review(
        rows: [row(id: '1', reviewer: KraReviewer.reportingManager)],
        stage: ReviewStage.reportingManagerRating,
      ));
      expect(r.selfSubmitted, isFalse);
    });

    test('a partly-rated sheet is not submitted', () {
      final r = ReviewComplianceRow.from(review(
        rows: [
          row(id: '1', reviewer: KraReviewer.reportingManager, selfValue: 80),
          row(id: '2', reviewer: KraReviewer.hr), // never rated
        ],
      ));
      expect(r.selfSubmitted, isFalse);
    });

    test('an explicit stage record still wins over missing scores', () {
      // Submit is the employee's own declaration that they are done; honour it
      // even if a row carries no score (an unrated KRA they chose to leave).
      final r = ReviewComplianceRow.from(review(
        rows: [
          row(id: '1', reviewer: KraReviewer.reportingManager),
          row(id: '2', reviewer: KraReviewer.hr),
        ],
        records: {ReviewStage.selfRating: record()},
      ));
      expect(r.selfSubmitted, isTrue);
    });
  });

  group('per-reviewer progress', () {
    test('Yes only when EVERY KRA that reviewer owns is scored', () {
      final r = ReviewComplianceRow.from(review(
        rows: [
          row(
              id: '1',
              reviewer: KraReviewer.reportingManager,
              reviewerValue: 70),
          row(
              id: '2',
              reviewer: KraReviewer.reportingManager,
              reviewerValue: 60),
        ],
      ));
      expect(r.byReportingManager, ReviewerProgress.yes);
    });

    test(
        'partial work is No, not Yes — a reviewer who did 1 of 2 still owes '
        'the other', () {
      final r = ReviewComplianceRow.from(review(
        rows: [
          row(
              id: '1',
              reviewer: KraReviewer.reportingManager,
              reviewerValue: 70),
          row(id: '2', reviewer: KraReviewer.reportingManager),
        ],
      ));
      expect(r.byReportingManager, ReviewerProgress.no);
    });

    test(
        'no KRA for that reviewer is NOT APPLICABLE, not No — reporting "No" '
        'would send them chasing work that does not exist', () {
      final r = ReviewComplianceRow.from(review(
        rows: [
          row(
              id: '1',
              reviewer: KraReviewer.reportingManager,
              reviewerValue: 70)
        ],
      ));
      expect(r.byHr, ReviewerProgress.notApplicable);
      expect(r.byFinance, ReviewerProgress.notApplicable);
    });

    test('each reviewer is judged only on their OWN KRAs', () {
      final r = ReviewComplianceRow.from(review(
        rows: [
          row(id: '1', reviewer: KraReviewer.hr, reviewerValue: 90),
          row(id: '2', reviewer: KraReviewer.accounts),
        ],
      ));
      expect(r.byHr, ReviewerProgress.yes);
      expect(r.byFinance, ReviewerProgress.no);
    });

    test('a zero score still counts as reviewed — rating 0 is a rating', () {
      final r = ReviewComplianceRow.from(review(
        rows: [row(id: '1', reviewer: KraReviewer.hr, reviewerValue: 0)],
      ));
      expect(r.byHr, ReviewerProgress.yes);
    });

    test('Ops Excellence reports notTracked — the app assigns no KRA to it',
        () {
      final r = ReviewComplianceRow.from(review(
        rows: [row(id: '1', reviewer: KraReviewer.hr, reviewerValue: 90)],
      ));
      expect(r.byOpsExcellence, ReviewerProgress.notTracked);
    });
  });

  group('a KRA with no assigned reviewer', () {
    // The KRA sheet defaults an unassigned KRA to the reporting manager. This
    // report used to leave it unowned, so a review whose rows predate per-KRA
    // assignment showed N/A in all three reviewer columns — the report saying
    // there was nothing to do, beside a sheet showing every KRA awaiting the
    // manager. Two screens, opposite answers, same data.
    MonthlyKraRow unassigned({double? reviewerValue}) => MonthlyKraRow(
          id: 'u1',
          name: 'Legacy KRA',
          weightagePercent: 100,
          maxScore: 100,
          displayOrder: 0,
          // reviewerGroup left null, as a legacy row arrives
          stageScores: {
            if (reviewerValue != null)
              ReviewStage.reportingManagerRating:
                  RowScore(value: reviewerValue),
          },
        );

    test('belongs to the reporting manager, not to nobody', () {
      final r = ReviewComplianceRow.from(review(rows: [unassigned()]));
      expect(r.byReportingManager, ReviewerProgress.no);
      expect(r.byHr, ReviewerProgress.notApplicable);
      expect(r.byFinance, ReviewerProgress.notApplicable);
    });

    test('and is satisfied when the manager rates it', () {
      final r = ReviewComplianceRow.from(
          review(rows: [unassigned(reviewerValue: 70)]));
      expect(r.byReportingManager, ReviewerProgress.yes);
    });
  });

  group('final approval', () {
    test('true once management has locked the review', () {
      final r = ReviewComplianceRow.from(review(
        rows: [row(id: '1', reviewer: KraReviewer.hr, reviewerValue: 90)],
        managementLockedAt: DateTime.utc(2026, 8, 11),
      ));
      expect(r.finalApproval, isTrue);
    });

    test('true once management has scored anything', () {
      final r = ReviewComplianceRow.from(review(
        rows: [
          row(
              id: '1',
              reviewer: KraReviewer.hr,
              reviewerValue: 90,
              mgmtValue: 88)
        ],
      ));
      expect(r.finalApproval, isTrue);
    });

    test('false while the Review cycle is still running', () {
      final r = ReviewComplianceRow.from(review(
        rows: [row(id: '1', reviewer: KraReviewer.hr, reviewerValue: 90)],
        stage: ReviewStage.accountHrRating,
      ));
      expect(r.finalApproval, isFalse);
    });
  });

  test('untouched flags a sheet nobody has started, for the chase-list', () {
    final nothing = ReviewComplianceRow.from(review(
      rows: [row(id: '1', reviewer: KraReviewer.hr)],
    ));
    expect(nothing.untouched, isTrue);

    final started = ReviewComplianceRow.from(review(
      rows: [row(id: '1', reviewer: KraReviewer.hr, reviewerValue: 50)],
    ));
    expect(started.untouched, isFalse);
  });
}

ReviewStage _stageOf(KraReviewer r) {
  switch (r) {
    case KraReviewer.reportingManager:
      return ReviewStage.reportingManagerRating;
    case KraReviewer.hr:
      return ReviewStage.accountHrRating;
    case KraReviewer.accounts:
      return ReviewStage.financeRating;
  }
}
