/// All user-facing strings. Centralizing these makes future
/// localization (Hindi, Marathi) trivial — just swap this file.
class AppStrings {
  AppStrings._();

  // ───── App ─────
  static const String appName = 'Vistar';
  static const String appTagline = 'KRA Review & Incentive Management';
  static const String companyName = 'Vistar Logitek Pvt. Ltd.';

  // ───── Login screen ─────
  static const String loginWelcome = 'Welcome back';
  static const String loginSubtitle = 'Sign in to continue to your dashboard';
  static const String loginEmailLabel = 'Email';
  static const String loginEmailHint = 'you@vistar.com';
  static const String loginPasswordLabel = 'Password';
  static const String loginPasswordHint = 'Enter your password';
  static const String loginRememberMe = 'Remember me';
  static const String loginForgotPassword = 'Forgot password?';
  static const String loginButton = 'Sign In';
  static const String loginFooter = 'Need help? Contact HR at hr@vistar.com';
  static const String loginForgotComingSoon =
      'Password reset is coming soon. For now, please contact HR.';

  // ───── Dashboard ─────
  static const String dashboardLogoutTooltip = 'Logout';

  // ───── Validation ─────
  static const String validationEmailRequired = 'Please enter your email';
  static const String validationEmailInvalid =
      'Please enter a valid email address';
  static const String validationPasswordRequired = 'Please enter your password';
  static const String validationPasswordTooShort =
      'Password must be at least 8 characters';
  static const String validationRequired = 'This field is required';
  static const String validationNumberRequired = 'Please enter a number';
  static const String validationWeightageRange =
      'Weightage must be between 0 and 100';

  // ───── Connectivity ─────
  static const String offlineBanner = 'No internet connection';
  static const String offlineLoginDisabled =
      'You\'re offline. Reconnect to sign in.';

  // ───── Loading ─────
  static const String slowLoadHint =
      'Waking up the server… this can take up to a minute on the first load.';

  // ───── Errors (fallback / generic) ─────
  static const String errorGeneric = 'Something went wrong. Please try again.';
  static const String errorSessionEnded =
      'Your session has ended. Please sign in again.';

  // ───── Common ─────
  static const String commonSave = 'Save';
  static const String commonCancel = 'Cancel';
  static const String commonDelete = 'Delete';
  static const String commonEdit = 'Edit';
  static const String commonAdd = 'Add';
  static const String commonNext = 'Next';
  static const String commonBack = 'Back';
  static const String commonConfirm = 'Confirm';
  static const String commonSearch = 'Search';
  static const String commonClose = 'Close';
  static const String commonRetry = 'Retry';
  static const String commonRefresh = 'Refresh';
  static const String commonContinue = 'Continue';
  static const String commonDiscard = 'Discard';
  static const String commonView = 'View';
  static const String commonAll = 'All';
  static const String commonNone = 'None';
  static const String commonSelect = 'Select';
  static const String commonClone = 'Duplicate';
  static const String commonOptional = 'Optional';
  static const String commonComingSoon = 'Coming soon';

  // ───── Route error / not-found ─────
  static const String routeErrorTitle = 'Page not available';
  static const String routeErrorMessage =
      "This page isn't available yet. Let's get you back on track.";
  static const String routeErrorGoHome = 'Go to Home';

  // ───── HR shell / bottom nav ─────
  static const String hrShellHome = 'Home';
  static const String hrShellEmployees = 'Employees';
  static const String hrShellTemplates = 'Templates';
  static const String hrShellReviews = 'Reviews';
  static const String hrShellReports = 'Reports';

  // ───── HR home ─────
  static const String hrHomeTitle = 'HR Dashboard';
  static const String hrHomeWelcome = 'Welcome back,';
  static const String hrHomeNoActiveCycle = 'No active review cycle';
  static const String hrHomeStartFirstCycle =
      'Create a review cycle to begin tracking incentives.';
  static const String hrHomeStatActiveEmployees = 'Active Employees';
  static const String hrHomeStatSelfRated = 'Self-Rated This Month';
  static const String hrHomeStatManagerApproved = 'Manager Approved';
  static const String hrHomeStatQuarterPayout = 'Quarter Payout';
  static const String hrHomeQuickActions = 'Quick Actions';
  static const String hrHomeRecentActivity = 'Recent Activity';
  static const String hrHomeQuickAddEmployee = 'Add Employee';
  static const String hrHomeQuickCreateTemplate = 'Create Template';
  static const String hrHomeQuickAssignKra = 'Assign KRAs';
  static const String hrHomeQuickReviews = 'Monthly Reviews';
  static const String hrHomeNoActivity = 'No recent activity yet.';
  static const String hrHomeDaysRemaining = 'days remaining';
  static const String hrHomeDayRemaining = 'day remaining';
  static const String hrHomeCycleEnded = 'Cycle ended';

