import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';
import 'package:vistar_app/features/reviews/data/models/incentive_snapshot.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review_summary.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/models/stage_status.dart';

/// The dashboard reaches for [MonthlyReviewSummary.needsActionBy] on
/// every row it renders to decide the "needs your action" badge. That
/// predicate is deceptively subtle — it has to consider stage, status,
/// AND role. Missing any of the three quietly under- or over-badges the
/// dashboard.
void main() {
  MonthlyReviewSummary summary({
    required ReviewStage stage,
    StageStatus status = StageStatus.inProgress,
    String? managerId,
    PayoutStatus payoutStatus = PayoutStatus.pending,
  }) {
    return MonthlyReviewSummary(
      id: 'r1',
      employeeId: 'emp1',
      employeeName: 'Asha',
      employeeCode: 'VIS-1',
      managerId: managerId,
      year: 2026,
      month: 6,
      monthLabel: 'June 2026',
      currentStage: stage,
      currentStageStatus: status,
      payoutStatus: payoutStatus,
    );
  }

  // The two person-shaped rating stages badge off a RELATIONSHIP, not a role:
  // every employee has a reporting manager (managers and HR admins included),
  // so the badge follows employeeId / managerId, not the caller's role.
  group('MonthlyReviewSummary.needsActionBy — relationship stages', () {
    test('reporting-manager rating badges for the reporting manager, '
        'whatever their own role', () {
      final s =
          summary(stage: ReviewStage.reportingManagerRating, managerId: 'mgr1');
      expect(s.needsActionBy(UserRole.manager, userId: 'mgr1'), isTrue);
      // An HR_ADMIN who IS the reporting manager — previously role-blocked.
      expect(s.needsActionBy(UserRole.hrAdmin, userId: 'mgr1'), isTrue);
    });

    test('reporting-manager rating does not badge for anyone else', () {
      final s =
          summary(stage: ReviewStage.reportingManagerRating, managerId: 'mgr1');
      expect(s.needsActionBy(UserRole.manager, userId: 'other-mgr'), isFalse);
      expect(s.needsActionBy(UserRole.employee, userId: 'emp1'), isFalse);
      expect(s.needsActionBy(UserRole.finance, userId: 'fin1'), isFalse);
    });

    test('reporting-manager rating fails closed with no manager mapped', () {
      final s = summary(stage: ReviewStage.reportingManagerRating);
      expect(s.needsActionBy(UserRole.manager, userId: 'mgr1'), isFalse);
    });

    test('self rating badges only for the owner, whatever their role', () {
      final s = summary(stage: ReviewStage.selfRating);
      expect(s.needsActionBy(UserRole.employee, userId: 'emp1'), isTrue);
      // Managers/HR admins self-rate their own KRA too.
      expect(s.needsActionBy(UserRole.manager, userId: 'emp1'), isTrue);
      expect(s.needsActionBy(UserRole.hrAdmin, userId: 'emp1'), isTrue);
      expect(s.needsActionBy(UserRole.employee, userId: 'other'), isFalse);
    });
  });

  group('MonthlyReviewSummary.needsActionBy — status/terminal', () {
    test('false once the stage has been submitted (badge should clear)', () {
      final s = summary(
        stage: ReviewStage.reportingManagerRating,
        status: StageStatus.submitted,
        managerId: 'mgr1',
      );
      expect(s.needsActionBy(UserRole.manager, userId: 'mgr1'), isFalse);
    });

    test('false on the terminal completed stage for every role', () {
      final s = summary(
        stage: ReviewStage.completed,
        status: StageStatus.submitted,
        managerId: 'mgr1',
      );
      for (final role in UserRole.values) {
        expect(s.needsActionBy(role, userId: 'mgr1'), isFalse,
            reason: 'completed reviews should never badge — $role');
      }
    });
  });

  group('MonthlyReviewSummary payout / mark-paid', () {
    test('Accounts can mark paid once the management review is done', () {
      final s = summary(
        stage: ReviewStage.managementReview,
        status: StageStatus.submitted,
      );
      expect(s.managementReviewDone, isTrue);
      expect(s.canMarkPaidBy(UserRole.finance), isTrue);
      // HR / HR-admin are payout actors too.
      expect(s.canMarkPaidBy(UserRole.hr), isTrue);
      expect(s.canMarkPaidBy(UserRole.hrAdmin), isTrue);
    });

    test('not markable before the management review is done', () {
      // Review phase still in progress → management not done → no payout yet.
      final s = summary(
        stage: ReviewStage.reportingManagerRating,
        status: StageStatus.inProgress,
      );
      expect(s.managementReviewDone, isFalse);
      expect(s.canMarkPaidBy(UserRole.finance), isFalse);
    });

    test('a manager or employee can never mark paid', () {
      final s = summary(
        stage: ReviewStage.managementReview,
        status: StageStatus.submitted,
      );
      expect(s.canMarkPaidBy(UserRole.manager), isFalse);
      expect(s.canMarkPaidBy(UserRole.employee), isFalse);
    });

    test('already-paid reviews show as paid and are not markable again', () {
      final s = summary(
        stage: ReviewStage.completed,
        status: StageStatus.submitted,
        payoutStatus: PayoutStatus.paid,
      );
      expect(s.payoutPaid, isTrue);
      expect(s.canMarkPaidBy(UserRole.finance), isFalse);
    });
  });

  group('MonthlyReviewSummary.needsActionBy — org-level stages', () {
    test('still light up for exactly the roles agreed in the pipeline spec, '
        'independent of any reporting relationship', () {
      const table = <ReviewStage, Set<UserRole>>{
        // HR and Finance are now SEPARATE Review raters.
        ReviewStage.accountHrRating: {
          UserRole.hr,
          UserRole.hrAdmin,
        },
        ReviewStage.financeRating: {UserRole.finance},
        ReviewStage.managementReview: {UserRole.admin, UserRole.hrAdmin},
        ReviewStage.incentivePayout: {
          UserRole.finance,
          UserRole.hr,
          UserRole.hrAdmin,
        },
      };
      for (final entry in table.entries) {
        // managerId set + a userId that is NOT it: org stages must ignore both.
        final s = summary(stage: entry.key, managerId: 'mgr1');
        for (final role in UserRole.values) {
          final shouldBadge = entry.value.contains(role);
          expect(
            s.needsActionBy(role, userId: 'somebody-else'),
            shouldBadge,
            reason:
                '${entry.key.name} for role $role — expected $shouldBadge',
          );
        }
      }
    });
  });
}
