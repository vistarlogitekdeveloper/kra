import '../../../auth/data/models/user.dart';
import 'monthly_review.dart';
import 'review_stage.dart';

/// Compact row for the monthly-review dashboards — enough to render a list
/// tile without loading every KRA score. Built from a [MonthlyReview].
class MonthlyReviewSummary {
  final String reviewId;
  final String employeeId;
  final String employeeName;
  final String employeeCode;
  final String? managerName;
  final ReviewPeriod period;
  final ReviewStage currentStage;
  final double finalScorePct;
  final PayoutStatus payoutStatus;

  const MonthlyReviewSummary({
    required this.reviewId,
    required this.employeeId,
    required this.employeeName,
    this.employeeCode = '',
    this.managerName,
    required this.period,
    required this.currentStage,
    this.finalScorePct = 0,
    this.payoutStatus = PayoutStatus.notReady,
  });

  /// True when [role] can act on this review right now (coarse role gate —
  /// the repository has already scoped the list to the user's own reviews /
  /// direct reports before handing it to the UI).
  bool needsActionFrom(UserRole role) =>
      !currentStage.isTerminal && currentStage.actorRoles.contains(role);

  factory MonthlyReviewSummary.fromReview(MonthlyReview r) =>
      MonthlyReviewSummary(
        reviewId: r.id,
        employeeId: r.employeeId,
        employeeName: r.employeeName,
        employeeCode: r.employeeCode,
        managerName: r.managerName,
        period: r.period,
        currentStage: r.currentStage,
        finalScorePct: r.finalScorePct,
        payoutStatus: r.payoutStatus,
      );
}
