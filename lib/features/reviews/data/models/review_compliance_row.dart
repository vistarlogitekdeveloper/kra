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
  ///   * every KRA carrying a self score, which is how a finished rating looks
  ///     on a deployment that advances the cursor on save without writing a
  ///     stage record.
  ///
  /// It deliberately does NOT accept the cursor being past Self-Rating. The
  /// stored stage can outrun the scores — that mismatch is why dashboards
  /// elsewhere resolve through `displayStage` rather than the raw cursor — and
  /// trusting it here reported "Submitted" for employees who had rated nothing,
  /// which is the one thing a chase-list must never get wrong.
  ///
  /// Partial work is not submitted, matching [_progressFor]: an employee who
  /// rated three of twelve KRAs still owes the other nine.
  static bool _selfSubmitted(MonthlyReview r) {
    if (r.recordFor(ReviewStage.selfRating) != null) return true;
    if (r.rows.isEmpty) return false;
    return r.rows
        .every((row) => row.scoreFor(ReviewStage.selfRating)?.value != null);
  }

  /// Done when every KRA assigned to [stage]'s reviewer carries a score.
  ///
  /// Partial work counts as NOT done: a reviewer who has scored three of eight
  /// KRAs still owes the other five, and reporting "Yes" would hide that.
  ///
  /// A KRA with NO assigned reviewer counts as the reporting manager's, which
  /// is the same default the KRA sheet applies. Leaving it unowned instead made
  /// this report disagree with the sheet HR works from: a review whose rows
  /// predate per-KRA assignment showed N/A in all three reviewer columns — the
  /// report claiming there was nothing to do, next to a sheet showing twelve
  /// KRAs awaiting the manager.
  ///
  /// "Scored" means a score with a VALUE. A reviewer who has only attached a
  /// reason or proof has not rated the KRA.
  static ReviewerProgress _progressFor(MonthlyReview r, ReviewStage stage) {
    final owned = r.rows
        .where((row) =>
            (row.reviewStage ?? ReviewStage.reportingManagerRating) == stage)
        .toList();
    if (owned.isEmpty) return ReviewerProgress.notApplicable;
    final scored =
        owned.where((row) => row.scoreFor(stage)?.value != null).length;
    return scored == owned.length ? ReviewerProgress.yes : ReviewerProgress.no;
  }

  /// Signed off when management has locked the review, has scored any KRA in
  /// the Management column, or has submitted the Management Review stage.
  ///
  /// All three are acts management actually performed. The cursor being past
  /// Management Review is NOT accepted, for the same reason as
  /// [_selfSubmitted]: the stored stage can outrun the work, and this column is
  /// the last gate before money moves.
  static bool _finalApproved(MonthlyReview r) =>
      r.isManagementLocked ||
      r.recordFor(ReviewStage.managementReview) != null ||
      r.rows.any(
          (row) => row.scoreFor(ReviewStage.managementReview)?.value != null);

  /// True when nothing at all has happened yet — used to grey the row.
  bool get untouched =>
      !selfSubmitted &&
      !finalApproval &&
      byReportingManager != ReviewerProgress.yes &&
      byHr != ReviewerProgress.yes &&
      byFinance != ReviewerProgress.yes;
}
