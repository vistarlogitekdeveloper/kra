import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/employee/data/models/enums.dart';
import 'package:vistar_app/features/manager/data/models/manager_review_detail.dart';
import 'package:vistar_app/features/manager/data/models/monthly_score.dart';
import 'package:vistar_app/features/manager/data/models/review_permissions.dart';
import 'package:vistar_app/features/manager/data/models/review_row.dart';
import 'package:vistar_app/features/manager/data/models/review_totals.dart';
import 'package:vistar_app/features/manager/presentation/providers/manager_rate_providers.dart';

/// A manager must never be required to rate a month that has not finished.
///
/// Reported behaviour: every month of a cycle is seeded `OPEN`, and
/// `MonthlyScore.isEditable` only asked whether the month was OPEN and
/// applicable — it knew about HR's LOCKED flag and nothing about the calendar.
/// So through September the September column was editable AND counted as
/// required: submit stayed disabled on "Incomplete scores" until the manager
/// invented a rating for a month with twenty days left, the footer read
/// "0 of 9" when only 6 cells could legitimately be filled, and that
/// fabricated number was POSTed and reached the incentive. Nothing on the
/// server rejected it — `updateScores` checks LOCKED only.
///
/// The clock is 5 September 2026 throughout: July and August have ended,
/// September has not.
void main() {
  final now = DateTime(2026, 9, 5);

  MonthlyScore cell({
    required int month,
    double? rating,
    bool isNotApplicable = false,
    ReviewMonthStatus status = ReviewMonthStatus.open,
    bool withDate = true,
  }) =>
      MonthlyScore(
        monthlyScoreId: 'c$month-${rating ?? 'x'}',
        monthId: 'm$month',
        monthLabel: 'M$month',
        monthStatus: status,
        monthDate: withDate ? DateTime(2026, month, 1) : null,
        managerRating: rating,
        isNotApplicable: isNotApplicable,
      );

  ManagerReviewMonth monthCol(int m) => ManagerReviewMonth(
        id: 'm$m',
        monthLabel: 'M$m',
        monthDate: DateTime(2026, m, 1),
        status: ReviewMonthStatus.open,
      );

  ManagerRateState stateWith(
    List<MonthlyScore> cells, {
    List<int> cycleMonths = const [7, 8, 9],
  }) =>
      ManagerRateState(
        clock: now,
        reviewId: 'r1',
        review: ManagerReviewDetail(
          id: 'r1',
          state: ReviewState.draft,
          employee: const ManagerReviewEmployee(
            id: 'e1',
            name: 'Asha',
            employeeCode: 'VLPL0001',
          ),
          cycle: ManagerReviewCycle(
            id: 'c1',
            name: 'Q2',
            months: [for (final m in cycleMonths) monthCol(m)],
          ),
          rows: [
            ReviewRow(
              assignmentItemId: 'a1',
              name: 'Safety',
              weightage: 1,
              maxScore: 10,
              scoreSource: ScoreSource.manager,
              sortOrder: 0,
              monthlyScores: cells,
            ),
          ],
          totals: const ReviewTotals(),
          permissions: const ReviewPermissions(canRate: true, canEdit: false),
        ),
      );

  group('MonthlyScore.isRatableOn', () {
    test('an ended month is ratable', () {
      expect(cell(month: 8).isRatableOn(now), isTrue);
      expect(cell(month: 7).isRatableOn(now), isTrue);
    });

    test('the LIVE month is not — this is the reported bug', () {
      expect(cell(month: 9).isRatableOn(now), isFalse,
          reason: 'September has not finished on 5 September');
    });

    test('an HR-locked month stays unratable even though it has ended', () {
      expect(
        cell(month: 8, status: ReviewMonthStatus.locked).isRatableOn(now),
        isFalse,
      );
    });

    test('an N/A cell is never ratable', () {
      expect(cell(month: 8, isNotApplicable: true).isRatableOn(now), isFalse);
    });

    test('a cell with no month date is refused, not assumed open', () {
      // Failing closed is deliberate: a cell whose month cannot be identified
      // must not be scored. Fixtures without a date make assertions vacuous,
      // which is why the shared helper always supplies one.
      expect(cell(month: 8, withDate: false).isRatableOn(now), isFalse);
    });
  });

  group('copyWith must carry monthDate', () {
    test('editing a cell does not strip its month', () {
      // copyWith runs on every keystroke. Dropping monthDate would null the
      // date on first edit and isRatableOn would then refuse the cell,
      // locking the manager out of the matrix entirely.
      final edited = cell(month: 8).copyWith(managerRating: 7.0);
      expect(edited.monthDate, isNotNull);
      expect(edited.isRatableOn(now), isTrue);
      expect(edited.managerRating, 7.0);
    });
  });

  group('isComplete counts only what can be rated today', () {
    test('true with the two ended months rated and the live one empty', () {
      // The whole point: September being blank must not block submit.
      final s = stateWith([
        cell(month: 7, rating: 8),
        cell(month: 8, rating: 7),
        cell(month: 9),
      ]);
      expect(s.isComplete, isTrue);
    });

    test('false while an ENDED month is still missing', () {
      final s = stateWith([
        cell(month: 7, rating: 8),
        cell(month: 8),
        cell(month: 9),
      ]);
      expect(s.isComplete, isFalse);
    });

    test('NOT vacuously true when nothing is ratable yet', () {
      // Early in a cycle no month has ended. "Every ratable cell is rated" is
      // trivially true of an empty set, which would enable submit on a review
      // with no scores at all.
      final s = stateWith(
        [cell(month: 12), cell(month: 11)],
        cycleMonths: [11, 12],
      );
      expect(s.isComplete, isFalse);
    });
  });

  group('the submit CTA waits for the whole quarter', () {
    test('quarterEnded is false while the last month is still running', () {
      final s = stateWith([cell(month: 7, rating: 8)]);
      expect(s.quarterEnded, isFalse,
          reason: 'the cycle runs to September, which has not ended');
    });

    test('and true once it has', () {
      final s = stateWith([cell(month: 7, rating: 8)], cycleMonths: [5, 6, 7]);
      expect(s.quarterEnded, isTrue);
    });

    test('submitOpensOn is the 1st of the month after the cycle ends', () {
      final s = stateWith([cell(month: 7, rating: 8)]);
      expect(s.submitOpensOn, DateTime(2026, 10, 1));
    });

    test('and is null once the quarter has ended — nothing to wait for', () {
      final s = stateWith([cell(month: 7, rating: 8)], cycleMonths: [5, 6, 7]);
      expect(s.submitOpensOn, isNull);
    });

    test('a cycle ending in December rolls into January', () {
      final s = stateWith(
        [cell(month: 7, rating: 8)],
        cycleMonths: [10, 11, 12],
      );
      expect(s.submitOpensOn, DateTime(2027, 1, 1));
    });

    test('a cycle with no months does not block submit forever', () {
      // Failing closed here would strand a review nobody could ever finish.
      final s = stateWith([cell(month: 7, rating: 8)], cycleMonths: []);
      expect(s.quarterEnded, isTrue);
      expect(s.submitOpensOn, isNull);
    });
  });
}
