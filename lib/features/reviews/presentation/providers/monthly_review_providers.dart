import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/models/monthly_review.dart';
import '../../data/models/monthly_review_summary.dart';
import '../../data/repositories/mock_monthly_review_repository.dart';
import '../../data/repositories/monthly_review_repository.dart';

/// Single swap point for the data layer. Returns the in-memory mock today;
/// replace the body with `ApiMonthlyReviewRepository(...)` once the monthly
/// backend ships — no other file changes.
final monthlyReviewRepositoryProvider =
    Provider<MonthlyReviewRepository>((ref) {
  return MockMonthlyReviewRepository();
});

/// The requesting user as a [ReviewScope] (id + role) — drives which
/// reviews the dashboards see. Null until authenticated.
final currentReviewScopeProvider = Provider<ReviewScope?>((ref) {
  final auth = ref.watch(authStateProvider);
  if (auth is! AuthAuthenticated) return null;
  return ReviewScope(userId: auth.user.id, role: auth.user.role);
});

/// Calendar months that have reviews (newest first) — feeds month pickers.
final availablePeriodsProvider =
    FutureProvider.autoDispose<List<ReviewPeriod>>((ref) {
  return ref.watch(monthlyReviewRepositoryProvider).availablePeriods();
});

/// The month the dashboards are currently showing. Defaults to null →
/// callers fall back to the newest available period.
final selectedPeriodProvider = StateProvider<ReviewPeriod?>((ref) => null);

/// Review summaries for [period], scoped to the signed-in user.
final monthlyReviewListProvider = FutureProvider.autoDispose
    .family<List<MonthlyReviewSummary>, ReviewPeriod>((ref, period) async {
  final scope = ref.watch(currentReviewScopeProvider);
  if (scope == null) return const [];
  return ref
      .watch(monthlyReviewRepositoryProvider)
      .listForMonth(period: period, scope: scope);
});

/// Full review for the detail / stage screens.
final monthlyReviewDetailProvider =
    FutureProvider.autoDispose.family<MonthlyReview, String>((ref, id) async {
  return ref.watch(monthlyReviewRepositoryProvider).getReview(id);
});