  // ───── Employees ─────
  static const String employeesTitle = 'Employees';
  static const String employeesSearchHint = 'Search by name, code, or email';
  static const String employeesFilterAll = 'All roles';
  static const String employeesFilterStatusAll = 'Any status';
  static const String employeesFilterStatusActive = 'Active only';
  static const String employeesFilterStatusInactive = 'Inactive only';
  static const String employeesEmptyTitle = 'No employees yet';
  static const String employeesEmptyMessage =
      'Add your first employee to get started.';
  static const String employeesEmptyCta = 'Add Employee';
  static const String employeesNoSearchResults = 'No matching employees';
  static const String employeesNoSearchHint = 'Try a different search term.';
  static const String employeesActive = 'Active';
  static const String employeeDetailAssignKra = 'Assign KRA';
  static const String employeeDetailEditProfile = 'Edit Profile';
  static const String hrHeatmapMonthlyBreakdown = 'Monthly breakdown';
  static const String hrHeatmapAverage = 'Cycle average';
  static const String hrHeatmapReviewsCount = 'reviews';
  static const String hrHeatmapViewEmployees = 'View employees here';
  static const String employeesInactive = 'Inactive';
  static const String employeesActionEdit = 'Edit';
  static const String employeesActionDeactivate = 'Deactivate';
  static const String employeesDeactivateConfirmTitle = 'Deactivate employee?';
  static const String employeesDeactivateConfirmMessage =
      'They will lose access immediately. You can reactivate from the master record later.';
  static const String employeesDeactivateSuccess = 'Employee deactivated.';
  static const String employeesDeactivateFailed =
      'Could not deactivate. Please try again.';
  static const String employeesLoadMoreFailed =
      'Could not load more employees. Tap to retry.';

  // ───── Employee form ─────
  static const String employeeFormCreateTitle = 'Add Employee';
  static const String employeeFormEditTitle = 'Edit Employee';
  static const String employeeFormSectionBasics = 'Basic details';
  static const String employeeFormSectionEmployment = 'Employment';
  static const String employeeFormCode = 'Employee code';
  static const String employeeFormCodeHint = 'e.g. VIS-1042';
  static const String employeeFormFullName = 'Full name';
  static const String employeeFormEmail = 'Work email';
  static const String employeeFormRole = 'Role';
  static const String employeeFormDepartment = 'Department';
  static const String employeeFormProjectLocation = 'Project location';
  static const String employeeFormManager = 'Reporting manager';
  static const String employeeFormGrade = 'Grade';
  static const String employeeFormJoinedDate = 'Joining date';
  static const String employeeFormUnsavedTitle = 'Discard changes?';
  static const String employeeFormUnsavedMessage =
      'Your edits will be lost if you go back without saving.';
  static const String employeeFormSaved = 'Employee saved successfully.';
  static const String employeeFormCreated = 'Employee added successfully.';

  // ───── Employee detail ─────
  static const String employeeDetailTitle = 'Employee Details';
  static const String employeeDetailViewAssignments = 'View KRA Assignments';

  // ───── KRA templates ─────
  static const String kraTemplatesTitle = 'KRA Templates';
  static const String kraTemplatesEmptyTitle = 'No templates yet';
  static const String kraTemplatesEmptyMessage =
      'Create a template to standardise KRAs across a role.';
  static const String kraTemplatesEmptyCta = 'Create Template';
  static const String kraTemplatesItems = 'KRAs';
  static const String kraTemplatesCloneSuccess = 'Template duplicated.';
  static const String kraTemplatesDeleteSuccess = 'Template deleted.';
  static const String kraTemplatesDeleteConfirmTitle = 'Delete template?';
  static const String kraTemplatesDeleteConfirmMessage =
      'This will not affect existing assignments, but the template can no longer be used for new ones.';

  // ───── KRA template form ─────
  static const String kraItemDeleteConfirmTitle = 'Remove this KRA?';
  static const String kraItemDeleteConfirmMessage =
      'This KRA item will be removed from the template. Nothing is saved until you tap Save.';
  static const String kraTemplateFormCreateTitle = 'Create KRA Template';
  static const String kraTemplateFormEditTitle = 'Edit KRA Template';
  static const String kraTemplateFormName = 'Template name';
  static const String kraTemplateFormNameHint = 'e.g. Sales Manager — Q4';
  static const String kraTemplateFormRole = 'Applies to role';
  static const String kraTemplateFormDescription = 'Description (optional)';
  static const String kraTemplateFormItemsHeader = 'KRAs';
  static const String kraTemplateFormAddItem = 'Add KRA item';
  static const String kraTemplateFormItemName = 'KRA name';
  static const String kraTemplateFormItemDescription = 'Description';
  static const String kraTemplateFormItemTarget = 'Target';
  static const String kraTemplateFormItemTracking = 'Tracking method';
  static const String kraTemplateFormItemWeightage = 'Weightage %';
  static const String kraTemplateFormSaved = 'Template saved.';
  static const String kraTemplateFormItemsRequired =
      'Add at least one KRA item.';

  // ───── Weightage indicator ─────
  static const String weightageOf = 'of';
  static const String weightagePercentSuffix = '%';
  static const String weightageInvalidLabel = 'Total must equal 100%';
  static const String weightageValidLabel = 'Weightage balanced';

