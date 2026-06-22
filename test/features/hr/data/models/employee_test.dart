import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/hr/data/models/employee.dart';

void main() {
  group('Employee.monthlyIncentiveAmount (per-employee incentive)', () {
    test('parses a numeric incentive amount from JSON', () {
      final e = Employee.fromJson({
        'id': 'e1',
        'employeeCode': 'VIS-1',
        'fullName': 'Asha',
        'email': 'asha@vistar.test',
        'role': 'EMPLOYEE',
        'monthlyIncentiveAmount': 5000,
      });
      expect(e.monthlyIncentiveAmount, 5000);
    });

    test('parses a string-decimal incentive (Prisma Decimal on the wire)', () {
      final e = Employee.fromJson({
        'id': 'e1',
        'employeeCode': 'VIS-1',
        'fullName': 'Asha',
        'email': 'asha@vistar.test',
        'role': 'EMPLOYEE',
        'monthlyIncentiveAmount': '7000.00',
      });
      expect(e.monthlyIncentiveAmount, 7000);
    });

    test('is null when absent (employee falls back to the org default)', () {
      final e = Employee.fromJson({
        'id': 'e1',
        'employeeCode': 'VIS-1',
        'fullName': 'Asha',
        'email': 'asha@vistar.test',
        'role': 'EMPLOYEE',
      });
      expect(e.monthlyIncentiveAmount, isNull);
    });

    test('survives a toJson → fromJson round trip', () {
      const e = Employee(
        id: 'e1',
        employeeCode: 'VIS-1',
        fullName: 'Asha',
        email: 'asha@vistar.test',
        role: 'EMPLOYEE',
        monthlyIncentiveAmount: 4200,
      );
      final back = Employee.fromJson(e.toJson());
      expect(back.monthlyIncentiveAmount, 4200);
    });

    test('copyWith preserves the incentive when untouched', () {
      const e = Employee(
        id: 'e1',
        employeeCode: 'VIS-1',
        fullName: 'Asha',
        email: 'asha@vistar.test',
        role: 'EMPLOYEE',
        monthlyIncentiveAmount: 4200,
      );
      expect(e.copyWith(fullName: 'Asha R.').monthlyIncentiveAmount, 4200);
    });
  });
}
