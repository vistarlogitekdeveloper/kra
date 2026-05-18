import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/employee/data/models/enums.dart';
import 'package:vistar_app/features/manager/data/models/manager_review_detail.dart';
import 'package:vistar_app/features/manager/data/models/monthly_score.dart';
import 'package:vistar_app/features/manager/data/models/review_permissions.dart';
import 'package:vistar_app/features/manager/data/models/review_row.dart';
import 'package:vistar_app/features/manager/data/models/review_totals.dart';
import 'package:vistar_app/features/manager/presentation/providers/manager_rate_providers.dart';

/// Targeted tests for the pure-data invariants on [ManagerRateState].
/// The notifier itself is harder to test in isolation (Riverpod + Dio
/// dependencies) — these focus on the math that drives the matrix
/// footer and submit gate, where regressions would silently corrupt
/// the user-visible totals.
void main() {
  group('ManagerRateState.isComplete', () {
    test('false when review is null', () {
      const s = ManagerRateState();
      expect(s.isComplete, isFalse);
    });

    test('true when every MANAGER-editable cell is rated', () {
      final review = _review(rows: [
        _row(
          weightage: 0.5,
          source: ScoreSource.manager,
          cells: [
            _cell(rating: 8.0),
            _cell(rating: 7.0),
          ],
        ),
        _row(
          weightage: 0.5,
          source: ScoreSource.self,
          cells: [
            _cell(rating: 9.0),
            _cell(rating: 6.0),
          ],
        ),
      ]);
      final state = ManagerRateState(review: review, reviewId: 'r1');
      expect(state.isComplete, isTrue);
    });

    test('false when any MANAGER cell is missing a rating', () {
      final review = _review(rows: [
        _row(cells: [_cell(rating: 8.0), _cell(rating: null)]),
      ]);
      final state = ManagerRateState(review: review, reviewId: 'r1');
      expect(state.isComplete, isFalse);
    });

    test('skips FEED rows from the completeness check', () {
      // FEED rows are read-only — Ops/Finance feed populates them, so
      // they shouldn't gate the manager's submit.
      final review = _review(rows: [
        _row(
          source: ScoreSource.feed,
          cells: [_cell(rating: null)],
        ),
        _row(
          source: ScoreSource.manager,
          cells: [_cell(rating: 8.0)],
        ),
      ]);
      final state = ManagerRateState(review: review, reviewId: 'r1');
      expect(state.isComplete, isTrue);
    });

    test('skips N/A cells from the completeness check', () {
      final review = _review(rows: [
        _row(cells: [
          _cell(rating: 8.0),
          _cell(rating: null, isNotApplicable: true),
        ]),
      ]);
      final state = ManagerRateState(review: review, reviewId: 'r1');
      expect(state.isComplete, isTrue);
    });

    test('skips non-OPEN cells from the completeness check', () {
      final review = _review(rows: [
        _row(cells: [
          _cell(rating: 8.0),
          _cell(rating: null, status: ReviewMonthStatus.locked),
        ]),
      ]);
      final state = ManagerRateState(review: review, reviewId: 'r1');
      expect(state.isComplete, isTrue);
    });
  });

  group('ManagerRateState.weightedTotalPct', () {
    test('returns 0 when review is null', () {
      const s = ManagerRateState();
      expect(s.weightedTotalPct, 0);
    });

    test('returns 0 when no cells filled', () {
      final review = _review(rows: [
        _row(cells: [_cell(rating: null), _cell(rating: null)]),
      ]);
      final s = ManagerRateState(review: review, reviewId: 'r1');
      expect(s.weightedTotalPct, 0);
    });

    test('full marks → 100', () {
      // 1 row, weight 0.5 (= 50%), 2 cells × 10/10 → normalised 100.
      final review = _review(rows: [
        _row(
          weightage: 0.5,
          maxScore: 10,
          cells: [_cell(rating: 10.0), _cell(rating: 10.0)],
        ),
      ]);
      final s = ManagerRateState(review: review, reviewId: 'r1');
      expect(s.weightedTotalPct, closeTo(100, 0.01));
    });

    test('half marks → 50', () {
      final review = _review(rows: [
        _row(
          weightage: 1.0,
          maxScore: 10,
          cells: [_cell(rating: 5.0), _cell(rating: 5.0)],
        ),
      ]);
      final s = ManagerRateState(review: review, reviewId: 'r1');
      expect(s.weightedTotalPct, closeTo(50, 0.01));
    });

    test('excludes N/A cells from denominator', () {
      // If one cell is N/A and the other is 10/10, the row should
      // still report 100% — N/A is "doesn't count", not "zero".
      final review = _review(rows: [
        _row(
          weightage: 1.0,
          maxScore: 10,
          cells: [
            _cell(rating: 10.0),
            _cell(rating: null, isNotApplicable: true),
          ],
        ),
      ]);
      final s = ManagerRateState(review: review, reviewId: 'r1');
      expect(s.weightedTotalPct, closeTo(100, 0.01));
    });

    test('clamps to 0-100 range', () {
      // Pathological case: rating > maxScore. We don't validate at
      // this layer (the cell widget does), so just confirm we never
      // emit > 100 or < 0 from the math.
      final review = _review(rows: [
        _row(
          weightage: 1.0,
          maxScore: 10,
          cells: [_cell(rating: 100.0)],
        ),
      ]);
      final s = ManagerRateState(review: review, reviewId: 'r1');
      expect(s.weightedTotalPct, lessThanOrEqualTo(100.0));
      expect(s.weightedTotalPct, greaterThanOrEqualTo(0.0));
    });
  });

  group('ManagerRateState.copyWith', () {
    test('preserves untouched fields', () {
      const s = ManagerRateState(
        reviewId: 'r1',
        mode: ManagerRateMode.edit,
        managerComment: 'hello',
        isSubmitting: true,
      );
      final c = s.copyWith(isSubmitting: false);
      expect(c.reviewId, 'r1');
      expect(c.mode, ManagerRateMode.edit);
      expect(c.managerComment, 'hello');
      expect(c.isSubmitting, isFalse);
    });

    test('can clear lastSavedAt via explicit null', () {
      final t = DateTime(2026, 5, 14);
      final s = ManagerRateState(lastSavedAt: t);
      final c = s.copyWith(lastSavedAt: null);
      expect(c.lastSavedAt, isNull);
    });
  });
}