  // ───── Assign KRAs wizard ─────
  static const String kraAssignTitle = 'Assign KRAs';
  static const String kraAssignStep1 = 'Pick employees';
  static const String kraAssignStep2 = 'Pick template';
  static const String kraAssignStep3 = 'Review & confirm';
  static const String kraAssignStep1Hint =
      'Select one or more employees to receive these KRAs.';
  static const String kraAssignStep2Hint =
      'Choose a template — items and weightages will be snapshotted.';
  static const String kraAssignStep3Hint =
      'Confirm the assignment for the selected cycle.';
  static const String kraAssignNoTemplate = 'No matching templates found.';
  static const String kraAssignNoCycle = 'No active review cycle yet.';
  static const String kraAssignSuccessOne = 'KRAs assigned to 1 employee.';
  static const String kraAssignSuccessMany =
      'KRAs assigned to {count} employees.';
  static const String kraAssignSelectCycle = 'Cycle';

  // ───── Review cycles ─────
  static const String reviewCyclesTitle = 'Review Cycles';
  static const String reviewCyclesEmptyTitle = 'No review cycles yet';
  static const String reviewCyclesEmptyMessage =
      'Create your first cycle to start the quarterly review workflow.';
  static const String reviewCyclesEmptyCta = 'New Review Cycle';
  static const String reviewCyclesActivate = 'Activate';
  static const String reviewCyclesClose = 'Close cycle';
  // Admin-only bulk delete (deletes every cycle, including active ones).
  static const String reviewCyclesDeleteAllTooltip = 'Delete all cycles';
  static const String reviewCyclesDeleteAllTitle = 'Delete ALL review cycles?';
  static const String reviewCyclesDeleteAllMessage =
      'Permanently removes every review cycle — including any that are '
      'active — along with all assignments and reviews tied to them. This '
      'cannot be undone.';
  static const String reviewCyclesDeleteAllConfirm = 'Delete all';
  static const String reviewCyclesActivateConfirmTitle = 'Activate this cycle?';
  static const String reviewCyclesActivateConfirmMessage =
      'Employees will be able to start self-rating once this cycle is active.';
  static const String reviewCyclesCloseConfirmTitle = 'Close this cycle?';
  static const String reviewCyclesCloseConfirmMessage =
      'Closed cycles are read-only. You will need to create a new cycle for the next quarter.';
  static const String reviewCyclesActivateSuccess = 'Cycle activated.';
  static const String reviewCyclesActivateFailed =
      'Could not activate cycle. Please try again.';
  static const String reviewCyclesCloseSuccess = 'Cycle closed.';
  static const String reviewCyclesCloseFailed =
      'Could not close cycle. Please try again.';

  // ───── Review cycle form ─────
  static const String reviewCycleFormCreateTitle = 'New Review Cycle';
  static const String reviewCycleFormEditTitle = 'Edit Review Cycle';
  static const String reviewCycleFormName = 'Cycle name';
  static const String reviewCycleFormNameHint = 'e.g. Q4 FY 2025-26';
  static const String reviewCycleFormStartDate = 'Start date';
  static const String reviewCycleFormEndDate = 'End date';
  static const String reviewCycleFormSelfRating = 'Self-rating deadline';
  static const String reviewCycleFormManagerReview = 'Manager review deadline';
  static const String reviewCycleFormOpsScoring = 'Ops scoring deadline';
  static const String reviewCycleFormFinanceScoring =
      'Finance scoring deadline';
  static const String reviewCycleFormDateOrder =
      'End date must be on or after start date.';
  static const String reviewCycleFormSaved = 'Review cycle saved.';

  // ───── Performance incentives (per employee) ─────
  static const String employeeFormIncentiveSection = 'Performance incentive';
  static const String employeeFormMonthlyIncentive = 'Monthly incentive amount';
  static const String employeeFormMonthlyIncentiveHint =
      'e.g. 5000 — leave blank to use the org default';
  static const String employeeDetailIncentiveTitle = 'Performance incentive';
  static const String employeeDetailMonthlyIncentive = 'Monthly incentive';
  static const String employeeDetailIncentiveNotSet = 'Not set (org default)';

  // Assign-from-detail quick action
  static const String employeeIncentiveSetCta = 'Set';
  static const String employeeIncentiveEditCta = 'Edit';
  static const String employeeIncentiveSheetTitle =
      'Assign performance incentive';
  static const String employeeIncentiveClear = 'Clear override';
  static const String employeeIncentiveSaved = 'Performance incentive updated.';

  // ───── Reports placeholder ─────
  static const String hrReportsTitle = 'Reports';
  static const String hrReportsComingSoonTitle = 'Reports — coming soon';
  static const String hrReportsComingSoonMessage =
      'Quarterly payout, score distribution, and exports will land in Step 7.';

  // ───── Dialogs / generic ─────
  static const String dialogYes = 'Yes';
  static const String dialogNo = 'No';
  static const String snackbarRetry = 'Retry';

  // ───── HR Drawer ─────
  static const String hrDrawerLocations = 'Locations';
  static const String hrDrawerBulkSetup = 'Bulk Setup';
  static const String hrDrawerAssignKras = 'Assign KRAs';
  static const String hrDrawerProfile = 'Profile';

