import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/reviews/data/models/incentive_snapshot.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/data/models/stage_record.dart';
import 'package:vistar_app/features/reviews/data/models/stage_status.dart';

/// Pins the JSON wire contract every monthly-review model round-trips
/// through toJson → fromJson without loss.
void main() {
  group('ReviewPeriod', () {
    test('key round-trips through parse', () {
      const p = ReviewPeriod(2026, 6);
      expect(p.key, '2026-06');
      expect(ReviewPeriod.parse(p.key), p);
    });
  });

  group('ReviewStage / StageStatus / PayoutStatus wire forms', () {
    test('every stage round-trips through toApiString/fromApi', () {
      for (final s in ReviewStage.values) {
        expect(ReviewStage.fromApi(s.toApiString()), s);
      }
    });

    test('stage status + payout status round-trip', () {
      for (final s in StageStatus.values) {
        expect(StageStatus.fromApi(s.toApiString()), s);
      }
      for (final p in PayoutStatus.values) {
        expect(PayoutStatus.fromApi(p.toApiString()), p);
      }
    });
  });

  group('MonthlyKraRow', () {
    test('round-trips with per-stage scores', () {
      final row = const MonthlyKraRow(
        id: 'k1',
        name: 'Revenue',
        category: 'Sales',
        weightagePercent: 40,
        maxScore: 10,
        displayOrder: 0,
        target: '5L',
      )
          .withStageScore(
            ReviewStage.selfRating,
            const RowScore(value: 8, remark: 'hit target'),
          )
          .withStageScore(
            ReviewStage.reportingManagerRating,
            const RowScore(value: 7),
          );

      final back = MonthlyKraRow.fromJson(row.toJson());
      expect(back.id, 'k1');
      expect(back.weightagePercent, 40);
      expect(back.displayOrder, 0);
      expect(back.scoreFor(ReviewStage.selfRating)?.value, 8);
      expect(back.scoreFor(ReviewStage.selfRating)?.remark, 'hit target');
      expect(back.scoreFor(ReviewStage.reportingManagerRating)?.value, 7);
      expect(back.scoreFor(ReviewStage.accountHrRating), isNull);
    });
  });

  group('MonthlyReview', () {
    test('round-trips with rows, stage records, and incentive', () {
      final review = MonthlyReview(
        id: 'r1',
        employeeId: 'emp1',
        employeeName: 'Asha',
        employeeCode: 'VIS-1',
        grade: 'E1',
        managerId: 'm1',
        managerName: 'Manish',
        period: const ReviewPeriod(2026, 6),
        currentStage: ReviewStage.reportingManagerRating,
        stageRecords: {
          ReviewStage.selfRating: StageRecord(
            actorId: 'emp1',
            actorName: 'Asha',
            submittedAt: DateTime(2026, 6, 10),
            comment: 'done',
          ),
        },
        rows: [
          const MonthlyKraRow(
            id: 'k1',
            name: 'Revenue',
            weightagePercent: 100,
            maxScore: 10,
          ).withStageScore(ReviewStage.selfRating, const RowScore(value: 9)),
        ],
        incentive: const IncentiveSnapshot(eligibleAmount: 5000),
      );

      final back = MonthlyReview.fromJson(review.toJson());
      expect(back.id, 'r1');
      expect(back.employeeId, 'emp1');
      expect(back.period, const ReviewPeriod(2026, 6));
      expect(back.currentStage, ReviewStage.reportingManagerRating);
      // A submitted stage keeps its record; the current stage derives as
      // in-progress from the record's absence.
      expect(back.recordFor(ReviewStage.selfRating), isNotNull);
      expect(back.statusOf(ReviewStage.selfRating), StageStatus.submitted);
      expect(back.recordFor(ReviewStage.selfRating)!.submittedAt,
          DateTime(2026, 6, 10));
      expect(back.statusOf(ReviewStage.reportingManagerRating),
          StageStatus.inProgress);
      expect(back.rows.single.scoreFor(ReviewStage.selfRating)?.value, 9);
      expect(back.eligibleAmount, 5000);
      // finalScorePct uses self (the only rated stage): 9/10 × 100 = 90.
      expect(back.finalScorePct, closeTo(90, 1e-9));
    });

    test(
        'tolerates string-decimal amounts, a period object, and legacy '
        'payout tokens', () {
      final back = MonthlyReview.fromJson({
        'id': 'r2',
        'employeeId': 'e',
        'employeeName': 'X',
        'year': 2026,
        'month': 5,
        'currentStage': 'INCENTIVE_PAYOUT',
        'eligibleAmount': '7000.00',
        'payoutStatus': 'READY', // legacy token → pending
        'rows': const [],
      });
      expect(back.period, const ReviewPeriod(2026, 5));
      expect(back.eligibleAmount, 7000);
      expect(back.currentStage, ReviewStage.incentivePayout);
      expect(back.payoutStatus, PayoutStatus.pending);
    });
  });
}
