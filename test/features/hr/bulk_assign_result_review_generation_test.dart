import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/hr/data/models/bulk_assign_result.dart';

/// The bulk-assign response now UPSERTS: an employee who already had a KRA this
/// cycle has it REPLACED (updatedCount), never silently skipped as a dup.
/// `reviewGeneration` reports how the underlying reviews were created/rebuilt
/// so HR can be toasted an accurate message. Parsing must be tolerant.
void main() {
  group('BulkAssignResult — created vs updated (upsert)', () {
    test('parses a re-assign that REPLACED an existing KRA', () {
      final result = BulkAssignResult.fromJson({
        'createdCount': 0,
        'updatedCount': 1,
        'skippedCount': 0,
        'skippedEmployeeIds': <String>[],
        'created': <Map<String, dynamic>>[],
        'reviewGeneration': {
          'created': 0,
          'updated': 1,
          'skipped': <Map<String, dynamic>>[],
          'message': '1 review updated to the new KRA.',
        },
      });
      expect(result.createdCount, 0);
      expect(result.updatedCount, 1);
      expect(result.skippedCount, 0);
      expect(result.reviewGeneration, isNotNull);
      expect(result.reviewGeneration!.updated, 1);
      expect(result.reviewGeneration!.message, '1 review updated to the new KRA.');
      expect(result.reviewGeneration!.hasMessage, isTrue);
    });

    test('parses a fresh assign (created) with a new review', () {
      final result = BulkAssignResult.fromJson({
        'createdCount': 1,
        'updatedCount': 0,
        'skippedCount': 0,
        'skippedEmployeeIds': <String>[],
        'created': <Map<String, dynamic>>[],
        'reviewGeneration': {'created': 1, 'updated': 0, 'skipped': [], 'message': '1 review created.'},
      });
      expect(result.createdCount, 1);
      expect(result.updatedCount, 0);
      expect(result.reviewGeneration!.created, 1);
    });

    test('surfaces a skipped-review reason (e.g. review already in progress)', () {
      final result = BulkAssignResult.fromJson({
        'createdCount': 0,
        'updatedCount': 1,
        'skippedCount': 0,
        'skippedEmployeeIds': <String>[],
        'created': <Map<String, dynamic>>[],
        'reviewGeneration': {
          'created': 0,
          'updated': 0,
          'skipped': [
            {'employeeId': 'e1', 'reason': 'A review is already in progress for this cycle.'}
          ],
          'message': 'A review is already in progress for this cycle.',
        },
      });
      expect(result.reviewGeneration!.skippedReasons,
          ['A review is already in progress for this cycle.']);
      expect(result.reviewGeneration!.message,
          'A review is already in progress for this cycle.');
    });

    test('is null / defaults when the response omits the extra fields', () {
      final result = BulkAssignResult.fromJson({
        'createdCount': 1,
        'skippedCount': 0,
        'skippedEmployeeIds': <String>[],
        'created': <Map<String, dynamic>>[],
      });
      expect(result.updatedCount, 0);
      expect(result.reviewGeneration, isNull);
    });

    test('tolerates a partial reviewGeneration (missing message) without throwing', () {
      final result = BulkAssignResult.fromJson({
        'createdCount': 1,
        'updatedCount': 0,
        'skippedCount': 0,
        'skippedEmployeeIds': <String>[],
        'created': <Map<String, dynamic>>[],
        'reviewGeneration': {'created': 1},
      });
      expect(result.reviewGeneration!.created, 1);
      expect(result.reviewGeneration!.message, '');
      expect(result.reviewGeneration!.hasMessage, isFalse);
    });
  });
}
