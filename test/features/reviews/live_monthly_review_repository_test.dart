import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/row_score.dart';
import 'package:vistar_app/features/reviews/data/models/stage_status.dart';
import 'package:vistar_app/features/reviews/data/repositories/live_monthly_review_repository.dart';

void main() {
  final now = DateTime(2026, 7, 3);

  // Stand-in for the live backend roster — the repo has NO hardcoded
  // employees of its own.
  List<RosterEntry> roster() => const [
        RosterEntry(
          id: 'e-101',
          name: 'Real Employee One',
          code: 'VLPL0101',
          grade: 'E1',
          managerId: 'mgr-1',
          managerName: 'Real Manager',
          eligibleAmount: 8000,
        ),
        RosterEntry(
          id: 'e-102',
          name: 'Real Employee Two',
          code: 'VLPL0102',
          grade: 'M1',
          managerId: 'mgr-1',
          managerName: 'Real Manager',
          eligibleAmount: 12000,
        ),
      ];

  LiveMonthlyReviewRepository repo({List<RosterEntry> Function()? r}) =>
      LiveMonthlyReviewRepository(
        loadRoster: () async => (r ?? roster)(),
        clock: () => now,
      );

  group('roster materialisation', () {
    test('lists a review per real employee, at Self-Rating', () async {
      final list = await repo().listMonthlyReviews(year: 2026, month: 7);
      expect(list, hasLength(2));
      expect(list.map((s) => s.employeeName),
          containsAll(['Real Employee One', 'Real Employee Two']));
      expect(list.every((s) => s.currentStage == ReviewStage.selfRating), isTrue);
      // Real incentive ceiling carried onto the summary.
      final one = list.firstWhere((s) => s.employeeCode == 'VLPL0101');
      expect(one.incentiveEligibleAmount, 8000);
    });

    test('an empty roster yields an empty dashboard', () async {
      final list = await repo(r: () => const [])
          .listMonthlyReviews(year: 2026, month: 7);
      expect(list, isEmpty);
    });

    test('review id is period-scoped to the employee', () async {
      final r = repo();
      await r.listMonthlyReviews(year: 2026, month: 7);
      final review = await r.getReview('2026-07-e-101');
      expect(review.employeeName, 'Real Employee One');
      expect(review.eligibleAmount, 8000);
      expect(review.rows, isNotEmpty); // KRA template applied
    });
  });

  group('read scoping (cross-user leak)', () {
    test('reads are scoped to the caller roster, not the whole store',
        () async {
      // The store is process-wide and outlives logout. Simulate an HR
      // (org-wide) session followed by an employee session on the SAME repo
      // instance: loadRoster returns whoever the current caller should see.
      var current = roster(); // HR: sees both employees
      final r = LiveMonthlyReviewRepository(
        loadRoster: () async => current,
        clock: () => now,
      );
      final hrView = await r.listMonthlyReviews(year: 2026, month: 7);
      expect(hrView, hasLength(2)); // store now holds both e-101 and e-102

      // Now an employee logs in — roster narrows to just themselves.
      current = const [
        RosterEntry(id: 'e-101', name: 'Real Employee One', code: 'VLPL0101'),
      ];
      final empView = await r.listMonthlyReviews(year: 2026, month: 7);
      expect(empView, hasLength(1));
      expect(empView.single.employeeId, 'e-101'); // must NOT see e-102
    });
  });

  group('pipeline persists in-session', () {
    test('submitting self-rating advances and sticks across a refresh',
        () async {
      final r = repo();
      await r.listMonthlyReviews(year: 2026, month: 7);
      const id = '2026-07-e-101';
      final before = await r.getReview(id);

      await r.submitStage(
        id,
        ReviewStage.selfRating,
        rowScores: {
          for (final row in before.rows) row.id: const RowScore(value: 8),
        },
        actorId: 'e-101',
        actorName: 'Real Employee One',
      );

      // A re-list must NOT reset the advanced review back to Self-Rating.
      await r.listMonthlyReviews(year: 2026, month: 7);
      final after = await r.getReview(id);
      expect(after.currentStage, ReviewStage.accountHrRating);
      expect(after.statusOf(ReviewStage.selfRating), StageStatus.submitted);
      expect(after.rows.first.scoreFor(ReviewStage.selfRating)?.value, 8);
    });
  });
}
