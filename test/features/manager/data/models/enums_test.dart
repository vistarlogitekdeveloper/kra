import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/manager/data/models/enums.dart';

void main() {
  group('ManagerTeamFilter.fromApi', () {
    test('parses all known values (case-insensitive)', () {
      expect(ManagerTeamFilter.fromApi('PENDING_MY_REVIEW'),
          ManagerTeamFilter.pendingMyReview);
      expect(ManagerTeamFilter.fromApi('pending_my_review'),
          ManagerTeamFilter.pendingMyReview);
      expect(ManagerTeamFilter.fromApi('COMPLETED'),
          ManagerTeamFilter.completed);
      expect(ManagerTeamFilter.fromApi('NOT_SUBMITTED'),
          ManagerTeamFilter.notSubmitted);
      expect(ManagerTeamFilter.fromApi('OVERDUE'),
          ManagerTeamFilter.overdue);
    });

    test('falls back to all on null / unknown / empty', () {
      expect(ManagerTeamFilter.fromApi(null), ManagerTeamFilter.all);
      expect(ManagerTeamFilter.fromApi(''), ManagerTeamFilter.all);
      expect(ManagerTeamFilter.fromApi('BANANA'), ManagerTeamFilter.all);
    });
  });

  group('ManagerTeamFilter.toApiString', () {
    test('all resolves to null so the query param can be omitted', () {
      expect(ManagerTeamFilter.all.toApiString(), isNull);
    });

    test('non-all filters return their wire value', () {
      expect(ManagerTeamFilter.pendingMyReview.toApiString(),
          'PENDING_MY_REVIEW');
      expect(ManagerTeamFilter.completed.toApiString(), 'COMPLETED');
      expect(ManagerTeamFilter.notSubmitted.toApiString(),
          'NOT_SUBMITTED');
      expect(ManagerTeamFilter.overdue.toApiString(), 'OVERDUE');
    });
  });

  group('ManagerMode', () {
    test('displayName returns user-facing labels', () {
      expect(ManagerMode.myTeam.displayName, 'My Team');
      expect(ManagerMode.myReview.displayName, 'My Review');
    });
  });

  group('BulkSkipReason.fromApi', () {
    test('parses known wire values', () {
      expect(BulkSkipReason.fromApi('INCOMPLETE_AFTER_COPY'),
          BulkSkipReason.incompleteAfterCopy);
      expect(BulkSkipReason.fromApi('NOT_EMPLOYEE_SUBMITTED'),
          BulkSkipReason.notEmployeeSubmitted);
      expect(BulkSkipReason.fromApi('DEADLINE_PASSED'),
          BulkSkipReason.deadlinePassed);
    });

    test('falls back to other for unknown codes', () {
      expect(BulkSkipReason.fromApi('FOO'), BulkSkipReason.other);
      expect(BulkSkipReason.fromApi(''), BulkSkipReason.other);
    });
  });
}
