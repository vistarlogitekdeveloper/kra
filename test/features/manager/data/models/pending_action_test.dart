import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/manager/data/models/pending_action.dart';

void main() {
  group('PendingAction.fromJson — flat (legacy/spec) shape', () {
    test('reads every field from inline top-level keys', () {
      final p = PendingAction.fromJson({
        'reviewId': 'rev_1',
        'employeeId': 'emp_1',
        'employeeName': 'Pravin K',
        'employeeCode': 'VLPL0001',
        'monthLabel': 'Apr 2026',
        'submittedAt': '2026-04-05T09:30:00Z',
        'deadlineRemaining': 7,
      });

      expect(p.reviewId, 'rev_1');
      expect(p.employeeId, 'emp_1');
      expect(p.employeeName, 'Pravin K');
      expect(p.employeeCode, 'VLPL0001');
      expect(p.monthLabel, 'Apr 2026');
      expect(p.submittedAt?.isUtc, isTrue);
      expect(p.deadlineRemaining, 7);
      expect(p.isOverdue, isFalse);
    });
  });

  group('PendingAction.fromJson — live (nested) shape', () {
    test('reads employee under employee.{id,name,employeeCode}', () {
      final p = PendingAction.fromJson({
        'id': 'rev_2',
        'employee': {
          'id': 'emp_2',
          'name': 'Asha M',
          'employeeCode': 'VLPL0002',
        },
        'month': {'monthLabel': 'May 2026'},
        'daysRemaining': -3,
      });

      expect(p.reviewId, 'rev_2');
      expect(p.employeeId, 'emp_2');
      expect(p.employeeName, 'Asha M');
      expect(p.employeeCode, 'VLPL0002');
      expect(p.monthLabel, 'May 2026');
      expect(p.deadlineRemaining, -3);
      expect(p.isOverdue, isTrue);
    });

    test('tolerates employee.fullName / employee.code fallbacks', () {
      final p = PendingAction.fromJson({
        'id': 'rev_3',
        'employee': {
          'id': 'emp_3',
          'fullName': 'Ravi T',
          'code': 'VLPL0003',
        },
        'month': {'label': 'Jun 2026'},
      });
      expect(p.employeeName, 'Ravi T');
      expect(p.employeeCode, 'VLPL0003');
      expect(p.monthLabel, 'Jun 2026');
    });
  });

  group('PendingAction.fromJson — mixed / missing', () {
    test('live employee block wins when both shapes coexist', () {
      final p = PendingAction.fromJson({
        'reviewId': 'rev_4',
        'employeeName': 'Old',
        'employee': {'id': 'emp_4', 'name': 'New', 'employeeCode': 'C'},
      });
      expect(p.employeeName, 'New');
      expect(p.employeeId, 'emp_4');
    });

    test('falls back to empty string when neither shape carries names', () {
      final p = PendingAction.fromJson({'reviewId': 'r5'});
      expect(p.employeeName, '');
      expect(p.employeeCode, '');
      expect(p.monthLabel, '');
      expect(p.deadlineRemaining, isNull);
      expect(p.submittedAt, isNull);
      expect(p.isOverdue, isFalse);
    });

    test('isOverdue is false when deadlineRemaining is null', () {
      final p = PendingAction.fromJson({'reviewId': 'r6'});
      expect(p.isOverdue, isFalse);
    });
  });
}
