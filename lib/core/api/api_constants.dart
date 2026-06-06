/// Single source of truth for backend connectivity.
///
/// To switch environments, change [_environment] below or pass
/// `--dart-define=ENV=staging` at build time:
///   flutter run --dart-define=ENV=dev
///   flutter build apk --dart-define=ENV=prod
class ApiConstants {
  ApiConstants._();

  // ───── Environment selection ─────
  //
  // There is only one backend today — the Render-hosted test env.
  // When staging / prod ship, restore the per-env map and read the
  // active key via `String.fromEnvironment('ENV')`. Until then,
  // pretending to switch envs via `--dart-define=ENV=...` is a no-op
  // and a footgun (callers assume something happens), so the switch
  // is collapsed to a single constant.
  static const String baseUrl = 'https://vistar-crm.onrender.com/api/v1/kra/';
  static const String environment = 'test';

  // ───── Endpoint paths (relative to baseUrl) ─────
  static const String authLogin = '/auth/login';
  static const String authLogout = '/auth/logout';
  static const String authRefresh = '/auth/refresh';
  static const String authMe = '/auth/me';

  // HR module endpoints
  static const String employees = '/employees';
  static const String locations = '/locations';
  static const String kraTemplates = '/kra-templates';
  static const String kraAssignments = '/kra-assignments';
  static const String kraAssignmentsBulk = '/kra-assignments/bulk';
  static const String reviewCycles = '/review-cycles';
  static const String bonusSlabs = '/bonus-slabs';
  static const String hrDashboard = '/hr/dashboard';

  // Employee module endpoints — every authenticated user, regardless of
  // role, hits this surface to rate themselves on their own KRAs.
  static const String employeeDashboard = '/employee/dashboard';
  static const String employeeKraAssignments = '/employee/kra-assignments';
  static const String employeeReviews = '/employee/reviews';
  static const String employeeIncentiveSummary = '/employee/incentive-summary';
  static const String employeeProfile = '/employee/profile';
  // Self-rate URLs are constructed: '$employeeReviews/$reviewId/self-rate'

  // Manager module endpoints — see lib/features/manager/. Per-review
  // and per-employee sub-paths are constructed by the repos.
  static const String managerDashboard = '/manager/dashboard';
  static const String managerTeam = '/manager/team';
  static const String managerReviews = '/manager/reviews';
  static const String managerBulkApprove =
      '/manager/reviews/bulk-approve';
  // Shared per-review scores endpoint used for manager auto-save.
  // Body must include `side: 'MANAGER'`.
  static const String reviewsScores = '/reviews';

  // ───── Endpoints that should NOT have a Bearer token attached ─────
  // Marked via options.extra['skipAuth'] = true at the call site.
  // /auth/me explicitly is NOT in this list — it requires a valid
  // access token to identify the current user.
  static const Set<String> noAuthEndpoints = {
    authLogin,
    authRefresh,
  };

  // ───── Endpoints that should NOT trigger refresh-and-retry on 401 ─────
  // The refresh interceptor consults this set before kicking off a
  // refresh. A 401 from /auth/logout (e.g. token already invalidated
  // server-side) shouldn't drag us through a refresh loop — local
  // cleanup runs unconditionally and that's enough.
  static const Set<String> noRefreshOn401Endpoints = {
    authLogin,
    authRefresh,
    authLogout,
  };

  // ───── Timeouts ─────
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
  static const Duration sendTimeout = Duration(seconds: 15);

  // ───── Response envelope keys ─────
  static const String envelopeSuccess = 'success';
  static const String envelopeData = 'data';
  static const String envelopeError = 'error';
  static const String envelopeErrorCode = 'code';
  static const String envelopeErrorMessage = 'message';
  static const String envelopeErrorDetails = 'details';
}
