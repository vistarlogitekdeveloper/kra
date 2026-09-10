import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review_summary.dart';

/// The employee's job designation on the Monthly Reviews list.
///
/// It lives in the backend's `employees.position` column — the value HR picks
/// on the employee form, already exposed elsewhere as `Employee.position`. The
/// monthly-review queries simply never selected it, so it never reached the
/// list.
///
/// The client is deliberately tolerant here: the card renders the line only
/// when a non-empty value arrives, so the app is safe to deploy before or
/// after the API patch (docs/install_review_designation.mjs). These pin that
/// tolerance, because "renders nothing" and "renders null" look identical in a
/// screenshot and only one of them is correct.
void main() {
  Map<String, dynamic> base() => {
        'id': 'r1',
        'employeeId': 'e1',
        'employeeName': 'Dinesh Dnyaneshwar Gawade',
        'employeeCode': 'VLPL0156',
        'year': 2026,
        'month': 8,
      };

  group('parsing', () {
    test('reads employeeDesignation, the name the summary endpoint uses', () {
      final s = MonthlyReviewSummary.fromJson(
        base()..['employeeDesignation'] = 'Cluster Manager',
      );
      expect(s.employeeDesignation, 'Cluster Manager');
    });

    test('falls back to position, the raw column name', () {
      // Anything serialising an employee row directly still calls it
      // `position`; it is the same value and must not be dropped.
      final s = MonthlyReviewSummary.fromJson(
          base()..['position'] = 'Sr. Accountant');
      expect(s.employeeDesignation, 'Sr. Accountant');
    });

    test('and to employeePosition', () {
      final s = MonthlyReviewSummary.fromJson(
        base()..['employeePosition'] = 'Warehouse Manager',
      );
      expect(s.employeeDesignation, 'Warehouse Manager');
    });

    test('employeeDesignation wins when more than one shape is present', () {
      final s = MonthlyReviewSummary.fromJson(base()
        ..['employeeDesignation'] = 'Cluster Manager'
        ..['position'] = 'stale');
      expect(s.employeeDesignation, 'Cluster Manager');
    });
  });

  group('absence is null, never a placeholder', () {
    test('null when the API has not shipped the field', () {
      // The state of every deployment until the server patch lands. The card
      // must render no line at all, so this has to be null rather than ''.
      final s = MonthlyReviewSummary.fromJson(base());
      expect(s.employeeDesignation, isNull);
    });

    test('null when the employee genuinely has no position set', () {
      // `position` is nullable in the schema and plenty of employees have
      // none — a normal state, not an error.
      final s =
          MonthlyReviewSummary.fromJson(base()..['employeeDesignation'] = null);
      expect(s.employeeDesignation, isNull);
    });

    test('an all-whitespace value renders nothing', () {
      // The card guards on `.trim().isNotEmpty`, so a stray "  " must not
      // reserve a blank line and shove the stage pill out of alignment with
      // the neighbouring cards.
      final s = MonthlyReviewSummary.fromJson(
        base()..['employeeDesignation'] = '   ',
      );
      expect((s.employeeDesignation ?? '').trim(), isEmpty);
    });
  });

  group('it does not disturb the fields already on the card', () {
    test('name and code still parse', () {
      final s = MonthlyReviewSummary.fromJson(
        base()..['employeeDesignation'] = 'Cluster Manager',
      );
      expect(s.employeeName, 'Dinesh Dnyaneshwar Gawade');
      expect(s.employeeCode, 'VLPL0156');
    });

    test('grade is a separate field and is not overwritten', () {
      // Grade ("E1", "M1") and designation ("Cluster Manager") are different
      // things; an earlier reading of this request assumed they were the same.
      final s = MonthlyReviewSummary.fromJson(base()
        ..['employeeGrade'] = 'M1'
        ..['employeeDesignation'] = 'Cluster Manager');
      expect(s.employeeGrade, 'M1');
      expect(s.employeeDesignation, 'Cluster Manager');
    });
  });
}
