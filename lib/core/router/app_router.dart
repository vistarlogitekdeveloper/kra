import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/models/user.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/reset_password_screen.dart';
import '../../features/reviews/presentation/screens/admin_review_dashboard_screen.dart';
import '../../features/reviews/presentation/screens/monthly_review_dashboard_screen.dart';
import '../../features/reviews/presentation/screens/monthly_review_detail_screen.dart';
import '../../features/reviews/presentation/screens/quarterly_kra_sheet_screen.dart';
import '../widgets/route_error_screen.dart';
import '../../features/employee/presentation/screens/employee_shell_screen.dart';
import '../../features/employee/presentation/screens/history/my_reviews_history_screen.dart';
import '../../features/employee/presentation/screens/history/review_detail_screen.dart';
import '../../features/employee/presentation/screens/home/employee_home_screen.dart';
import '../../features/employee/presentation/screens/profile/edit_profile_screen.dart';
import '../../features/employee/presentation/screens/profile/my_profile_screen.dart';
import '../../features/employee/presentation/screens/profile/my_reporting_tree_screen.dart';
import '../../features/employee/presentation/screens/self_rate/self_rate_locked_screen.dart';
import '../../features/employee/presentation/screens/self_rate/self_rate_review_screen.dart';
import '../../features/employee/presentation/screens/self_rate/self_rate_success_screen.dart';
import '../../features/hr/presentation/screens/audit_log_screen.dart';
import '../../features/hr/presentation/screens/bulk_setup_screen.dart';
import '../../features/hr/presentation/screens/employee_detail_screen.dart';
import '../../features/hr/presentation/screens/employee_form_screen.dart';
import '../../features/hr/presentation/screens/employees_screen.dart';
import '../../features/hr/presentation/screens/hr_home_screen.dart';
import '../../features/hr/presentation/screens/hr_reports_screen.dart';
import '../../features/hr/presentation/screens/hr_shell_screen.dart';
import '../../features/hr/presentation/screens/kra_assign_screen.dart';
import '../../features/hr/presentation/screens/kra_template_form_screen.dart';
import '../../features/hr/presentation/screens/kra_templates_screen.dart';
import '../../features/hr/presentation/screens/locations_screen.dart';
import '../../features/manager/presentation/screens/manager_shell_screen.dart';
import '../../features/manager/presentation/screens/my_team/bulk_approve/bulk_approve_confirm_screen.dart';
import '../../features/manager/presentation/screens/my_team/bulk_approve/bulk_approve_result_screen.dart';
import '../../features/manager/presentation/screens/my_team/history/team_history_screen.dart';
import '../../features/manager/presentation/screens/my_team/history/team_member_history_screen.dart';
import '../../features/manager/presentation/screens/my_team/my_team_shell.dart';
import '../../features/manager/presentation/screens/my_team/profile/manager_profile_screen.dart';
import '../../features/manager/presentation/screens/my_team/rate/manager_rate_partial_success_screen.dart';
import '../../features/manager/presentation/screens/my_team/rate/manager_rate_review_screen.dart';
import '../../features/manager/presentation/screens/my_team/rate/manager_rate_screen.dart';
import '../../features/manager/presentation/screens/my_team/rate/manager_rate_success_screen.dart';
import '../../features/manager/presentation/screens/my_team/review/review_detail_screen.dart'
    as manager_review;
import '../../features/manager/presentation/screens/my_team/team/team_list_screen.dart';
import '../../features/manager/presentation/screens/my_team/team/team_member_profile_screen.dart';

/// Centralised route paths — never use raw strings at call sites.
class AppRoutes {
  AppRoutes._();

  static const String login = '/login';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';
  static const String employeeDashboard = '/employee';
  static const String managerDashboard = '/manager';
  static const String hrDashboard = '/hr';

  // ── Monthly reviews (new pipeline) — role-adaptive, top-level so any
  // login can reach it. Phase 3 wires these into the role shells.
  static const String monthlyReviews = '/reviews/monthly';
  static String monthlyReviewDetail(String id) => '/reviews/monthly/$id';

  // Quarterly KRA sheet — the per-employee 3-month sheet. No id → the
  // signed-in user's own sheet (employee self view).
  static const String reviewsQuarterly = '/reviews/quarterly';
  static String reviewsQuarterlyFor(String employeeId) =>
      '/reviews/quarterly/$employeeId';

