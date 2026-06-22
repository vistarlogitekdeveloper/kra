import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/hr/data/models/kra_assignment.dart';

/// Pins the dual-read JSON contract for KraAssignment.
///
/// The live API on `/kra-assignments?employeeId=...` nests references
/// under `employee.*`, `cycle.*`, `template.*`. The early spec used flat
/// `employeeName`, `cycleName`, `templateName`. We read the nested form
/// first and fall back to the flat one — the employee-detail KRA section
/// shows "—" if both are missing, so the dual-read keeps the UX healthy
/// across both backend shapes.
void main() {
  group('KraAssignment.fromJson dual-read', () {
    test('reads names from nested cycle / template / employee objects', () {
      final a = KraAssignment.fromJson(const {
        'id': 'asgn_1',
        'employeeId': 'emp_1',
        'cycleId': 'cyc_1',
        'templateId': 'tpl_1',
        'isLocked': false,
        'items': <Map<String, dynamic>>[],
        'employee': {'id': 'emp_1', 'name': 'Anita Sharma'},
        'cycle': {'id': 'cyc_1', 'name': 'Q1 FY26-27'},
        'template': {'id': 'tpl_1', 'name': 'Employee KRA - Default'},
      });

      expect(a.employeeName, 'Anita Sharma');
      expect(a.cycleName, 'Q1 FY26-27');
      expect(a.templateName, 'Employee KRA - Default');
    });

    test('falls back to flat *Name fields when nested objects are absent',
        () {
      final a = KraAssignment.fromJson(const {
        'id': 'asgn_2',
        'employeeId': 'emp_2',
        'employeeName': 'Bharath K',
        'cycleId': 'cyc_2',
        'cycleName': 'Q2 FY26-27',
        'templateId': 'tpl_2',
        'templateName': 'Manager KRA',
        'isLocked': true,
        'items': <Map<String, dynamic>>[],
      });

      expect(a.employeeName, 'Bharath K');
      expect(a.cycleName, 'Q2 FY26-27');
      expect(a.templateName, 'Manager KRA');
      expect(a.isLocked, true);
    });

    test('nested form wins when both shapes are present (defensive)', () {
      final a = KraAssignment.fromJson(const {
        'id': 'asgn_3',
        'employeeId': 'emp_3',
        'cycleId': 'cyc_3',
        'isLocked': false,
        'items': <Map<String, dynamic>>[],
        'cycleName': 'STALE',
        'cycle': {'id': 'cyc_3', 'name': 'FRESH'},
      });

      expect(a.cycleName, 'FRESH');
    });

    test('leaves names null when neither shape carries them', () {
      final a = KraAssignment.fromJson(const {
        'id': 'asgn_4',
        'employeeId': 'emp_4',
        'cycleId': 'cyc_4',
        'isLocked': false,
        'items': <Map<String, dynamic>>[],
      });

      expect(a.employeeName, isNull);
      expect(a.cycleName, isNull);
      expect(a.templateName, isNull);
    });
  });
}
