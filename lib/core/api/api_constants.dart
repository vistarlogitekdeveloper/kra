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
  // Defaults to the Render-hosted test env. Override it to point the app at a
  // backend you're running yourself:
  //
  //   flutter run -d chrome --dart-define=API_BASE=http://localhost:3000/api/v1/kra/
  //
  // This matters more than it looks: running the APP locally does NOT make the
  // backend local — without an override, a locally-run app still talks to the
  // deployed Render server. So server-side work (new columns, new routes) is
  // invisible to local testing until it's either deployed OR pointed at here.
  // Trailing slash included; Dio joins relative endpoint paths onto it.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://vistar-crm.onrender.com/api/v1/kra/',
  );
  static const String environment =
      String.fromEnvironment('ENV', defaultValue: 'test');

  // ───── Endpoint paths (relative to baseUrl) ─────
  static const String authLogin = '/auth/login';
  static const String authLogout = '/auth/logout';
  static const String authRefresh = '/auth/refresh';
  static const String authMe = '/auth/me';
  static const String authForgotPassword = '/auth/forgot-password';
  static const String authResetPassword = '/auth/reset-password';
  // Admin set-password is constructed: '$employees/$id/set-password'

  // HR module endpoints
  static const String employees = '/employees';
  static const String locations = '/locations';
  static const String kraTemplates = '/kra-templates';
  static const String kraAssignments = '/kra-assignments';
  static const String kraAssignmentsBulk = '/kra-assignments/bulk';
  static const String reviewCycles = '/review-cycles';
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
  static const String managerBulkApprove = '/manager/reviews/bulk-approve';
  // Shared per-review scores endpoint used for manager auto-save.
  // Body must include `side: 'MANAGER'`.
  static const String reviewsScores = '/reviews';

  // ───── Monthly reviews (new 5-stage pipeline) ─────
  // Contract in docs/BACKEND_HANDOFF.md (PRIORITY 5). Sub-paths as actually
  // constructed by ApiMonthlyReviewRepository:
  //   GET  $monthlyReviews?year=&month=&currentStage=  → [MonthlyReviewSummary]
  //                                              (scoped server-side from JWT)
  //   GET  $monthlyReviews/:id                 → MonthlyReview
  //   POST $monthlyReviews/:id/submit-stage    → submit/advance a stage
  //   POST $monthlyReviews/:id/mark-paid        → mark incentive paid
  static const String monthlyReviews = '/reviews/monthly';

  // ───── Endpoints that should NOT have a Bearer token attached ─────
  // Marked via options.extra['skipAuth'] = true at the call site.
  // /auth/me explicitly is NOT in this list — it requires a valid
  // access token to identify the current user.
  static const Set<String> noAuthEndpoints = {
    authLogin,
    authRefresh,
    authForgotPassword,
    authResetPassword,
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
  // The backend is on Render's free tier, which sleeps after ~15 min of
  // inactivity and takes 30–60s to wake. Timeouts MUST exceed that or the
  // first request after idle dies before the server is up — which shows as
  // every page stuck on its loading shimmer. Keep connect/receive ≥ 60s.
  static const Duration connectTimeout = Duration(seconds: 60);
  static const Duration receiveTimeout = Duration(seconds: 60);
  static const Duration sendTimeout = Duration(seconds: 30);

  // ───── Response envelope keys ─────
  static const String envelopeSuccess = 'success';
  static const String envelopeData = 'data';
  static const String envelopeError = 'error';
  static const String envelopeErrorCode = 'code';
  static const String envelopeErrorMessage = 'message';
  static const String envelopeErrorDetails = 'details';
}
