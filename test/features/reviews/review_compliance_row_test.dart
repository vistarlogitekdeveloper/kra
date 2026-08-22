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

    test('a cursor past Self-Rating ALSO counts — so the report is right on a '
        'backend that still auto-advances instead of showing everyone as '
        'not submitted', () {
      final r = ReviewComplianceRow.from(review(
        rows: [row(id: '1', reviewer: KraReviewer.reportingManager)],
        stage: ReviewStage.reportingManagerRating,
      ));
      expect(r.selfSubmitted, isTrue);
    });

    test('scores alone are not submission — a half-filled sheet is not done',
        () {
      final r = ReviewComplianceRow.from(review(
        rows: [
          row(id: '1', reviewer: KraReviewer.reportingManager, selfValue: 80)
        ],
      ));
      expect(r.selfSubmitted, isFalse);
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

    test('partial work is No, not Yes — a reviewer who did 1 of 2 still owes '
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

    test('no KRA for that reviewer is NOT APPLICABLE, not No — reporting "No" '
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

    test('Ops Excellence reports notTracked — the app assigns no KRA to it', () {
      final r = ReviewComplianceRow.from(review(
        rows: [row(id: '1', reviewer: KraReviewer.hr, reviewerValue: 90)],
      ));
      expect(r.byOpsExcellence, ReviewerProgress.notTracked);
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
          row(id: '1', reviewer: KraReviewer.hr, reviewerValue: 90, mgmtValue: 88)
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
