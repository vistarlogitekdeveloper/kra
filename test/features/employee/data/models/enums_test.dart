import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/employee/data/models/enums.dart';

void main() {
  group('ReviewState.fromApi', () {
    test('parses all known values (case-insensitive)', () {
      expect(ReviewState.fromApi('DRAFT'), ReviewState.draft);
      expect(ReviewState.fromApi('draft'), ReviewState.draft);
      expect(ReviewState.fromApi('IN_PROGRESS'), ReviewState.inProgress);
      expect(ReviewState.fromApi('EMPLOYEE_SUBMITTED_ALL'),
          ReviewState.employeeSubmittedAll);
      expect(ReviewState.fromApi('MANAGER_RATED_ALL'),
          ReviewState.managerRatedAll);
      expect(ReviewState.fromApi('FINALIZED'), ReviewState.finalized);
      expect(ReviewState.fromApi('ACKNOWLEDGED'), ReviewState.acknowledged);
    });

    test('falls back to draft on unknown values', () {
      expect(ReviewState.fromApi('UNKNOWN_STATE'), ReviewState.draft);
      expect(ReviewState.fromApi(''), ReviewState.draft);
    });
  });

  group('ReviewState properties', () {
    test('isSelfEditable is true for draft/inProgress/employeeSubmittedAll',
        () {
      expect(ReviewState.draft.isSelfEditable, isTrue);
      expect(ReviewState.inProgress.isSelfEditable, isTrue);
      expect(ReviewState.employeeSubmittedAll.isSelfEditable, isTrue);
      expect(ReviewState.managerRatedAll.isSelfEditable, isFalse);
      expect(ReviewState.finalized.isSelfEditable, isFalse);
      expect(ReviewState.acknowledged.isSelfEditable, isFalse);
    });

    test('hasSubmittedAll is false only for draft/inProgress', () {
      expect(ReviewState.draft.hasSubmittedAll, isFalse);
      expect(ReviewState.inProgress.hasSubmittedAll, isFalse);
      expect(ReviewState.employeeSubmittedAll.hasSubmittedAll, isTrue);
      expect(ReviewState.managerRatedAll.hasSubmittedAll, isTrue);
      expect(ReviewState.finalized.hasSubmittedAll, isTrue);
      expect(ReviewState.acknowledged.hasSubmittedAll, isTrue);
    });

    test('pipelineStep returns 1-6 in order', () {
      expect(ReviewState.draft.pipelineStep, 1);
      expect(ReviewState.inProgress.pipelineStep, 2);
      expect(ReviewState.employeeSubmittedAll.pipelineStep, 3);
      expect(ReviewState.managerRatedAll.pipelineStep, 4);
      expect(ReviewState.finalized.pipelineStep, 5);
      expect(ReviewState.acknowledged.pipelineStep, 6);
    });
  });

  group('ReviewMonthStatus.fromApi', () {
    test('parses all values', () {
      expect(ReviewMonthStatus.fromApi('OPEN'), ReviewMonthStatus.open);
      expect(ReviewMonthStatus.fromApi('CLOSED'), ReviewMonthStatus.closed);
      expect(ReviewMonthStatus.fromApi('LOCKED'), ReviewMonthStatus.locked);
    });

    test('falls back to open on unknown', () {
      expect(ReviewMonthStatus.fromApi('BANANA'), ReviewMonthStatus.open);
    });
  });

  group('ScoreSource.fromApi', () {
    test('parses known values', () {
      expect(ScoreSource.fromApi('SELF'), ScoreSource.self);
      expect(ScoreSource.fromApi('MANAGER'), ScoreSource.manager);
      expect(ScoreSource.fromApi('FEED'), ScoreSource.feed);
    });

    test('falls back to manager on unknown', () {
      expect(ScoreSource.fromApi('BANANA'), ScoreSource.manager);
    });
  });

  group('MonthlyIncentiveStatus.fromApi', () {
    test('parses all values', () {
      expect(MonthlyIncentiveStatus.fromApi('NO_REVIEW'),
          MonthlyIncentiveStatus.noReview);
      expect(MonthlyIncentiveStatus.fromApi('PENDING_SELF'),
          MonthlyIncentiveStatus.pendingSelf);
      expect(MonthlyIncentiveStatus.fromApi('PENDING_MANAGER'),
          MonthlyIncentiveStatus.pendingManager);
      expect(MonthlyIncentiveStatus.fromApi('COMPLETE'),
          MonthlyIncentiveStatus.complete);
      expect(MonthlyIncentiveStatus.fromApi('LOCKED'),
          MonthlyIncentiveStatus.locked);
    });
  });
}
