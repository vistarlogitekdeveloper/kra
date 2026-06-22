import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/hr/data/models/bulk_assign_result.dart';

/// Pins the wire contract for POST /kra-assignments/bulk.
///
/// The endpoint returns `data` as a MAP, not a list, with `createdCount`,
/// `skippedCount`, `skippedEmployeeIds`, and `created: [...]`. We used to
/// parse it through `unwrapList`, which threw BAD_RESPONSE on the happy
/// path — the confirm screen surfaced this as a failure even though the
/// backend had saved everything.
void main() {
  group('BulkAssignResult.fromJson', () {
    test('parses the live shape — all skipped (idempotent re-assign)', () {
      final r = BulkAssignResult.fromJson({
        'createdCount': 0,
        'skippedCount': 1,
        'skippedEmployeeIds': ['emp-1'],
        'created': <Map<String, dynamic>>[],
      });

      expect(r.createdCount, 0);
      expect(r.skippedCount, 1);
      expect(r.skippedEmployeeIds, ['emp-1']);
      expect(r.created, isEmpty);
    });

    test('parses a mixed result', () {
      final r = BulkAssignResult.fromJson({
        'createdCount': 2,
        'skippedCount': 1,
        'skippedEmployeeIds': ['emp-3'],
        'created': [
          {
            'id': 'asg-1',
            'employeeId': 'emp-1',
            'cycleId': 'cyc-1',
            'isLocked': false,
            'items': <Map<String, dynamic>>[],
          },
          {
            'id': 'asg-2',
            'employeeId': 'emp-2',
            'cycleId': 'cyc-1',
            'isLocked': false,
            'items': <Map<String, dynamic>>[],
          },
        ],
      });

      expect(r.createdCount, 2);
      expect(r.skippedCount, 1);
      expect(r.skippedEmployeeIds, ['emp-3']);
      expect(r.created.map((a) => a.id).toList(), ['asg-1', 'asg-2']);
    });

    test('falls back to list lengths when counts are missing', () {
      final r = BulkAssignResult.fromJson({
        'created': <Map<String, dynamic>>[],
        'skippedEmployeeIds': ['emp-1', 'emp-2'],
      });

      expect(r.createdCount, 0);
      expect(r.skippedCount, 2);
    });

    test('tolerates string-encoded counts', () {
      final r = BulkAssignResult.fromJson({
        'createdCount': '3',
        'skippedCount': '0',
        'skippedEmployeeIds': <String>[],
        'created': <Map<String, dynamic>>[],
      });

      expect(r.createdCount, 3);
      expect(r.skippedCount, 0);
    });

    test('returns empty lists when fields are missing entirely', () {
      final r = BulkAssignResult.fromJson(const <String, dynamic>{});

      expect(r.createdCount, 0);
      expect(r.skippedCount, 0);
      expect(r.skippedEmployeeIds, isEmpty);
      expect(r.created, isEmpty);
    });
  });
}
