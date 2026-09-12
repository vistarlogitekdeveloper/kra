import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review_summary.dart';

/// The project location shown beside the employee's name on the Monthly
/// Reviews list — "Yash Thikekar - HO".
///
/// The value comes from `kra.project_locations.name`, joined into
/// `listSummaries` and serialised by `toSummary` as `projectLocation`. It was
/// already arriving; the list card simply did not render it.
///
/// The shape is the risk. `JsonParse.parseString` falls back to
/// `value.toString()`, so an object payload read without a guard puts a literal
/// `{id: loc_x, name: HO}` on the card — which is precisely the bug the manager
/// module's `TeamMember` already had to fix (see
/// `manager_team_live_contract_test.dart`, which asserts the parsed value
/// `isNot(contains('{'))`). Both modules describe the same column, and payload
/// shapes in this backend have drifted between flat and nested before, so this
/// pins both forms rather than assuming today's one is permanent.
void main() {
  Map<String, dynamic> base() => {
        'id': 'r1',
        'employeeId': 'e1',
        'employeeName': 'Yash Thikekar',
        'employeeCode': 'VLPL0156',
        'year': 2026,
        'month': 8,
      };

  group('the shape the API actually sends today', () {
    test('a flat string reads directly', () {
      final s = MonthlyReviewSummary.fromJson(
        base()..['projectLocation'] = 'HO',
      );
      expect(s.projectLocation, 'HO');
    });

    test('a multi-word location survives intact', () {
      final s = MonthlyReviewSummary.fromJson(
        base()..['projectLocation'] = 'Adept, Pune',
      );
      expect(s.projectLocation, 'Adept, Pune');
    });
  });

  group('the nested shape a sibling endpoint already uses', () {
    test('an object yields its NAME, never the stringified map', () {
      final s = MonthlyReviewSummary.fromJson(
        base()..['projectLocation'] = {'id': 'loc_ho', 'name': 'HO'},
      );
      expect(s.projectLocation, 'HO');
      // The failure this guards against renders as "{id: loc_ho, name: HO}"
      // on the card — valid-looking output that no exception would catch.
      expect(s.projectLocation, isNot(contains('{')));
      expect(s.projectLocation, isNot(contains('loc_ho')));
    });

    test('an object with no name is null, not an empty-ish map dump', () {
      final s = MonthlyReviewSummary.fromJson(
        base()..['projectLocation'] = {'id': 'loc_ho'},
      );
      expect(s.projectLocation, isNull);
    });
  });

  group('absence is null, so the card renders no dash', () {
    test('null when the employee has no location mapped', () {
      // Nullable in the schema, and `pl` is a LEFT JOIN — plenty of employees
      // have none. The card guards on trim().isNotEmpty, so this has to be
      // null or empty rather than a placeholder: a dangling " - " would read
      // as a rendering fault rather than as missing data.
      final s = MonthlyReviewSummary.fromJson(base());
      expect(s.projectLocation, isNull);
    });

    test('an explicit null parses as null', () {
      final s = MonthlyReviewSummary.fromJson(
        base()..['projectLocation'] = null,
      );
      expect(s.projectLocation, isNull);
    });

    test('an all-whitespace value renders nothing', () {
      final s = MonthlyReviewSummary.fromJson(
        base()..['projectLocation'] = '   ',
      );
      expect((s.projectLocation ?? '').trim(), isEmpty);
    });
  });

  test('it does not disturb the fields already on the card', () {
    // Name, code and designation share the card with it; designation in
    // particular sits on the very next line.
    final s = MonthlyReviewSummary.fromJson(base()
      ..['projectLocation'] = 'HO'
      ..['employeeDesignation'] = 'Cluster Manager'
      ..['employeeGrade'] = 'M1');
    expect(s.employeeName, 'Yash Thikekar');
    expect(s.employeeCode, 'VLPL0156');
    expect(s.employeeDesignation, 'Cluster Manager');
    expect(s.employeeGrade, 'M1');
    expect(s.projectLocation, 'HO');
  });
}
