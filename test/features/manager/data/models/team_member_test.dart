import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/employee/data/models/enums.dart';
import 'package:vistar_app/features/manager/data/models/team_member.dart';

void main() {
  group('TeamMember.isReadyForMyReview', () {
    test('true when state=EMPLOYEE_SUBMITTED_ALL and reviewId present', () {
      final m = _member(
        state: ReviewState.employeeSubmittedAll,
        reviewId: 'r1',
      );
      expect(m.isReadyForMyReview, isTrue);
    });

    test('false when reviewId is null even with submitted state', () {
      final m = _member(
        state: ReviewState.employeeSubmittedAll,
        reviewId: null,
      );
      expect(m.isReadyForMyReview, isFalse);
    });

    test('false for any other review state', () {
      for (final s in [
        ReviewState.draft,
        ReviewState.inProgress,
        ReviewState.managerRatedAll,
        ReviewState.finalized,
        ReviewState.acknowledged,
      ]) {
        final m = _member(state: s, reviewId: 'r1');
        expect(m.isReadyForMyReview, isFalse, reason: s.toString());
      }
    });
  });

  group('TeamMember JSON round-trip', () {
    test('toJson → fromJson preserves identity', () {
      final original = _member(
        employeeId: 'emp-001',
        employeeCode: 'VLPL0001',
        fullName: 'Pravin K',
        state: ReviewState.employeeSubmittedAll,
        reviewId: 'r1',
        selfTotal: 88.5,
        managerTotal: null,
        finalTotal: null,
        isOverdue: false,
        trend: const [70.0, 80.0, null],
      );
      final restored = TeamMember.fromJson(original.toJson());
      expect(restored.employeeId, original.employeeId);
      expect(restored.fullName, original.fullName);
      expect(restored.reviewState, original.reviewState);
      expect(restored.selfTotal, 88.5);
      expect(restored.managerTotal, isNull);
      expect(restored.threeMonthTrend, [70.0, 80.0, null]);
    });

    test('fromJson tolerates string decimals from the wire', () {
      final json = {
        'employeeId': 'e',
        'employeeCode': 'c',
        'fullName': 'name',
        'reviewState': 'EMPLOYEE_SUBMITTED_ALL',
        'selfTotal': '85.50',
        'managerTotal': '90.00',
        'threeMonthTrend': ['80.0', '85.5', null],
      };
      final m = TeamMember.fromJson(json);
      expect(m.selfTotal, 85.5);
      expect(m.managerTotal, 90.0);
      expect(m.threeMonthTrend, [80.0, 85.5, null]);
    });
  });

  group('TeamMemberPage.hasMore', () {
    test('false when all items already loaded', () {
      const p = TeamMemberPage(
        members: [],
        page: 1,
        pageSize: 20,
        total: 0,
      );
      expect(p.hasMore, isFalse);
    });

    test('true when loaded count < total', () {
      final p = TeamMemberPage(
        members: List.generate(20, (_) => _member()),
        page: 1,
        pageSize: 20,
        total: 50,
      );
      expect(p.hasMore, isTrue);
    });

    test('false when paged through to the last page', () {
      final p = TeamMemberPage(
        members: List.generate(10, (_) => _member()),
        page: 3,
        pageSize: 20,
        total: 50,
      );
      // (3-1)*20 + 10 = 50, equal to total → no more.
      expect(p.hasMore, isFalse);
    });
  });
}

TeamMember _member({
  String employeeId = 'e1',
  String employeeCode = 'c1',
  String fullName = 'Test User',
  ReviewState state = ReviewState.draft,
  String? reviewId,
  double? selfTotal,
  double? managerTotal,
  double? finalTotal,
  bool isOverdue = false,
  List<double?> trend = const [],
}) {
  return TeamMember(
    employeeId: employeeId,
    employeeCode: employeeCode,
    fullName: fullName,
    reviewState: state,
    reviewId: reviewId,
    selfTotal: selfTotal,
    managerTotal: managerTotal,
    finalTotal: finalTotal,
    isOverdue: isOverdue,
    threeMonthTrend: trend,
  );
}
