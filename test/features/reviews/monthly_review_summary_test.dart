import 'package:flutter_test/flutter_test.dart';
import 'package:vistar_app/features/auth/data/models/user.dart';
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
  }) {
    return MonthlyReviewSummary(
      id: 'r1',
      employeeId: 'emp1',
      employeeName: 'Asha',
      employeeCode: 'VIS-1',
      year: 2026,
      month: 6,
      monthLabel: 'June 2026',
      currentStage: stage,
      currentStageStatus: status,
    );
  }

  group('MonthlyReviewSummary.needsActionBy', () {
    test('true when the role can act on the current stage', () {
      final s = summary(stage: ReviewStage.reportingManagerRating);
      expect(s.needsActionBy(UserRole.manager), isTrue);
    });

    test('false for a role outside the current stage\'s actor set', () {
      final s = summary(stage: ReviewStage.reportingManagerRating);
      expect(s.needsActionBy(UserRole.employee), isFalse);
      expect(s.needsActionBy(UserRole.finance), isFalse);
    });

    test('false once the stage has been submitted (badge should clear)',
        () {
      final s = summary(
        stage: ReviewStage.reportingManagerRating,
        status: StageStatus.submitted,
      );
      expect(s.needsActionBy(UserRole.manager), isFalse);
    });

    test('false on the terminal completed stage for every role', () {
      final s = summary(
        stage: ReviewStage.completed,
        status: StageStatus.submitted,
      );
      for (final role in UserRole.values) {
        expect(s.needsActionBy(role), isFalse,
            reason: 'completed reviews should never badge — $role');
      }
    });

    test('per stage → role wiring — each stage lights up for exactly the '
        'roles agreed in the pipeline spec', () {
      const table = <ReviewStage, Set<UserRole>>{
        ReviewStage.selfRating: {UserRole.employee},
        ReviewStage.accountHrRating: {UserRole.hr, UserRole.finance},
        ReviewStage.reportingManagerRating: {UserRole.manager},
        ReviewStage.managementReview: {UserRole.admin, UserRole.hrAdmin},
        ReviewStage.incentivePayout: {UserRole.finance, UserRole.hr},
      };
      for (final entry in table.entries) {
        final s = summary(stage: entry.key);
        for (final role in UserRole.values) {
          final shouldBadge = entry.value.contains(role);
          expect(
            s.needsActionBy(role),
            shouldBadge,
            reason:
                '${entry.key.name} for role $role — expected $shouldBadge',
          );
        }
      }
    });
  });
}