  // ───── Locations ─────
  static const String locationsTitle = 'Locations';
  static const String locationsEmptyTitle = 'No locations yet';
  static const String locationsEmptyMessage =
      'Add a project location to assign employees and KRAs.';
  static const String locationsEmptyCta = 'Add Location';
  static const String locationFormCreateTitle = 'Add Location';
  static const String locationFormEditTitle = 'Edit Location';
  static const String locationFormName = 'Location name';
  static const String locationFormCode = 'Location code';
  static const String locationFormCity = 'City';
  static const String locationFormState = 'State';
  static const String locationFormAddress = 'Address';
  static const String locationFormCustomer = 'Customer';
  static const String locationDeleteConfirmTitle = 'Delete location?';
  static const String locationDeleteConfirmMessage =
      'Employees assigned here will need to be reassigned.';
  static const String locationDeleteSuccess = 'Location deleted.';
  static const String locationSaved = 'Location saved.';

  // ───── Bulk Setup wizard ─────
  static const String bulkSetupTitle = 'Bulk Setup';
  static const String bulkSetupStep1 = 'Filter Employees';
  static const String bulkSetupStep2 = 'Select Employees';
  static const String bulkSetupStep3 = 'Preview';
  static const String bulkSetupStep4 = 'Execute';
  static const String bulkSetupFindEmployees = 'Find Eligible Employees';
  static const String bulkSetupPreview = 'Preview';
  static const String bulkSetupExecute = 'Create Reviews';
  static const String bulkSetupConfirmTitle = 'Create reviews?';
  static const String bulkSetupConfirmMessage =
      'This will create KRA reviews for the selected employees. This cannot be undone.';
  static const String bulkSetupSuccess = 'Reviews created successfully.';
  static const String bulkSetupNoCycle = 'Please select a review cycle.';

  // ───── Audit Log ─────
  static const String auditLogTitle = 'Audit Log';
  static const String auditLogEmptyTitle = 'No audit entries';
  static const String auditLogEmptyMessage =
      'Changes made in the system will appear here.';
  static const String auditLogFilterActor = 'Actor';
  static const String auditLogFilterAction = 'Action';
  static const String auditLogFilterEntityType = 'Entity type';
  static const String auditLogFilterDateRange = 'Date range';
  static const String auditLogExportComingSoon = 'Export is coming in Step 7.';
  static const String auditLogViewDiff = 'View diff';

  // ───── HR Admin role-guard ─────
  static const String hrAdminOnlyMessage =
      'This section is only available to HR Admins.';

  // ───── KPI / Dashboard extras ─────
  static const String hrKpiActiveEmployees = 'Active Employees';
  static const String hrKpiPendingReviews = 'Pending Reviews';
  static const String hrKpiQuarterPayout = 'Quarter Payout';
  static const String hrKpiCompletion = 'Completion';
  static const String hrPipelineTitle = 'Review Pipeline';
  static const String hrActionItemsTitle = 'Needs your attention';
  static const String hrAllCaughtUp = 'All caught up! 🎉';
  static const String hrHeatmapTitle = 'Location Heatmap';
  static const String hrDeadlinesTitle = 'Upcoming Deadlines';
  static const String hrRecentActivityTitle = 'Recent Activity';
  static const String hrOverdue = 'OVERDUE';

  // ─────────────────────────────────────────────────────────────────
  // Employee Module
  // ─────────────────────────────────────────────────────────────────

  // ───── Employee shell / bottom nav ─────
  static const String employeeShellHome = 'Home';
  static const String employeeShellSelfRate = 'Self-Rate';
  static const String employeeShellHistory = 'History';
  static const String employeeShellProfile = 'Profile';

  // ───── Greeting ─────
  static const String greetingMorning = 'Good morning';
  static const String greetingAfternoon = 'Good afternoon';
  static const String greetingEvening = 'Good evening';
  static const String greetingNight = 'Good night';

  // ───── Home — current month card ─────
  static const String homeCurrentMonthTitle = 'Current month';
  static const String homeCurrentMonthSelfPending = 'Self-rating pending';
  static const String homeCurrentMonthSelfRated =
      'Self-submitted • Awaiting manager';
  static const String homeCurrentMonthManagerReviewed = 'Manager reviewed';
  static const String homeCurrentMonthFinalized = 'Finalized';
  static const String homeCurrentMonthStartRating = 'Start rating →';
  static const String homeCurrentMonthViewSubmission = 'View my submission';
  static const String homeCurrentMonthViewDetails = 'View details';
  static const String homeNoActiveCycleTitle = 'No active review cycle';
  static const String homeNoActiveCycleMessage =
      'Your HR team hasn\'t opened a cycle yet. Check back soon.';

  // ───── Home — KRAs summary ─────
  static const String homeMyKrasTitle = 'My KRAs';
  static const String homeMyKrasViewAll = 'View all';
  static const String homeMyKrasEmpty =
      'No KRAs assigned for this cycle. Contact HR.';
  static const String homeMyKrasItemsCountSingular = '1 item';
  // Plural form composed at the call-site: "$count items"

  // ───── Home — history strip ─────
  static const String homeHistoryStripTitle = 'Recent months';
  static const String homeHistoryStripPending = 'Pending';

  // ───── Home — incentive snapshot ─────
  static const String homeIncentiveTitle = 'My incentive this quarter';
  static const String homeIncentiveCaption =
      'Based on finalized reviews. Subject to change.';
  static const String homeIncentiveOf = 'of';

