import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/data/models/user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../hr/presentation/providers/employee_providers.dart';
import '../../../manager/presentation/providers/manager_team_providers.dart';
import '../../data/models/monthly_review.dart';
import '../../data/models/monthly_review_summary.dart';
import '../../data/repositories/live_monthly_review_repository.dart';
import '../../data/repositories/monthly_review_repository.dart';

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
  return LiveMonthlyReviewRepository(loadRoster: () => _loadRoster(ref));
});

/// Fetches the role-appropriate set of real employees from the live API.
Future<List<RosterEntry>> _loadRoster(Ref ref) async {
  final scope = ref.read(currentReviewScopeProvider);
  if (scope == null) return const [];
  switch (scope.role) {
    case UserRole.employee:
    case UserRole.ops:
      // An employee can only see their own review.
      return [RosterEntry(id: scope.userId, name: scope.userName)];

    case UserRole.manager:
    case UserRole.bdManager:
    case UserRole.warehouseMgr:
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
      final page = await ref
          .read(employeeRepositoryProvider)
          .list(page: 1, pageSize: 500, isActive: true);
      return page.employees
          .map((e) => RosterEntry(
                id: e.id,
                name: e.fullName,
                code: e.employeeCode,
                grade: e.grade,
                managerId: e.managerId,
                managerName: e.managerName,
                eligibleAmount: e.monthlyIncentiveAmount ?? 0,
              ))
          .toList();
  }
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