// ─── Test fixture helpers ──────────────────────────────────────────────

ManagerReviewDetail _review({required List<ReviewRow> rows}) {
  return ManagerReviewDetail(
    id: 'r1',
    state: ReviewState.employeeSubmittedAll,
    employee: const ManagerReviewEmployee(
      id: 'e1',
      name: 'Test Employee',
      employeeCode: 'VLPL0001',
    ),
    cycle: const ManagerReviewCycle(
      id: 'c1',
      name: 'FY26 Q1',
      months: [],
    ),
    rows: rows,
    totals: const ReviewTotals(),
    permissions: const ReviewPermissions(canRate: true, canEdit: false),
  );
}

ReviewRow _row({
  double weightage = 0.5,
  double maxScore = 10,
  ScoreSource source = ScoreSource.manager,
  List<MonthlyScore>? cells,
}) {
  return ReviewRow(
    assignmentItemId: 'a1',
    name: 'Test KRA',
    weightage: weightage,
    maxScore: maxScore,
    scoreSource: source,
    sortOrder: 0,
    monthlyScores: cells ?? [_cell()],
  );
}

MonthlyScore _cell({
  ReviewMonthStatus status = ReviewMonthStatus.open,
  bool isNotApplicable = false,
  double? rating,
}) {
  return MonthlyScore(
    monthlyScoreId: 'cell-${rating ?? "null"}-${isNotApplicable ? "na" : "ok"}',
    monthId: 'm-1',
    monthLabel: 'May',
    monthStatus: status,
    isNotApplicable: isNotApplicable,
    managerRating: rating,
  );
}