  // ───── Deadline banner ─────
  static const String deadlineSelfRatingClosesIn = 'Self-rating closes in';
  static const String deadlineDay = 'day';
  static const String deadlineDays = 'days';
  static const String deadlineOverdue = 'Self-rating overdue — submit now';

  // ───── Monthly deadline notices (self 7th / manager 10th) ─────
  static const String deadlineSelfRatingTitle = 'Self-rating deadline';
  static const String deadlineManagerRatingTitle = 'Manager rating deadline';

  // ───── Monthly reviews (new pipeline) ─────
  static const String monthlyReviewsTitleSelf = 'My Monthly Reviews';
  static const String monthlyReviewsTitleTeam = 'Team Monthly Reviews';
  static const String monthlyReviewsTitleAll = 'Monthly Reviews';
  static const String monthlyReviewsNavPreview = 'Monthly Reviews (preview)';
  static const String monthlyReviewsEmpty = 'No reviews for this month.';
  static const String monthlyReviewsNeedsYou = 'Needs you';
  static const String monthlyReviewsWaitingOn = 'Waiting on';
  static const String monthlyReviewStageDone = 'Done';
  static const String monthlyReviewSubmit = 'Submit rating';
  static const String monthlyReviewApprove = 'Approve';
  static const String monthlyReviewReturn = 'Return for rework';
  static const String monthlyReviewMarkPaid = 'Mark incentive paid';
  static const String monthlyReviewCommentLabel = 'Comment (optional)';
  static const String monthlyReviewScoreHint = 'Score';
  static const String monthlyReviewRemarkHint = 'Remark (optional)';
  static const String monthlyReviewSubmitted = 'Rating submitted.';
  static const String monthlyReviewApproved = 'Approved — sent to payout.';
  static const String monthlyReviewReturned =
      'Returned to the reporting manager.';
  static const String monthlyReviewPaid = 'Incentive marked as paid.';
  static const String monthlyReviewActionFailed =
      'Could not complete the action. Please try again.';
  static const String monthlyReviewProjectedPayout = 'Projected payout';
  static const String monthlyReviewEligible = 'Eligible amount';

  // ───── Self-Rate ─────
  static const String selfRateTitle = 'Rate yourself';
  static const String selfRateLiveTotal = 'Current total';
  static const String selfRateReviewCta = 'Review →';
  static const String selfRateMissingScore = 'Score required';
  static const String selfRateReasonLabel = 'Reason for your rating';
  static const String selfRateReasonHint =
      'Explain why you gave this score (200 chars max)';

  // ───── Self-rate attachment (proof) ─────
  static const String selfRateAttachmentLabel = 'Proof / attachment';
  static const String selfRateAttachmentAdd = 'Attach proof';
  static const String selfRateAttachmentReplace = 'Replace';
  static const String selfRateAttachmentRemoveTooltip = 'Remove attachment';
  static const String selfRateAttachmentPendingNote =
      'Saved with your draft. Upload to the server is coming soon.';
  static const String selfRateOverallCommentLabel =
      'Overall comment for the month';
  static const String selfRateScoreOutOfRange =
      'Score must be between 0 and the item\'s maximum.';
  static const String selfRateScoreRequired =
      'Please rate every KRA before submitting.';
  static const String selfRateUnsavedTitle = 'Unsaved changes';
  static const String selfRateUnsavedMessage =
      'You have unsaved changes. Leaving now will discard them.';
  static const String selfRateUnsavedSave = 'Save draft';
  static const String selfRateUnsavedDiscard = 'Discard';
  static const String commonKeepEditing = 'Keep editing';
  static const String selfRateResumeTitle = 'Resume your draft?';
  static const String selfRateResumeMessage =
      'You started rating earlier. Continue where you left off?';
  static const String selfRateResumeContinue = 'Continue';
  static const String selfRateResumeStartFresh = 'Start fresh';
  static const String selfRateConfirmTitle = 'Submit final rating?';
  static const String selfRateConfirmMessage =
      'Once submitted, you cannot change this until the manager reviews.';
  static const String selfRateConfirmSubmit = 'Submit final';
  static const String selfRateBackToEdit = 'Back to edit';
  static const String selfRateSubmitButton = 'Submit final';
  static const String selfRateSubmitting = 'Submitting…';
  static const String selfRateSuccessTitle = 'Submitted!';
  static const String selfRateSuccessSubtitle = 'Your manager will review by';
  static const String selfRateSuccessTotalLabel = 'Total submitted';
  static const String selfRateViewSubmission = 'View submission';
  static const String selfRateBackToHome = 'Back to home';
  static const String selfRateGoToHistory = 'Go to History';
  static const String selfRateLockedTitle = 'Submission locked';
  static const String selfRateLockedAwaitingManager = 'Awaiting manager review';
  static const String selfRateLockedPeriodClosed = 'Self-rating period closed';
  static const String selfRateLockedSubmittedOn = 'You submitted on';
  static const String selfRateLockedClosedOn = 'Self-rating period closed on';
  static const String selfRateOfflineTooltip = 'Internet required to submit';
  static const String selfRateDescriptionToggleShow = 'Show description';
  static const String selfRateDescriptionToggleHide = 'Hide description';
  static const String selfRateTargetLabel = 'Target';
  static const String selfRateTrackingLabel = 'Tracking';
  static const String selfRateCharCount = 'characters';

