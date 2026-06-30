import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_kra_row.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/repositories/mock_monthly_review_repository.dart';
import 'package:vistar_app/features/reviews/data/repositories/monthly_review_repository.dart';

void main() {
  // Fixed clock so the seeded periods are deterministic.
  final now = DateTime(2026, 6, 22);
  const current = ReviewPeriod(2026, 6);

  MockMonthlyReviewRepository repo() => MockMonthlyReviewRepository(now: now);

  group('MockMonthlyReviewRepository seeding + scoping', () {
    test('exposes current + previous month', () async {
      final periods = await repo().availablePeriods();
      expect(periods.map((p) => p.key), containsAll(['2026-06', '2026-05']));
      // newest first
      expect(periods.first.key, '2026-06');
    });

    test('employee sees only their own review', () async {
      final list = await repo().listForMonth(
        period: current,
        scope: const ReviewScope(userId: 'emp1', role: UserRole.employee),
      );
      expect(list, hasLength(1));
      expect(list.single.employeeId, 'emp1');
    });

    test('manager sees their whole team', () async {
      final list = await repo().listForMonth(
        period: current,
        scope: const ReviewScope(userId: 'm1', role: UserRole.manager),
      );
      expect(
          list.map((r) => r.employeeId), containsAll(['emp1', 'emp2', 'emp3']));
    });

    test('HR sees the whole org', () async {
      final list = await repo().listForMonth(
        period: current,
        scope: const ReviewScope(userId: 'hrx', role: UserRole.hr),
      );
      expect(list, hasLength(3));
    });
  });

  group('MockMonthlyReviewRepository state machine', () {
    test('submitting self-rating advances to Account & HR', () async {
      final r = repo();
      const id = '2026-06-emp1'; // seeded at selfRating
      final before = await r.getReview(id);
      expect(before.currentStage, ReviewStage.selfRating);

      final after = await r.submitStage(
        reviewId: id,
        stage: ReviewStage.selfRating,
        actor: const ReviewScope(userId: 'emp1', role: UserRole.employee),
        rowScores: {
          for (final row in before.rows)
            row.id: const RowScore(value: 8, remark: 'ok'),
        },
      );
      expect(after.currentStage, ReviewStage.accountHrRating);
      expect(after.recordFor(ReviewStage.selfRating).status, StageStatus.done);
      // Scores were applied.
      expect(after.rows.first.scoreFor(ReviewStage.selfRating)?.value, 8);
    });

    test('submitting the wrong stage throws', () async {
      final r = repo();
      expect(
        () => r.submitStage(
          reviewId: '2026-06-emp1',
          stage: ReviewStage.managementReview,
          actor: const ReviewScope(userId: 'x', role: UserRole.admin),
        ),
        throwsStateError,
      );
    });

    test('management "return" sends it back to reporting manager', () async {
      final r = repo();
      // Drive emp2 (seeded at reportingManagerRating) forward to management.
      const id = '2026-06-emp2';
      var rev = await r.getReview(id);
      expect(rev.currentStage, ReviewStage.reportingManagerRating);
      rev = await r.submitStage(
        reviewId: id,
        stage: ReviewStage.reportingManagerRating,
        actor: const ReviewScope(userId: 'm1', role: UserRole.manager),
        rowScores: {
          for (final row in rev.rows) row.id: const RowScore(value: 7)
        },
      );
      expect(rev.currentStage, ReviewStage.managementReview);

      final returned = await r.submitStage(
        reviewId: id,
        stage: ReviewStage.managementReview,
        actor: const ReviewScope(userId: 'a1', role: UserRole.admin),
        decision: StageDecision.returnForRework,
        comment: 'Please revisit row 2',
      );
      expect(returned.currentStage, ReviewStage.reportingManagerRating);
    });

    test('markPaid completes the review', () async {
      final r = repo();
      const id = '2026-06-emp3'; // seeded at incentivePayout
      final paid = await r.markPaid(
        reviewId: id,
        actor: const ReviewScope(userId: 'f1', role: UserRole.finance),
      );
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
      // emp3 current month is fully scored through manager stage.
      final rev = await r.getReview('2026-06-emp3');
      expect(rev.finalScorePct, greaterThan(0));
      expect(rev.projectedPayout,
          closeTo(rev.eligibleAmount * rev.finalScorePct / 100, 1e-9));
    });
  });
}
