import 'monthly_review.dart';
import 'review_stage.dart';

/// Whether a given reviewer has done their part on one review.
///
/// [notApplicable] is deliberately distinct from [no]: a KRA sheet assigns each
/// KRA to exactly ONE reviewer, so a sheet with no HR-assigned KRAs has nothing
/// for HR to review. Reporting that as "No" would read as an outstanding action
/// and send HR chasing work that does not exist.
enum ReviewerProgress { yes, no, notApplicable, notTracked }

/// One employee's row on the HR review-compliance report: who has reviewed and
/// who has not, for a single month.
///
/// Derived entirely from the full [MonthlyReview] — the list endpoint carries
/// only aggregate percentages, not per-reviewer detail, so this cannot be built
/// from summaries alone.
class ReviewComplianceRow {
  final String employeeId;
  final String employeeName;
  final String employeeCode;

  /// True once the employee has finished their self-rating.
  final bool selfSubmitted;

  final ReviewerProgress byReportingManager;
  final ReviewerProgress byHr;
  final ReviewerProgress byFinance;

  /// Ops Excellence is not a reviewer this app models — a KRA is owned by
  /// exactly one of Reporting Manager / HR / Accounts. The column exists so the
  /// report matches the sheet HR works from, but it reports [notTracked] rather
  /// than inventing a value.
  final ReviewerProgress byOpsExcellence;

  /// Management has signed the review off (locked, or scored the Management
  /// column). The last gate before payout.
  final bool finalApproval;

  const ReviewComplianceRow({
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    required this.selfSubmitted,
    required this.byReportingManager,
    required this.byHr,
    required this.byFinance,
    required this.byOpsExcellence,
    required this.finalApproval,
  });

  /// Reads one review into a report row.
  factory ReviewComplianceRow.from(MonthlyReview review) {
    return ReviewComplianceRow(
      employeeId: review.employeeId,
      employeeName: review.employeeName,
      employeeCode: review.employeeCode,
      selfSubmitted: _selfSubmitted(review),
      byReportingManager:
          _progressFor(review, ReviewStage.reportingManagerRating),
      byHr: _progressFor(review, ReviewStage.accountHrRating),
      byFinance: _progressFor(review, ReviewStage.financeRating),
      byOpsExcellence: ReviewerProgress.notTracked,
      finalApproval: _finalApproved(review),
    );
  }

  /// The employee has finished, by either proof:
  ///   * a Self-Rating stage record — the explicit Submit action; or
  ///   * the cursor having moved past Self-Rating, which is how a review looks
  ///     on a deployment that still auto-advances on save.
  ///
  /// Accepting both means the report is correct before AND after that backend
  /// change ships, instead of showing every employee as "Not submitted".
  static bool _selfSubmitted(MonthlyReview r) =>
      r.recordFor(ReviewStage.selfRating) != null ||
      r.currentStage.pipelineIndex > ReviewStage.selfRating.pipelineIndex;

  /// Done when every KRA assigned to [stage]'s reviewer carries a score.
  ///
  /// Partial work counts as NOT done: a reviewer who has scored three of eight
  /// KRAs still owes the other five, and reporting "Yes" would hide that.
  static ReviewerProgress _progressFor(MonthlyReview r, ReviewStage stage) {
    final owned = r.rows.where((row) => row.reviewStage == stage).toList();
    if (owned.isEmpty) return ReviewerProgress.notApplicable;
    final scored =
        owned.where((row) => row.scoreFor(stage)?.value != null).length;
    return scored == owned.length ? ReviewerProgress.yes : ReviewerProgress.no;
  }

  /// Signed off when management has locked the review, or has scored any KRA in
  /// the Management column, or the review has already run past that stage.
  static bool _finalApproved(MonthlyReview r) =>
      r.isManagementLocked ||
      r.rows.any((row) =>
          row.scoreFor(ReviewStage.managementReview)?.value != null) ||
      r.currentStage.pipelineIndex >
          ReviewStage.managementReview.pipelineIndex;

  /// True when nothing at all has happened yet — used to grey the row.
  bool get untouched =>
      !selfSubmitted &&
      !finalApproval &&
      byReportingManager != ReviewerProgress.yes &&
      byHr != ReviewerProgress.yes &&
      byFinance != ReviewerProgress.yes;
}