  // ───── Self-Rate server error mappings ─────
  static const String selfRateErrorAlreadyRated =
      'This review has already been submitted.';
  static const String selfRateErrorMonthLocked =
      'This month is locked. Please contact HR.';
  static const String selfRateErrorDeadlinePassed =
      'Self-rating period has closed for this month.';
  static const String selfRateErrorScoreOutOfRange =
      'One or more scores are outside the allowed range.';
  static const String selfRateErrorIncompleteScores =
      'Please rate every KRA before submitting.';

  // ───── History ─────
  static const String historyTitle = 'My reviews';
  static const String historyFilterAll = 'All';
  static const String historyFilterPending = 'Pending';
  static const String historyFilterFinalized = 'Finalized';
  static const String historyEmptyTitle = 'No reviews yet';
  static const String historyEmptyMessage =
      'Once a cycle is finalized, your monthly reviews will appear here.';
  static const String historyScoreSelf = 'Self';
  static const String historyScoreManager = 'Manager';
  static const String historyScoreOps = 'Ops';
  static const String historyScoreFinance = 'Finance';
  static const String historyScoreFinal = 'Final';
  static const String historyScoreNotApplicable = '—';
  static const String historyEarnedLabel = 'Earned';
  static const String historyDetailTotalRow = 'Total';
  static const String historyDetailIncentiveLabel = 'Incentive earned';
  static const String historyDetailEditSubmission = 'Edit submission';
  static const String historyDetailNoComment = 'No comment';
  static const String historyDetailCycleFilter = 'Cycle';
  static const String historyTimelineDraft = 'Draft';
  static const String historyTimelineSelfRated = 'Self-rated';
  static const String historyTimelineManagerReviewed = 'Manager';
  static const String historyTimelineOpsScored = 'Ops';
  static const String historyTimelineFinanceScored = 'Finance';
  static const String historyTimelineFinalized = 'Finalized';

  // ───── Profile ─────
  static const String profileTitle = 'My profile';
  static const String profileSectionContact = 'Contact';
  static const String profileSectionReporting = 'Reporting';
  static const String profileSectionDefaults = 'Defaults';
  static const String profileFieldEmail = 'Email';
  static const String profileFieldPhone = 'Phone';
  static const String profileFieldGrade = 'Grade';
  static const String profileFieldEmployeeCode = 'Employee code';
  static const String profileFieldRole = 'Role';
  static const String profileFieldDepartment = 'Department';
  static const String profileFieldLocation = 'Location';
  static const String profileFieldManager = 'Manager';
  static const String profileFieldDefaultTemplate = 'Default template';
  static const String profileFieldMonthlyIncentive = 'Monthly incentive';
  static const String profileEditTitle = 'Edit profile';
  static const String profileEditPhotoLabel = 'Profile photo';
  static const String profileEditPhotoComingSoon = 'Coming soon';
  static const String profileEditPhoneInvalid =
      'Please enter a valid 10-digit phone number.';
  static const String profileEditSaved = 'Profile updated.';
  static const String profileLogout = 'Log out';
  static const String profileLogoutConfirmTitle = 'Log out?';
  static const String profileLogoutConfirmMessage =
      'You\'ll need to sign in again on next launch.';
  static const String profileViewReportingTree = 'View reporting tree';
  static const String profileReportingTreeTitle = 'Reporting tree';
  static const String profileReportingTreeMyManager = 'My manager';
  static const String profileReportingTreeMyReports = 'My reports';
  static const String profileReportingTreeNoManager =
      'You don\'t have a manager assigned.';
  static const String profileReportingTreeNoReports = 'No one reports to you.';

  // ───── Empty / shared ─────
  static const String emptyDashboardTitle = 'Nothing to show yet';
  static const String emptyDashboardMessage =
      'Once your HR team activates a cycle, your dashboard will populate here.';

  // ─────────────────────────────────────────────────────────────────
  // Manager Module
  // ─────────────────────────────────────────────────────────────────

  // ───── Mode switcher ─────
  static const String managerModeMyTeam = 'My Team';
  static const String managerModeMyReview = 'My Review';

  // ───── Bottom nav — My Team ─────
  static const String managerTeamNavDashboard = 'Dashboard';
  static const String managerTeamNavTeam = 'Team';
  static const String managerTeamNavHistory = 'History';
  static const String managerTeamNavProfile = 'Profile';

  // ───── Dashboard ─────
  static const String managerDashboardTitle = 'Manager dashboard';
  static const String managerDashboardStatTotal = 'Total reports';
  static const String managerDashboardStatPending = 'Pending my review';
  static const String managerDashboardStatCompleted = 'Completed this month';
  static const String managerDashboardStatOverdue = 'Overdue';
  static const String managerDashboardPendingTitle = 'Awaiting your review';
  static const String managerDashboardAllCaughtUp = 'All caught up! 🎉';
  static const String managerDashboardViewAll = 'View all';
  static const String managerDashboardSubmittedAgo = 'submitted';
  static const String managerDashboardTrendTitle = 'Last cycle highlights';
  static const String managerDashboardTrendAverage = 'Average team score';
  static const String managerDashboardTrendHighest = 'Highest';
  static const String managerDashboardTrendLowest = 'Lowest';
  static const String managerDashboardTrendCompletion = 'Completion rate';
  static const String managerDashboardActiveCycle = 'Active cycle';
  static const String managerDashboardManagerDeadline =
      'Manager review deadline';
  static const String managerDashboardNoReportsTitle =
      'You don\'t manage any team members';
  static const String managerDashboardNoReportsMessage =
      'You\'re set up as a manager but no direct reports are assigned to you yet. Switch to "My Review" to rate yourself, or contact HR.';
  static const String managerDashboardNoReportsCta = 'Go to My Review';

