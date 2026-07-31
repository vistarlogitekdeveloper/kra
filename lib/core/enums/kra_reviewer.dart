/// Which single reviewer owns a KRA in the Review cycle.
///
/// A KRA is defined "in three parts" — each KRA item is assigned to exactly ONE
/// of these three reviewers, who alone rates it during the Review cycle. Its
/// Review score is that reviewer's rating (not an average). This maps onto the
/// three Review-cycle [ReviewStage] raters:
///   * [reportingManager] → REPORTING_MANAGER_RATING (a relationship: the
///     employee's own reporting manager, whatever their role)
///   * [hr]               → ACCOUNT_HR_RATING (role: HR / HR_ADMIN)
///   * [accounts]         → FINANCE_RATING (role: FINANCE)
///
/// Kept dependency-free (no ReviewStage import) so both the HR template models
/// and the reviews models can use it; the ReviewStage mapping lives next to
/// [MonthlyKraRow] where ReviewStage is already in scope.
enum KraReviewer {
  reportingManager,
  hr,
  accounts;

  /// UPPER_SNAKE wire form. Tolerant of the aliases the backend/score_source
  /// vocabulary uses (MANAGER, HR_FEED, ACCOUNTS_FEED, FINANCE). Returns null
  /// for blank/unknown so an unassigned KRA stays unassigned.
  static KraReviewer? fromApi(String? value) {
    final raw = (value ?? '').trim().toUpperCase().replaceAll('-', '_');
    switch (raw) {
      case 'REPORTING_MANAGER':
      case 'REPORTING_MANAGER_RATING':
      case 'MANAGER':
      case 'RM':
        return KraReviewer.reportingManager;
      case 'HR':
      case 'HR_FEED':
      case 'HR_RATING':
      case 'ACCOUNT_HR':
      case 'ACCOUNT_HR_RATING':
        return KraReviewer.hr;
      case 'ACCOUNTS':
      case 'ACCOUNT':
      case 'ACCOUNTS_FEED':
      case 'FINANCE':
      case 'FINANCE_RATING':
        return KraReviewer.accounts;
      default:
        return null;
    }
  }

  String toApiString() {
    switch (this) {
      case KraReviewer.reportingManager:
        return 'REPORTING_MANAGER';
      case KraReviewer.hr:
        return 'HR';
      case KraReviewer.accounts:
        return 'ACCOUNTS';
    }
  }

  /// The value for the backend's `score_source` column, which is the KRA
  /// module's real per-KRA reviewer designation. Its enum is fixed
  /// (`MANAGER | HR_FEED | OPS_FEED | ACCOUNTS_FEED`) and the template API
  /// REJECTS anything else, so the reviewer MUST be sent in this vocabulary to
  /// persist. [fromApi] reads these back.
  String toScoreSource() {
    switch (this) {
      case KraReviewer.reportingManager:
        return 'MANAGER';
      case KraReviewer.hr:
        return 'HR_FEED';
      case KraReviewer.accounts:
        return 'ACCOUNTS_FEED';
    }
  }

  /// Full label for dropdowns and detail views.
  String get label {
    switch (this) {
      case KraReviewer.reportingManager:
        return 'Reporting Manager';
      case KraReviewer.hr:
        return 'HR';
      case KraReviewer.accounts:
        return 'Accounts';
    }
  }

  /// Compact label for the tight review-grid badge.
  String get shortLabel {
    switch (this) {
      case KraReviewer.reportingManager:
        return 'Manager';
      case KraReviewer.hr:
        return 'HR';
      case KraReviewer.accounts:
        return 'Accounts';
    }
  }

  /// Ultra-compact tag (≤4 chars) for the tiny per-month Review cell, where a
  /// full label won't fit. Pairs with a clock icon to read as "… pending".
  String get cellTag {
    switch (this) {
      case KraReviewer.reportingManager:
        return 'Mgr';
      case KraReviewer.hr:
        return 'HR';
      case KraReviewer.accounts:
        return 'Acct';
    }
  }
}
