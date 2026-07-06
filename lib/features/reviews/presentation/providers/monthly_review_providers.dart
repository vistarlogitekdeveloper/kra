import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/dio_client.dart';
import '../../../auth/data/models/user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../employee/presentation/providers/my_kra_providers.dart';
import '../../../hr/presentation/providers/employee_providers.dart';
import '../../../hr/presentation/providers/kra_assignment_providers.dart';
import '../../../manager/presentation/providers/manager_team_providers.dart';
import '../../data/models/monthly_kra_row.dart';
import '../../data/models/monthly_review.dart';
import '../../data/models/monthly_review_summary.dart';
import '../../data/repositories/api_monthly_review_repository.dart';
import '../../data/repositories/live_monthly_review_repository.dart';
import '../../data/repositories/monthly_review_repository.dart';

/// Whether to use the live monthly-review backend (`/reviews/monthly*`).
///
/// Gated on a build-time flag so the switch is a deploy-day config change,
/// not a code edit: pass `--dart-define=MONTHLY_BACKEND=true` once those
/// endpoints are deployed. Defaults to `false` because they 404 on the
/// current deployment — until then the app runs on the live-roster
/// repository (real employees from `/employees` etc. + an in-memory
/// pipeline). When `true`, [monthlyReviewRepositoryProvider] targets
/// [ApiMonthlyReviewRepository] with no model/UI changes.
final monthlyBackendEnabledProvider = Provider<bool>(
  (ref) => const bool.fromEnvironment('MONTHLY_BACKEND', defaultValue: true),
);

/// The signed-in user reduced to what the review layer needs: an id +
/// display name (for stage-submission audit) and a role (for gating).
class ReviewScope {
  final String userId;
  final String userName;
  final UserRole role;
  const ReviewScope({
    required this.userId,
    required this.userName,
    required this.role,
  });
}

/// Data layer for monthly reviews.
///
/// The **roster is real** — pulled from the live backend per role (HR/
/// admin → every employee, manager → direct reports, employee → self).
/// The *pipeline state* is still in-memory ([LiveMonthlyReviewRepository])
/// because there's no monthly-review backend yet; swap this for a straight
/// API impl once one ships.
final monthlyReviewRepositoryProvider =
    Provider<MonthlyReviewRepository>((ref) {
  if (ref.watch(monthlyBackendEnabledProvider)) {
    return ApiMonthlyReviewRepository(dio: ref.read(dioProvider));
  }
  return LiveMonthlyReviewRepository(loadRoster: () => _loadRoster(ref));
});

/// Fetches the role-appropriate set of real employees from the live API.
Future<List<RosterEntry>> _loadRoster(Ref ref) async {
  final scope = ref.read(currentReviewScopeProvider);
  if (scope == null) return const [];
  switch (scope.role) {
    case UserRole.employee:
    case UserRole.ops:
      // An employee can only see their own review + their own KRAs.
      // listMyAssignments returns [] when there's simply no assignment (the
      // repo then applies a generic template). A *thrown* error is a real
      // failure (e.g. Render cold-start timeout) and must propagate so the
      // dashboard shows error+retry — swallowing it here would silently lock
      // a generic-template review in via putIfAbsent for the whole session.
      final mine = await ref.read(myKraRepositoryProvider).listMyAssignments();
      final rows = _rowsFrom(mine.expand((a) => a.items).map((i) => (
            name: i.name,
            category: i.description,
            weightPct: i.weightagePercent,
            target: i.target,
            tracking: i.trackingMethod,
            sortOrder: i.sortOrder,
          )));
      return [RosterEntry(id: scope.userId, name: scope.userName, rows: rows)];

    case UserRole.manager:
    case UserRole.bdManager:
    case UserRole.warehouseMgr:
      // Direct reports come from /manager/team (backend-scoped by the manager's
      // JWT). managerId is set to the signed-in manager so the quarterly sheet
      // lets them edit their reports' manager scores.
      final page =
          await ref.read(managerTeamRepositoryProvider).listTeam(pageSize: 200);
      return page.members
          .map((m) => RosterEntry(
                id: m.employeeId,
                name: m.fullName,
                code: m.employeeCode,
                managerId: scope.userId,
                managerName: scope.userName,
              ))
          .toList();

    case UserRole.hr:
    case UserRole.finance:
    case UserRole.admin:
    case UserRole.hrAdmin:
      // Fetch the roster and every assignment concurrently, then join the
      // real KRA rows onto each employee by id.
      final empFuture = ref
          .read(employeeRepositoryProvider)
          .list(page: 1, pageSize: 500, isActive: true);
      final asgFuture = ref.read(kraAssignmentRepositoryProvider).list();
      final page = await empFuture;
      final assignments = await asgFuture;

      final rowsByEmployee = <String, List<MonthlyKraRow>>{};
      for (final a in assignments) {
        rowsByEmployee[a.employeeId] = _rowsFrom(a.items.map((i) => (
              name: i.name,
              category: i.description,
              weightPct: i.weightagePercent,
              target: i.target,
              tracking: i.trackingMethod,
              sortOrder: i.sortOrder,
            )));
      }

      return page.employees
          .map((e) => RosterEntry(
                id: e.id,
                name: e.fullName,
                code: e.employeeCode,
                grade: e.grade,
                managerId: e.managerId,
                managerName: e.managerName,
                eligibleAmount: e.monthlyIncentiveAmount ?? 0,
                rows: rowsByEmployee[e.id] ?? const [],
              ))
          .toList();
  }
}