  // ───── Team list ─────
  static const String managerTeamTitle = 'My team';
  static const String managerTeamSearchHint = 'Search by name or code';
  static const String managerTeamFilterAll = 'All';
  static const String managerTeamFilterPending = 'Pending My Review';
  static const String managerTeamFilterCompleted = 'Completed';
  static const String managerTeamFilterNotSubmitted = 'Not Submitted';
  static const String managerTeamFilterOverdue = 'Overdue';
  static const String managerTeamEmptyAll =
      'Your team list is empty. Reach out to HR if this is unexpected.';
  static const String managerTeamEmptyPending =
      'No one is waiting for your review right now. 🎉';
  static const String managerTeamEmptyCompleted =
      'You haven\'t completed any reviews this cycle yet.';
  static const String managerTeamEmptyNotSubmitted =
      'All your team members have started their reviews.';
  static const String managerTeamEmptyOverdue =
      'No overdue reviews — great job staying on top of things!';
  static const String managerTeamStateNotStarted = 'Not Started';
  static const String managerTeamStateInProgress = 'In Progress';
  static const String managerTeamStateReadyForReview = 'Ready for Review';
  static const String managerTeamStateYouRated = 'You Rated';
  static const String managerTeamStateFinalized = 'Finalized';
  static const String managerTeamStateOverdue = 'Overdue';
  static const String managerTeamBulkSelectMode = 'Select to approve';
  static const String managerTeamBulkApproveCta = 'Approve';
  static const String managerTeamBulkOnlyPending =
      'Only "Ready for Review" reviews can be approved here.';
  static const String managerTeamBulkSelectedCount = 'selected';

  // ───── Team member profile ─────
  static const String managerProfileTabProfile = 'Profile';
  static const String managerProfileTabCurrent = 'Current Review';
  static const String managerProfileTabHistory = 'History';
  static const String managerProfileFySummary = 'This year';
  static const String managerProfileFyTotalReviews = 'Total reviews';
  static const String managerProfileFyFinalized = 'Finalized';
  static const String managerProfileFyPending = 'Pending';
  static const String managerProfileFyAverage = 'Avg. final score';
  static const String managerProfileNoCurrentReview =
      'No review assigned for the active cycle.';

  // ───── Review detail ─────
  static const String managerReviewDetailTitle = 'Review detail';
  static const String managerReviewDetailStartRating = 'Start rating';
  static const String managerReviewDetailEditRating = 'Edit my rating';
  static const String managerReviewDetailWaitingTitle =
      'Waiting for self-rating';
  static const String managerReviewDetailWaitingMessage =
      'hasn\'t finished their self-rating yet. You\'ll be able to rate once they submit.';
  static const String managerReviewDetailNotStartedTitle =
      'Hasn\'t started yet';
  static const String managerReviewDetailNotStartedMessage =
      'hasn\'t opened their self-rating for this cycle.';
  static const String managerReviewDetailFinalizedTitle = 'Finalized';
  static const String managerReviewDetailIncentive = 'Incentive earned';
  static const String managerReviewDetailManagerComment =
      'Your overall comment';
  static const String managerReviewDetailPreviousReviews = 'Previous reviews';
  static const String managerReviewDetailWaitingForEmployee =
      'Employee hasn\'t submitted their self-rating yet. You\'ll be able to rate once they finish.';
  static const String managerReviewDetailWindowClosed =
      'The manager-review window is closed. Contact HR if you need to re-open this review.';
  static const String managerReviewDetailFinalisedReadOnly =
      'This review has been finalised. Scores are read-only.';

