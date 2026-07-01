import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/reviews/data/models/incentive_snapshot.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/data/models/stage_status.dart';
import 'package:vistar_app/features/reviews/data/repositories/mock_monthly_review_repository.dart';

void main() {
  // Fixed clock so the seeded periods/ids are deterministic.
  final now = DateTime(2026, 6, 22);
  MockMonthlyReviewRepository repo() => MockMonthlyReviewRepository(now: now);

  group('MockMonthlyReviewRepository seeding + scoping', () {
    test('seeds both the current and previous month', () async {
      final r = repo();
      final current = await r.listMonthlyReviews(year: 2026, month: 6);
      final previous = await r.listMonthlyReviews(year: 2026, month: 5);
      expect(current, hasLength(3));
      expect(previous, hasLength(3));
    });

    test('employee scope sees only their own review', () async {
      final list = await repo().listMonthlyReviews(
        year: 2026,
        month: 6,
        scopeEmployeeId: 'emp1',
      );
      expect(list, hasLength(1));
      expect(list.single.employeeId, 'emp1');
    });

    test('manager scope sees their whole team', () async {
      final list = await repo().listMonthlyReviews(
        year: 2026,
        month: 6,
        scopeManagerId: MockMonthlyReviewRepository.demoManagerId,
      );
      expect(
          list.map((r) => r.employeeId), containsAll(['emp1', 'emp2', 'emp3']));
    });

    test('unscoped (HR/org) sees everyone', () async {
      final list = await repo().listMonthlyReviews(year: 2026, month: 6);
      expect(list, hasLength(3));
    });

    test('currentStage filter narrows to a single stage', () async {
      final list = await repo().listMonthlyReviews(
        year: 2026,
        month: 6,
        currentStage: ReviewStage.incentivePayout,
      );
      expect(list, hasLength(1));
      expect(list.single.currentStage, ReviewStage.incentivePayout);
    });
  });

  group('MockMonthlyReviewRepository state machine', () {
    test('submitting self-rating advances to Account & HR', () async {
      final r = repo();
      const id = '2026-06-emp1'; // seeded at selfRating
      final before = await r.getReview(id);
      expect(before.currentStage, ReviewStage.selfRating);

      final after = await r.submitStage(
        id,
        ReviewStage.selfRating,
        rowScores: {
          for (final row in before.rows)
            row.id: const RowScore(value: 8, remark: 'ok'),
        },
        actorId: 'emp1',
        actorName: 'Asha',
      );
      expect(after.currentStage, ReviewStage.accountHrRating);
      expect(after.statusOf(ReviewStage.selfRating), StageStatus.submitted);
      expect(after.rows.first.scoreFor(ReviewStage.selfRating)?.value, 8);
    });

    test('submitting the wrong stage throws', () async {
      final r = repo();
      expect(
        () => r.submitStage(
          '2026-06-emp1',
          ReviewStage.managementReview,
          actorId: 'x',
          actorName: 'Admin',
        ),
        throwsStateError,
      );
    });

    test('management "return" sends it back to reporting manager', () async {
      final r = repo();
      const id = '2026-06-emp2'; // seeded at reportingManagerRating
      var rev = await r.getReview(id);
      expect(rev.currentStage, ReviewStage.reportingManagerRating);
      rev = await r.submitStage(
        id,
        ReviewStage.reportingManagerRating,
        rowScores: {
          for (final row in rev.rows) row.id: const RowScore(value: 7),
        },
        actorId: 'm1',
        actorName: 'Manish',
      );
      expect(rev.currentStage, ReviewStage.managementReview);

      final returned = await r.submitStage(
        id,
        ReviewStage.managementReview,
        approved: false,
        comment: 'Please revisit row 2',
        actorId: 'a1',
        actorName: 'Admin',
      );
      expect(returned.currentStage, ReviewStage.reportingManagerRating);
      // The manager stage re-opens (its record was cleared).
      expect(returned.statusOf(ReviewStage.reportingManagerRating),
          StageStatus.inProgress);
    });

    test('markPaid completes the review', () async {
      final r = repo();
      const id = '2026-06-emp3'; // seeded at incentivePayout
      final paid = await r.markPaid(id, actorId: 'f1', actorName: 'Finance');
      expect(paid.currentStage, ReviewStage.completed);
      expect(paid.payoutStatus, PayoutStatus.paid);
      expect(paid.isComplete, isTrue);
      expect(paid.paidAt, isNotNull);
    });
  });

  group('MonthlyReview score math', () {
    test('finalScorePct uses the furthest rating stage and weights rows',
        () async {
      final r = repo();
      // emp3 current month is scored through the manager stage.
      final rev = await r.getReview('2026-06-emp3');
      expect(rev.finalScorePct, greaterThan(0));
      expect(rev.projectedPayout,
          closeTo(rev.eligibleAmount * rev.finalScorePct / 100, 1e-9));
    });
  });
}