/// Maps raw KRA template/assignment items (from either the HR assignment
/// or the employee's own KRA endpoint) into ordered [MonthlyKraRow]s.
List<MonthlyKraRow> _rowsFrom(
  Iterable<
          ({
            String name,
            String? category,
            double weightPct,
            String? target,
            String? tracking,
            int sortOrder,
          })>
      items,
) {
  final sorted = items.toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return [
    for (var i = 0; i < sorted.length; i++)
      MonthlyKraRow(
        id: 'kra-$i',
        name: sorted[i].name,
        category: sorted[i].category,
        weightagePercent: sorted[i].weightPct,
        maxScore: MonthlyKraRow.defaultMaxScore,
        target: sorted[i].target,
        trackingMethod: sorted[i].tracking,
        displayOrder: i,
      ),
  ];
}

/// The requesting user as a [ReviewScope]. Null until authenticated.
final currentReviewScopeProvider = Provider<ReviewScope?>((ref) {
  final auth = ref.watch(authStateProvider);
  if (auth is! AuthAuthenticated) return null;
  return ReviewScope(
    userId: auth.user.id,
    userName: auth.user.fullName,
    role: auth.user.role,
  );
});

/// Recent calendar months (current + previous 5, newest first) — feeds
/// the month picker. Reviews exist monthly, so the picker is a fixed
/// rolling window rather than a query.
final availablePeriodsProvider = Provider<List<ReviewPeriod>>((ref) {
  final now = DateTime.now();
  return List.generate(6, (i) {
    var m = now.month - i;
    var y = now.year;
    while (m <= 0) {
      m += 12;
      y -= 1;
    }
    return ReviewPeriod(y, m);
  });
});

/// The month the dashboards are showing. Null → callers fall back to the
/// newest available period.
final selectedPeriodProvider = StateProvider<ReviewPeriod?>((ref) => null);

/// Review summaries for [period], scoped to the signed-in user's role.
final monthlyReviewListProvider = FutureProvider.autoDispose
    .family<List<MonthlyReviewSummary>, ReviewPeriod>((ref, period) async {
  final scope = ref.watch(currentReviewScopeProvider);
  if (scope == null) return const [];
  // The repository's roster is already role-scoped via [_loadRoster], so
  // we only pass the role along (informational).
  return ref.read(monthlyReviewRepositoryProvider).listMonthlyReviews(
        year: period.year,
        month: period.month,
        scopeRole: scope.role,
      );
});

/// Full review for the detail / stage screen.
final monthlyReviewDetailProvider =
    FutureProvider.autoDispose.family<MonthlyReview, String>((ref, id) async {
  return ref.read(monthlyReviewRepositoryProvider).getReview(id);
});

/// The three months of the fiscal quarter (Apr-start, matching the KRA
/// sheet: Q1 = Apr–Jun) that contains [p].
List<ReviewPeriod> quarterMonthsFor(ReviewPeriod p) {
  final int start;
  if (p.month >= 4 && p.month <= 6) {
    start = 4;
  } else if (p.month >= 7 && p.month <= 9) {
    start = 7;
  } else if (p.month >= 10 && p.month <= 12) {
    start = 10;
  } else {
    start = 1; // Jan–Mar
  }
  return [
    ReviewPeriod(p.year, start),
    ReviewPeriod(p.year, start + 1),
    ReviewPeriod(p.year, start + 2),
  ];
}

/// One employee's three monthly reviews for the quarter that contains
/// `anchor`. Any month with no review yet comes back null. Powers the
/// quarterly KRA sheet.
final quarterlySheetProvider = FutureProvider.autoDispose.family<
    ({List<ReviewPeriod> months, List<MonthlyReview?> reviews}),
    ({String employeeId, ReviewPeriod anchor})>((ref, args) async {
  final scope = ref.watch(currentReviewScopeProvider);
  final repo = ref.read(monthlyReviewRepositoryProvider);
  final months = quarterMonthsFor(args.anchor);
  final reviews = <MonthlyReview?>[];
  for (final period in months) {
    final list = await repo.listMonthlyReviews(
      year: period.year,
      month: period.month,
      scopeRole: scope?.role,
    );
    final matches =
        list.where((s) => s.employeeId == args.employeeId).toList();
    reviews.add(matches.isEmpty ? null : await repo.getReview(matches.first.id));
  }
  return (months: months, reviews: reviews);
});
