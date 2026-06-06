import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/employee/data/models/enums.dart';
import 'package:vistar_app/features/manager/data/models/previous_review.dart';

void main() {
  group('PreviousReview.fromJson — flat (legacy) shape', () {
    test('reads every field from inline top-level keys', () {
      final r = PreviousReview.fromJson({
        'reviewId': 'rev_1',
        'cycleName': 'Q1 FY26-27',
        'fyLabel': 'FY26-27',
        'quarterNum': 1,
        'state': 'FINALIZED',
        'finalTotal': 88.5,
        'endDate': '2026-06-30T00:00:00Z',
        'employeeName': 'Pravin K',
        'employeeId': 'emp_1',
      });
      expect(r.reviewId, 'rev_1');
      expect(r.cycleName, 'Q1 FY26-27');
      expect(r.fyLabel, 'FY26-27');
      expect(r.quarterNum, 1);
      expect(r.state, ReviewState.finalized);
      expect(r.finalTotal, 88.5);
      expect(r.endDate?.year, 2026);
      expect(r.employeeName, 'Pravin K');
      expect(r.employeeId, 'emp_1');
    });
  });

  group('PreviousReview.fromJson — live (nested) shape', () {
    test('reads cycle under reviewCycle.* and employee under employee.*', () {
      final r = PreviousReview.fromJson({
        'id': 'rev_2',
        'reviewCycle': {
          'name': 'Q2 FY26-27',
          'fyLabel': 'FY26-27',
          'quarterNum': 2,
          'endDate': '2026-09-30T00:00:00Z',
        },
        'employee': {'id': 'emp_2', 'name': 'Asha M'},
        'state': 'MANAGER_RATED_ALL',
        'finalAvgManagerPct': 76.25,
      });
      expect(r.reviewId, 'rev_2');
      expect(r.cycleName, 'Q2 FY26-27');
      expect(r.fyLabel, 'FY26-27');
      expect(r.quarterNum, 2);
      expect(r.state, ReviewState.managerRatedAll);
      // finalTotal falls back from flat to finalAvgManagerPct on live.
      expect(r.finalTotal, 76.25);
      expect(r.endDate?.month, 9);
      expect(r.employeeName, 'Asha M');
      expect(r.employeeId, 'emp_2');
    });

    test('also accepts the older `cycle` key as the live wrapper', () {
      final r = PreviousReview.fromJson({
        'reviewId': 'rev_3',
        'cycle': {'name': 'Q3 FY26-27'},
        'state': 'DRAFT',
      });
      expect(r.cycleName, 'Q3 FY26-27');
      expect(r.state, ReviewState.draft);
    });

    test('falls back to finalAvgSelfPct when no manager total exists yet', () {
      final r = PreviousReview.fromJson({
        'id': 'rev_4',
        'state': 'EMPLOYEE_SUBMITTED_ALL',
        'finalAvgSelfPct': 70.0,
      });
      expect(r.finalTotal, 70.0);
    });
  });

  group('PreviousReview.fromJson — mixed / missing', () {
    test('live nested cycle wins over inline cycleName', () {
      final r = PreviousReview.fromJson({
        'reviewId': 'rev_5',
        'cycleName': 'flat',
        'reviewCycle': {'name': 'nested'},
        'state': 'DRAFT',
      });
      expect(r.cycleName, 'nested');
    });

    test('defaults to DRAFT and empty strings when nothing matches', () {
      final r = PreviousReview.fromJson({});
      expect(r.reviewId, '');
      expect(r.cycleName, '');
      expect(r.state, ReviewState.draft);
      expect(r.finalTotal, isNull);
      expect(r.endDate, isNull);
      expect(r.employeeName, isNull);
      expect(r.employeeId, isNull);
    });
  });
}
