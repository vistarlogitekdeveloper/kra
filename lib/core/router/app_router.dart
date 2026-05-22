import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/models/user.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../widgets/route_error_screen.dart';
import '../../features/dashboards/placeholder_dashboard.dart';
import '../../features/employee/presentation/screens/employee_shell_screen.dart';
import '../../features/employee/presentation/screens/history/my_reviews_history_screen.dart';
import '../../features/employee/presentation/screens/history/review_detail_screen.dart';
import '../../features/employee/presentation/screens/home/employee_home_screen.dart';
import '../../features/employee/presentation/screens/profile/edit_profile_screen.dart';
import '../../features/employee/presentation/screens/profile/my_profile_screen.dart';
import '../../features/employee/presentation/screens/profile/my_reporting_tree_screen.dart';
import '../../features/employee/presentation/screens/self_rate/self_rate_locked_screen.dart';
import '../../features/employee/presentation/screens/self_rate/self_rate_review_screen.dart';
import '../../features/employee/presentation/screens/self_rate/self_rate_screen.dart';
import '../../features/employee/presentation/screens/self_rate/self_rate_success_screen.dart';
import '../../features/hr/presentation/screens/bonus_slabs_screen.dart';
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
import '../../features/hr/presentation/screens/review_cycle_form_screen.dart';
import '../../features/manager/presentation/screens/manager_shell_screen.dart';
import '../../features/manager/presentation/screens/my_team/bulk_approve/bulk_approve_confirm_screen.dart';
import '../../features/manager/presentation/screens/my_team/bulk_approve/bulk_approve_result_screen.dart';
import '../../features/manager/presentation/screens/my_team/dashboard/manager_dashboard_screen.dart';
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
import '../../features/hr/presentation/screens/review_cycles_screen.dart';

/// Centralised route paths — never use raw strings at call sites.
class AppRoutes {
  AppRoutes._();

  static const String login = '/login';
  static const String employeeDashboard = '/employee';
  static const String managerDashboard = '/manager';
  static const String opsDashboard = '/ops';
  static const String hrDashboard = '/hr';
  static const String financeDashboard = '/finance';

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
  static const String hrCycles = '/hr/cycles';
  static const String hrCycleNew = '/hr/cycles/new';
  static const String hrReports = '/hr/reports';
  static const String hrLocations = '/hr/locations';
  static const String hrBulkSetup = '/hr/bulk-setup';
  static const String hrAuditLog = '/hr/reports/audit-log';

  // Helpers for parameterised routes — keep the slash arithmetic in one
  // place so the wiring on either side stays in sync.
  static String hrEmployeeDetail(String id) => '/hr/employees/$id';
  static String hrEmployeeEdit(String id) => '/hr/employees/$id/edit';
  static String hrTemplateEdit(String id) => '/hr/kra-templates/$id';
  static String hrCycleSlabs(String id) => '/hr/cycles/$id/slabs';

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

  static const String managerReviewHome = '/manager/review/home';
  static const String managerReviewSelfRate = '/manager/review/self-rate';
  static const String managerReviewHistory = '/manager/review/history';
  static const String managerReviewProfile = '/manager/review/profile';

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

  /// Maps a [UserRole] to its landing route after login.
  ///
  /// Per the Step 4 spec:
  ///   - ADMIN / HR_ADMIN / HR  → `/hr/home` (their primary surface)
  ///   - MANAGER / BD_MANAGER / WAREHOUSE_MGR → `/manager/team/dashboard`
  ///   - Everyone else → `/employee/home`
  ///
  /// Manager-capable roles can deep-link to `/employee/home` to
  /// self-rate (the My Review mode); HR_ADMIN has a drawer entry to
  /// switch to manager view for escalations.
  static String dashboardForRole(UserRole role) {
    switch (role) {
      case UserRole.admin:
      case UserRole.hrAdmin:
      case UserRole.hr:
        return hrHome;
      case UserRole.manager:
      case UserRole.bdManager:
      case UserRole.warehouseMgr:
        return managerTeamDashboard;
      case UserRole.employee:
      case UserRole.ops:
      case UserRole.finance:
        return employeeHome;
    }
  }

  /// True if [role] may access any `/manager/*` route. Drives the
  /// router's role-guard redirect.
  static bool canAccessManager(UserRole role) {
    switch (role) {
      case UserRole.manager:
      case UserRole.hrAdmin:
      case UserRole.admin:
      case UserRole.bdManager:
      case UserRole.warehouseMgr:
        return true;
      case UserRole.employee:
      case UserRole.ops:
      case UserRole.finance:
      case UserRole.hr:
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
      final goingToHrArea =
          state.matchedLocation.startsWith(AppRoutes.hrDashboard);

      final goingToManagerArea =
          state.matchedLocation.startsWith(AppRoutes.managerDashboard);

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
        // HR_ADMIN / ADMIN. Other roles deep-linking to /manager/* get
        // bounced to their own dashboard.
        if (goingToManagerArea &&
            !AppRoutes.canAccessManager(authState.user.role)) {
          return AppRoutes.dashboardForRole(authState.user.role);
        }
        // Bare /manager → /manager/team/dashboard for manager-capable
        // roles. Wraps the Step-3 placeholder behaviour now that the
        // real manager surface exists.
        if (state.matchedLocation == AppRoutes.managerDashboard &&
            AppRoutes.canAccessManager(authState.user.role)) {
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

      // Unauthenticated (Initial / Loading / Error) — anywhere except
      // login bounces to login. Loading stays on login so the
      // BrandedPrimaryButton's spinner is visible.
      if (!goingToLogin) return AppRoutes.login;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const LoginScreen(),
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
          // ── Tab 2: Self-Rate (form + 3 sub-screens) ──
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.employeeSelfRate,
                builder: (_, __) => const SelfRateScreen(),
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

      // ───── Other role-specific placeholders ─────
      GoRoute(
        path: AppRoutes.opsDashboard,
        builder: (_, __) => const PlaceholderDashboard(role: UserRole.ops),
      ),
      GoRoute(
        path: AppRoutes.financeDashboard,
        builder: (_, __) =>
            const PlaceholderDashboard(role: UserRole.finance),
      ),

      // ───── Manager module ─────
      // Two-level shell hierarchy. The outer [ManagerShellScreen]
      // hosts the My Team / My Review mode switcher; the inner
      // [MyTeamShell] adds the bottom-nav scaffold for the 4 tabs
      // (Dashboard / Team / History / Profile). Pushed routes
      // (rate, review detail, bulk-approve) live outside the inner
      // shell so they cover the bottom nav.
      ShellRoute(
        builder: (context, state, child) =>
            ManagerShellScreen(child: child),
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) =>
                MyTeamShell(navigationShell: navigationShell),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppRoutes.managerTeamDashboard,
                    builder: (_, __) => const ManagerDashboardScreen(),
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
                path: AppRoutes.hrCycles,
                builder: (_, __) => const ReviewCyclesScreen(),
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
        builder: (_, __) => const KraAssignScreen(),
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
        path: AppRoutes.hrCycleNew,
        builder: (_, __) => const ReviewCycleFormScreen(),
      ),
      GoRoute(
        path: '/hr/cycles/:id/slabs',
        builder: (_, state) => BonusSlabsScreen(
          cycleId: state.pathParameters['id']!,
        ),
      ),
    ],
  );
});

/// The HR module is locked down to HR + HR_ADMIN + ADMIN.
/// Other roles deep-linking to `/hr/*` get redirected to their own dashboard.
bool _canAccessHr(UserRole role) =>
    role == UserRole.hr ||
    role == UserRole.hrAdmin ||
    role == UserRole.admin;

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