  // ── Employee module nested routes ──
  // Every authenticated user (except ADMIN) lands inside /employee/* —
  // an HR person rates themselves on their own KRAs too.
  static const String employeeHome = '/employee/home';
  static const String employeeSelfRate = '/employee/self-rate';
  static const String employeeSelfRateReview = '/employee/self-rate/review';
  static const String employeeSelfRateSuccess = '/employee/self-rate/success';
  static const String employeeSelfRateLocked = '/employee/self-rate/locked';
  static const String employeeHistory = '/employee/history';
  static const String employeeProfile = '/employee/profile';
  static const String employeeProfileEdit = '/employee/profile/edit';
  static const String employeeReportingTree =
      '/employee/profile/reporting-tree';

  static String employeeReviewDetail(String reviewId) =>
      '/employee/history/$reviewId';

  // ── HR module nested routes ──
  static const String hrHome = '/hr/home';
  static const String hrEmployees = '/hr/employees';
  static const String hrEmployeeNew = '/hr/employees/new';
  static const String hrTemplates = '/hr/kra-templates';
  static const String hrTemplateNew = '/hr/kra-templates/new';
  static const String hrAssign = '/hr/assign';
  // Replaced the old review-cycles surface with the monthly reviews
  // dashboard (the HR "Reviews" tab).
  static const String hrReviews = '/hr/reviews';
  static const String hrReports = '/hr/reports';
  static const String hrLocations = '/hr/locations';
  static const String hrBulkSetup = '/hr/bulk-setup';
  static const String hrAuditLog = '/hr/reports/audit-log';

  // Helpers for parameterised routes — keep the slash arithmetic in one
  // place so the wiring on either side stays in sync.
  static String hrEmployeeDetail(String id) => '/hr/employees/$id';
  static String hrEmployeeEdit(String id) => '/hr/employees/$id/edit';
  static String hrTemplateEdit(String id) => '/hr/kra-templates/$id';

  // ── Manager module nested routes ──
  // Two modes share the /manager root: My Team (default) and
  // My Review (reuses the employee screens via my_review_shell.dart).
  static const String managerTeamDashboard = '/manager/team/dashboard';
  static const String managerTeamList = '/manager/team/list';
  static const String managerTeamHistory = '/manager/team/history';
  static const String managerTeamProfile = '/manager/team/profile';
  static const String managerTeamBulkApprove = '/manager/team/bulk-approve';
  static const String managerTeamBulkApproveResult =
      '/manager/team/bulk-approve/result';

  // Parameterised manager routes — pushed pages outside the inner shell
  // so they cover the bottom nav when navigated to.
  static String managerTeamMember(String employeeId) =>
      '/manager/team/list/$employeeId';
  static String managerTeamMemberHistory(String employeeId) =>
      '/manager/team/list/$employeeId/history';
  static String managerReviewDetail(String reviewId) =>
      '/manager/team/reviews/$reviewId';
  static String managerRate(String reviewId) =>
      '/manager/team/reviews/$reviewId/rate';
  static String managerRateReview(String reviewId) =>
      '/manager/team/reviews/$reviewId/rate/review';
  static String managerRateSuccess(String reviewId) =>
      '/manager/team/reviews/$reviewId/rate/success';
  static String managerRatePartial(String reviewId) =>
      '/manager/team/reviews/$reviewId/rate/partial';

  /// The post-login landing route — the "My KRA / My Review" employee
  /// self-view, for EVERY role.
  ///
  /// A user's own KRA/review lives only under the `/employee/*` self-view
  /// endpoints, so that surface is the one screen every authenticated user
  /// must be able to see and fill — regardless of role. Role only ADDS
  /// extra areas on top (Team for managers, HR admin for HR); it never
  /// replaces the self-view. Those extra areas are reached additively via
  /// the workspace switcher (see [WorkspaceSwitcher]) and the role drawers,
  /// not by landing there.
  ///
  /// This also doubles as the guard bounce-back target: a role deep-linking
  /// into an area it can't access (`/hr/*`, `/manager/*`) is sent here — to
  /// its own KRA — rather than to a raw 403.
  static String dashboardForRole(UserRole role) => employeeHome;

  /// True if [role] may access the HR module (`/hr/*`). Mirrors the
  /// router's `_canAccessHr` guard so UI (e.g. the workspace switcher)
  /// can offer the HR area to exactly the roles the router lets in.
  static bool canAccessHr(UserRole role) =>
      role == UserRole.hr || role == UserRole.hrAdmin || role == UserRole.admin;

  /// True if [role] may access any `/manager/*` route. Drives the
  /// router's role-guard redirect.
  static bool canAccessManager(UserRole role, {bool hasReports = false}) {
    if (role == UserRole.hrAdmin || role == UserRole.admin) return true;
    if (hasReports) return true;
    switch (role) {
      case UserRole.manager:
      case UserRole.bdManager:
      case UserRole.warehouseMgr:
        return true;
      default:
        return false;
    }
  }
}

