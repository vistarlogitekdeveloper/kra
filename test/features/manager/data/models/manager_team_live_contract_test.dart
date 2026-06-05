import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/employee/data/models/enums.dart';
import 'package:vistar_app/features/manager/data/models/manager_dashboard.dart';
import 'package:vistar_app/features/manager/data/models/pending_action.dart';
import 'package:vistar_app/features/manager/data/models/team_member.dart';

/// Regression guard for the manager team-list + dashboard contracts.
///
/// Against the live backend, GET /manager/team identifies the member
/// with `id`/`name` (not `employeeId`/`fullName`), exposes
/// `projectLocation` as an object, and nests the review summary under
/// `currentReview.{id,state,selfTotal,…}` (not flat). Before the fix the
/// model read the flat names, so every tile rendered a blank name, a
/// stringified `{id: …, name: …}` location, and — critically — a null
/// `reviewId`, which hid the "Review" CTA and made it impossible to open
/// a review from the team tab. The hand-written fixtures used the flat
/// spec names, so the bug stayed green.
///
/// The dashboard's pending-action rows carry `daysRemaining` on the wire
/// (not `deadlineRemaining`), which the overdue/deadline chip depends on.
void main() {
  // Verbatim subset of a real GET /manager/team row.
  Map<String, dynamic> liveTeamMember() => {
        'id': 'emp_e2',
        'name': 'Vikram Singh',
        'employeeCode': 'EMP004',
        'email': 'emp2@vistar.test',
        'role': 'EMPLOYEE',
        'department': 'Operations',
        'grade': 'E1',
        'position': 'Associate',
        'projectLocation': {'id': 'loc_mumbai_hq', 'name': 'Mumbai HQ'},
        'currentReview': {
          'id': 'rev_e2',
          'state': 'EMPLOYEE_SUBMITTED_ALL',
          'selfRatedAt': '2026-05-14T06:21:55.725Z',
          'managerReviewedAt': null,
          'finalizedAt': null,
          'selfTotal': 90,
          'managerTotal': null,
          'finalTotal': null,
          'isLocked': false,
          'daysUntilDeadline': 70,
          'isOverdue': false,
        },
        'history': {'recentCycles': []},
      };

  group('TeamMember parses the live /manager/team contract', () {
    test('identity comes from id/name, not flat employeeId/fullName', () {
      final m = TeamMember.fromJson(liveTeamMember());
      expect(m.employeeId, 'emp_e2');
      expect(m.fullName, 'Vikram Singh');
      expect(m.employeeCode, 'EMP004');
    });

    test('projectLocation is the object name, not a stringified map', () {
      final m = TeamMember.fromJson(liveTeamMember());
      expect(m.projectLocation, 'Mumbai HQ');
      expect(m.projectLocation, isNot(contains('{')));
    });

    test('review summary is read from currentReview', () {
      final m = TeamMember.fromJson(liveTeamMember());
      // reviewId non-null is what surfaces the "Review" CTA and lets the
      // manager navigate to the review.
      expect(m.reviewId, 'rev_e2');
      expect(m.reviewState, ReviewState.employeeSubmittedAll);
      expect(m.selfTotal, 90);
      expect(m.isReadyForMyReview, isTrue);
    });
  });

  group('TeamMember backward compatibility with the flat shape', () {
    test('still parses flat spec/mock payloads', () {
      final flat = {
        'employeeId': 'e1',
        'employeeCode': 'C1',
        'fullName': 'Flat Name',
        'projectLocation': 'Pune DC',
        'reviewId': 'rv1',
        'reviewState': 'MANAGER_RATED_ALL',
        'selfTotal': 80,
        'managerTotal': 75,
        'isOverdue': true,
      };
      final m = TeamMember.fromJson(flat);
      expect(m.employeeId, 'e1');
      expect(m.fullName, 'Flat Name');
      expect(m.projectLocation, 'Pune DC');
      expect(m.reviewId, 'rv1');
      expect(m.reviewState, ReviewState.managerRatedAll);
      expect(m.selfTotal, 80);
      expect(m.isOverdue, isTrue);
    });

    test('toJson → fromJson round-trips', () {
      const original = TeamMember(
        employeeId: 'e9',
        employeeCode: 'C9',
        fullName: 'Round Trip',
        reviewId: 'rv9',
        reviewState: ReviewState.finalized,
        selfTotal: 88,
      );
      final back = TeamMember.fromJson(original.toJson());
      expect(back.employeeId, 'e9');
      expect(back.fullName, 'Round Trip');
      expect(back.reviewId, 'rv9');
      expect(back.reviewState, ReviewState.finalized);
      expect(back.selfTotal, 88);
    });
  });

  group('manager dashboard pending actions', () {
    test('PendingAction reads daysRemaining from the live wire', () {
      final live = {
        'reviewId': 'rev_e2',
        'employeeId': 'emp_e2',
        'employeeName': 'Vikram Singh',
        'employeeCode': 'EMP004',
        'submittedAt': '2026-05-14T06:21:55.725Z',
        'daysRemaining': -2,
        'isOverdue': true,
        'selfTotal': 90,
      };
      final pa = PendingAction.fromJson(live);
      expect(pa.reviewId, 'rev_e2');
      expect(pa.employeeName, 'Vikram Singh');
      expect(pa.deadlineRemaining, -2);
      expect(pa.isOverdue, isTrue);
    });

    test('ManagerDashboard parses the live top-level shape', () {
      final live = {
        'manager': {
          'id': 'emp_manager',
          'name': 'Raj Manager',
          'employeeCode': 'EMP002',
          'role': 'MANAGER',
        },
        'activeCycle': {
          'id': 'cyc_q1_fy2627',
          'name': 'Q1 FY26-27',
          'status': 'ACTIVE',
          'fyLabel': 'FY26-27',
          'managerReviewDeadline': '2026-07-31T00:00:00.000Z',
        },
        'stats': {
          'totalReports': 3,
          'pendingMyReview': 1,
          'completedThisMonth': 0,
          'overdueReviews': 0,
        },
        'pendingActions': [
          {
            'reviewId': 'rev_e2',
            'employeeName': 'Vikram Singh',
            'daysRemaining': 70,
          },
        ],
      };
      final d = ManagerDashboard.fromJson(live);
      expect(d.manager.name, 'Raj Manager');
      expect(d.activeCycle?.name, 'Q1 FY26-27');
      expect(d.stats.totalReports, 3);
      expect(d.stats.pendingMyReview, 1);
      expect(d.pendingActions, hasLength(1));
      expect(d.pendingActions.first.reviewId, 'rev_e2');
      expect(d.pendingActions.first.deadlineRemaining, 70);
    });
  });
}