  // ───── Manager-rate matrix ─────
  static const String managerRateTitle = 'Rate';
  static const String managerRateTotalLabel = 'Weighted total';
  static const String managerRateSelfChipPrefix = 'Self:';
  static const String managerRateRemarkHint =
      'Optional comment for this cell (200 char max)';
  static const String managerRateCommentLabel = 'Your overall comment';
  static const String managerRateCommentHint =
      'Leave an overall comment for the employee…';
  static const String managerRateReadOnlyLocked = 'Locked';
  static const String managerRateReadOnlyAuto = 'Auto';
  static const String managerRateOutOfRange =
      'Score must be between 0 and the item\'s maximum.';
  static const String managerRateIncompleteScores =
      'Rate every applicable cell before submitting.';
  static const String managerRateAutoSavedLabel = 'Saved';
  static const String managerRateAutoSavingLabel = 'Saving…';
  static const String managerRateAutoSaveFailed = 'Couldn\'t save — retrying';
  static const String managerRateRetry = 'Retry';
  static const String managerRateReviewCta = 'Review';
  static const String managerRateReviewTitle = 'Review your ratings';
  static const String managerRateSubmitCta = 'Submit final';
  static const String managerRateBackToEdit = 'Back to edit';
  static const String managerRateUnsavedTitle = 'Save in progress';
  static const String managerRateUnsavedMessage =
      'Auto-save is still in flight. Leave anyway? Your most recent edits may not be saved.';
  static const String managerRateConfirmTitle = 'Submit this review?';
  static const String managerRateConfirmMessage =
      'Once submitted, you cannot change scores unless you reopen within the deadline.';
  static const String managerRateOfflineTooltip = 'Internet required to submit';
  static const String managerRateDeadlineWarning =
      'Manager review deadline approaching';
  static const String managerRateDeadlinePassed =
      'Manager review deadline has passed';
  static const String managerRateSuccessTitle = 'Review submitted ✓';
  static const String managerRateSuccessSubtitle = 'Your rating is locked in.';
  static const String managerRateSuccessViewSubmission = 'View submission';
  static const String managerRateSuccessBackToTeam = 'Back to team';
  static const String managerRatePartialTitle = 'Saved — review not finalised';
  static const String managerRatePartialSubtitle =
      'Your scores are saved. The review can\'t move forward yet:';
  static const String managerRatePartialTryAgain = 'Try submit again';
  static const String managerRatePartialBackToReview = 'Back to review';

  // ───── Submit response code → user message mapping ─────
  static const String managerRateErrorIncompleteAfterCopy =
      'Ops or Finance hasn\'t filled in some scores yet.';
  static const String managerRateErrorMonthLocked =
      'One of the months in this review is locked.';
  static const String managerRateErrorDeadlinePassed =
      'Review deadline has passed.';

  // ───── Bulk approve ─────
  static const String bulkApproveTitle = 'Approve reviews';
  static const String bulkApproveCount = 'Approve {count} reviews?';
  static const String bulkApproveOptionalComment =
      'Optional comment (applies to all)';
  static const String bulkApproveCommentHint =
      'Add a short note to every approved review…';
  static const String bulkApproveWarning =
      'This copies the employee\'s self-ratings as your ratings for items you score. Items scored by Ops/Finance are not affected.';
  static const String bulkApproveConfirmCta = 'Confirm & Approve';
  static const String bulkApproveResultTitle = 'Approval result';
  static const String bulkApproveResultApproved = 'Approved';
  static const String bulkApproveResultSkipped = 'Skipped';
  static const String bulkApproveResultAllSuccess = 'All reviews approved.';
  static const String bulkApproveResultSomeSkipped =
      '{approved} approved, {skipped} skipped';
  static const String bulkApproveDone = 'Done';
  static const String bulkSkipReasonIncomplete =
      'Ops or Finance hasn\'t filled in their scores yet — you\'ll need to wait or rate manually.';
  static const String bulkSkipReasonNotSubmitted =
      'Employee hasn\'t finished their self-rating.';
  static const String bulkSkipReasonDeadlinePassed =
      'Review deadline has passed.';
  static const String bulkSkipReasonOther =
      'This review couldn\'t be approved.';

  // ───── Bulk approve confirm / result ─────
  static const String managerBulkApproveTitle = 'Bulk approve';
  static const String managerBulkApproveSelected = 'SELECTED REVIEWS';
  static const String managerBulkApproveCommentLabel =
      'Overall comment (applied to all)';
  static const String managerBulkApproveCommentHint =
      'Optional — leave blank to skip';
  static const String managerBulkApproveCta = 'Approve all';
  static const String managerBulkApproveConfirmTitle = 'Approve these reviews?';
  static const String managerBulkApproveConfirmMessage =
      'Reviews that can be finalised will transition to MANAGER_RATED_ALL. Others will be skipped with a reason — you can rate them individually afterwards.';
  static const String managerBulkApproveResultCleanTitle =
      'All reviews approved ✓';
  static const String managerBulkApproveResultMixedTitle = 'Partial approve';
  static const String managerBulkApproveResultAllSkippedTitle =
      'No reviews approved';
  static const String managerBulkApproveApprovedCount = 'APPROVED';
  static const String managerBulkApproveSkippedCount = 'SKIPPED';
  static const String managerBulkApproveBackToTeam = 'Back to team';
  static const String managerBulkApproveRateIndividually =
      'Rate skipped individually';

  // ───── Manager profile (mode switcher) ─────
  static const String managerProfileTitle = 'Profile';
  static const String managerProfileModeSectionLabel = 'VIEW MODE';
  static const String managerProfileModeMyTeam = 'My Team';
  static const String managerProfileModeMyReview = 'My Review';

  // ───── Team history ─────
  static const String managerHistoryTitle = 'Team history';
  static const String managerHistoryEmptyTitle = 'Pick a team member';
  static const String managerHistoryEmptyMessage =
      'Open a team member from the Team tab to see their quarterly '
      'review history.';
  static const String managerHistoryOpenTeam = 'Open Team';

  // ───── Drawer / shared ─────
  static const String hrDrawerSwitchToManager = 'Switch to Manager view';
}