/// Provides a GoRouter that listens to auth state and redirects
/// automatically.
///
/// Redirect rules:
///   1. Unauthenticated AND target is not /login → /login
///   2. Authenticated AND target is /login        → role's dashboard
///   3. Authenticated non-HR/ADMIN hitting /hr/*  → their own dashboard
///   4. Authenticated HR/ADMIN hitting /hr        → /hr/home
///   5. Otherwise                                  → no redirect
///
/// We do NOT redirect during AuthLoading — the existing route stays put
/// while a login is in flight, so the login screen's spinner can render.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.login,
    refreshListenable: _AuthListenable(ref),
    // Friendly fallback for unmatched routes (e.g. a backend deep-link to
    // a screen that isn't built yet). The default go_router error screen's
    // button targets `/`, which this app never registers, so it dead-ends;
    // ours routes "Go to Home" to a route that exists — the signed-in
    // user's dashboard, or /login when signed out.
    errorBuilder: (context, state) {
      final auth = ref.read(authStateProvider);
      final home = auth is AuthAuthenticated
          ? AppRoutes.dashboardForRole(auth.user.role)
          : AppRoutes.login;
      return RouteErrorScreen(homeRoute: home, error: state.error);
    },
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final goingToLogin = state.matchedLocation == AppRoutes.login;
      // Match `/hr` exactly OR any `/hr/...` sub-route — but not a
      // hypothetical sibling like `/hr-self-service`, which a naive
      // startsWith would have silently inherited the HR-only guard.
      final loc = state.matchedLocation;
      // Routes reachable while signed out (login + the password-recovery
      // flow). Anything else, unauthenticated, bounces to /login.
      final isPublicRoute = loc == AppRoutes.login ||
          loc == AppRoutes.forgotPassword ||
          loc == AppRoutes.resetPassword;
      final goingToHrArea = loc == AppRoutes.hrDashboard ||
          loc.startsWith('${AppRoutes.hrDashboard}/');
      final goingToManagerArea = loc == AppRoutes.managerDashboard ||
          loc.startsWith('${AppRoutes.managerDashboard}/');

      if (authState is AuthAuthenticated) {
        if (goingToLogin) {
          return AppRoutes.dashboardForRole(authState.user.role);
        }
        // Role guard: the HR module is HR/HR_ADMIN/ADMIN only. Other roles
        // get bounced to their own dashboard if they deep-link in.
        if (goingToHrArea && !_canAccessHr(authState.user.role)) {
          return AppRoutes.dashboardForRole(authState.user.role);
        }
        // Bare /hr → /hr/home for HR/HR_ADMIN/ADMIN.
        if (state.matchedLocation == AppRoutes.hrDashboard &&
            _canAccessHr(authState.user.role)) {
          return AppRoutes.hrHome;
        }
        // Manager role guard — MANAGER / BD_MANAGER / WAREHOUSE_MGR /
        // HR_ADMIN / ADMIN / any user with reports. Other roles deep-linking
        // to /manager/* get bounced to their own dashboard.
        if (goingToManagerArea &&
            !AppRoutes.canAccessManager(
              authState.user.role,
              hasReports: authState.user.hasReports,
            )) {
          return AppRoutes.dashboardForRole(authState.user.role);
        }
        // Bare /manager → /manager/team/dashboard for manager-capable
        // roles. Wraps the Step-3 placeholder behaviour now that the
        // real manager surface exists.
        if (state.matchedLocation == AppRoutes.managerDashboard &&
            AppRoutes.canAccessManager(
              authState.user.role,
              hasReports: authState.user.hasReports,
            )) {
          return AppRoutes.managerTeamDashboard;
        }
        // Bare /employee → /employee/home (the StatefulShellRoute
        // doesn't have its own builder at the parent path; redirect
        // sends users to the first tab).
        if (state.matchedLocation == AppRoutes.employeeDashboard) {
          return AppRoutes.employeeHome;
        }
        return null;
      }

      // Unauthenticated (Initial / Loading / Error) — anywhere except the
      // public routes bounces to login. Loading stays on login so the
      // BrandedPrimaryButton's spinner is visible.
      if (!isPublicRoute) return AppRoutes.login;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (_, __) => const ForgotPasswordScreen(),
      ),

      // ───── Quarterly KRA sheet (per-employee, full screen) ─────
      GoRoute(
        path: AppRoutes.reviewsQuarterly,
        builder: (_, __) => const QuarterlyKraSheetScreen(),
        routes: [
          GoRoute(
            path: ':employeeId',
            builder: (_, state) => QuarterlyKraSheetScreen(
              employeeId: state.pathParameters['employeeId'],
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        // Token arrives via the emailed deep link (?token=...).
        builder: (_, state) => ResetPasswordScreen(
          token: state.uri.queryParameters['token'],
        ),
      ),

      // ───── Monthly reviews (new pipeline) ─────
      // Top-level, role-adaptive, full-screen. Reachable by any signed-in
      // user; Phase 3 wires these into the per-role shells.
      GoRoute(
        path: AppRoutes.monthlyReviews,
        builder: (_, __) => const MonthlyReviewDashboardScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) => MonthlyReviewDetailScreen(
              reviewId: state.pathParameters['id']!,
            ),
          ),
        ],
      ),

      // ───── Employee module ─────
      // StatefulShellRoute keeps each tab's nav stack alive across
      // tab switches — important for the self-rate flow where the
      // user may bounce out to History mid-edit and expect their
      // form state to survive.
      //
      // Sub-routes (self-rate review/success/locked, history detail,
      // profile edit, reporting tree) nest INSIDE the relevant tab's
      // branch so the bottom nav stays visible. Stage 3/4 replaces
      // the placeholder builders for those sub-paths.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            EmployeeShellScreen(navigationShell: navigationShell),
        branches: [
          // ── Tab 1: Home ──
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.employeeHome,
                builder: (_, __) => const EmployeeHomeScreen(),
              ),
            ],
          ),
          // ── Tab 2: Reviews (monthly pipeline) ──
          // Re-rooted from the old cycle-era self-rate form to the monthly
          // review dashboard; the employee opens their month and self-rates
          // from there. The legacy self-rate sub-screens remain nested for
          // any deep links but are no longer the tab's surface.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.employeeSelfRate,
                // The employee's own quarterly KRA sheet — they view and edit
                // their Self scores across the quarter here.
                builder: (_, __) => const QuarterlyKraSheetScreen(),
                routes: [
                  GoRoute(
                    path: 'review',
                    builder: (_, __) => const SelfRateReviewScreen(),
                  ),
                  GoRoute(
                    path: 'success',
                    builder: (_, __) => const SelfRateSuccessScreen(),
                  ),
                  GoRoute(
                    path: 'locked',
                    builder: (_, __) => const SelfRateLockedScreen(),
                  ),
                ],
              ),
            ],
          ),
          // ── Tab 3: History (list + detail) ──
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.employeeHistory,
                builder: (_, __) => const MyReviewsHistoryScreen(),
                routes: [
                  GoRoute(
                    path: ':reviewId',
                    builder: (_, state) => ReviewDetailScreen(
                      reviewId: state.pathParameters['reviewId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // ── Tab 4: Profile (view + edit + reporting tree) ──
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.employeeProfile,
                builder: (_, __) => const MyProfileScreen(),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (_, __) => const EditProfileScreen(),
                  ),
                  GoRoute(
                    path: 'reporting-tree',
                    builder: (_, __) => const MyReportingTreeScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      // ───── Manager module ─────
      // Two-level shell hierarchy. The outer [ManagerShellScreen]
      // hosts the My Team / My Review mode switcher; the inner
      // [MyTeamShell] adds the bottom-nav scaffold for the 4 tabs
      // (Dashboard / Team / History / Profile). Pushed routes
      // (rate, review detail, bulk-approve) live outside the inner
      // shell so they cover the bottom nav.
      ShellRoute(
        builder: (context, state, child) => ManagerShellScreen(child: child),
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) =>
                MyTeamShell(navigationShell: navigationShell),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppRoutes.managerTeamDashboard,
                    // Re-rooted to the monthly review dashboard — the
                    // manager's team reviews per month.
                    builder: (_, __) => const MonthlyReviewDashboardScreen(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppRoutes.managerTeamList,
                    builder: (_, __) => const TeamListScreen(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppRoutes.managerTeamHistory,
                    builder: (_, __) => const TeamHistoryScreen(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppRoutes.managerTeamProfile,
                    builder: (_, __) => const ManagerProfileScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      // ── Pushed manager routes (outside inner shell, inside outer
      // ManagerShellScreen so the mode switcher stays visible) ──
      GoRoute(
        path: '/manager/team/list/:employeeId',
        builder: (_, state) => TeamMemberProfileScreen(
          employeeId: state.pathParameters['employeeId']!,
        ),
      ),
      GoRoute(
        path: '/manager/team/list/:employeeId/history',
        builder: (_, state) => TeamMemberHistoryScreen(
          employeeId: state.pathParameters['employeeId']!,
        ),
      ),
      GoRoute(
        path: '/manager/team/reviews/:reviewId',
        builder: (_, state) => manager_review.ReviewDetailScreen(
          reviewId: state.pathParameters['reviewId']!,
        ),
      ),
      GoRoute(
        path: '/manager/team/reviews/:reviewId/rate',
        builder: (_, state) => ManagerRateScreen(
          reviewId: state.pathParameters['reviewId']!,
        ),
      ),
      GoRoute(
        path: '/manager/team/reviews/:reviewId/rate/review',
        builder: (_, state) => ManagerRateReviewScreen(
          reviewId: state.pathParameters['reviewId']!,
        ),
      ),
      GoRoute(
        path: '/manager/team/reviews/:reviewId/rate/success',
        builder: (_, state) => ManagerRateSuccessScreen(
          reviewId: state.pathParameters['reviewId']!,
        ),
      ),
      GoRoute(
        path: '/manager/team/reviews/:reviewId/rate/partial',
        builder: (_, state) => ManagerRatePartialSuccessScreen(
          reviewId: state.pathParameters['reviewId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.managerTeamBulkApprove,
        builder: (_, state) {
          final ids = state.uri.queryParameters['ids']
                  ?.split(',')
                  .where((s) => s.isNotEmpty)
                  .toList() ??
              const <String>[];
          return BulkApproveConfirmScreen(reviewIds: ids);
        },
      ),
      GoRoute(
        path: AppRoutes.managerTeamBulkApproveResult,
        builder: (_, __) => const BulkApproveResultScreen(),
      ),

      // ───── HR module ─────
      // StatefulShellRoute.indexedStack keeps each tab's navigation
      // stack alive across tab switches — drilling into an employee
      // detail and jumping to Templates no longer loses the back-stack.
      // Push routes (forms, drawer destinations) live OUTSIDE the
      // shell so they cover the bottom nav when navigated to.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            HrShellScreen(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.hrHome,
                builder: (_, __) => const HrHomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.hrEmployees,
                builder: (_, __) => const EmployeesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.hrTemplates,
                builder: (_, __) => const KraTemplatesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.hrReviews,
                // HR-tier (HR / HR_ADMIN / ADMIN) get the consolidated review
                // dashboard: every employee's review at a glance, filterable
                // by KRA header, tap-through to perform the management review.
                builder: (_, __) => const AdminReviewDashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.hrReports,
                builder: (_, __) => const HrReportsScreen(),
              ),
            ],
          ),
        ],
      ),

      // Pushed (full-screen) HR routes — outside the shell on purpose
      // so the bottom nav doesn't show on forms / detail pages.
      GoRoute(
        path: AppRoutes.hrAssign,
        builder: (_, state) => KraAssignScreen(
          preselectEmployeeId: state.uri.queryParameters['employeeId'],
        ),
      ),
      GoRoute(
        path: AppRoutes.hrLocations,
        builder: (_, __) => const LocationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.hrBulkSetup,
        builder: (_, __) => const BulkSetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.hrEmployeeNew,
        builder: (_, __) => const EmployeeFormScreen(),
      ),
      GoRoute(
        path: '/hr/employees/:id',
        builder: (_, state) => EmployeeDetailScreen(
          employeeId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/hr/employees/:id/edit',
        builder: (_, state) => EmployeeFormScreen(
          employeeId: state.pathParameters['id'],
        ),
      ),
      GoRoute(
        path: AppRoutes.hrTemplateNew,
        builder: (_, __) => const KraTemplateFormScreen(),
      ),
      GoRoute(
        path: '/hr/kra-templates/:id',
        builder: (_, state) => KraTemplateFormScreen(
          templateId: state.pathParameters['id'],
        ),
      ),
      GoRoute(
        path: AppRoutes.hrAuditLog,
        builder: (_, __) => const AuditLogScreen(),
      ),
    ],
  );
});

/// The HR module is locked down to HR + HR_ADMIN + ADMIN.
/// Other roles deep-linking to `/hr/*` get redirected to their own dashboard.
bool _canAccessHr(UserRole role) => AppRoutes.canAccessHr(role);

/// Bridges Riverpod auth state changes into GoRouter's refresh
/// mechanism so the redirect rules re-run on login / logout / forced-logout.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen<AuthState>(
      authStateProvider,
      (_, __) => notifyListeners(),
    );
  }
}
