import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/data/models/user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/models/monthly_review.dart';
import '../../data/models/monthly_review_summary.dart';
import '../../data/repositories/mock_monthly_review_repository.dart';
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

/// Single swap point for the data layer. Returns the in-memory mock —
/// there is no monthly backend yet. When one ships, implement
/// [MonthlyReviewRepository] against it and return that here; no other
/// file changes needed.
final monthlyReviewRepositoryProvider =
    Provider<MonthlyReviewRepository>((ref) {
  return MockMonthlyReviewRepository();
});

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
  final repo = ref.watch(monthlyReviewRepositoryProvider);

  // Demo scoping: map the signed-in role onto the seeded demo team so
  // every login sees data. A real backend scopes by the actual user id.
  String? employeeId;
  String? managerId;
  switch (scope.role) {
    case UserRole.employee:
    case UserRole.ops:
      employeeId = MockMonthlyReviewRepository.demoEmployeeId;
      break;
    case UserRole.manager:
    case UserRole.bdManager:
    case UserRole.warehouseMgr:
      managerId = MockMonthlyReviewRepository.demoManagerId;
      break;
    case UserRole.hr:
    case UserRole.finance:
    case UserRole.admin:
    case UserRole.hrAdmin:
      break; // org-wide
  }

  return repo.listMonthlyReviews(
    year: period.year,
    month: period.month,
    scopeRole: scope.role,
    scopeEmployeeId: employeeId,
    scopeManagerId: managerId,
  );
});

/// Full review for the detail / stage screen.
final monthlyReviewDetailProvider =
    FutureProvider.autoDispose.family<MonthlyReview, String>((ref, id) async {
  return ref.watch(monthlyReviewRepositoryProvider).getReview(id);
});
