import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/dio_client.dart';
import '../../../../core/providers/org_scope_provider.dart';
import '../../data/models/monthly_review.dart';
import '../../data/models/rating_access.dart';
import '../../data/models/review_stage.dart';
import '../../data/repositories/rating_access_repository.dart';
import 'monthly_review_providers.dart';

/// One organisation's month on the rating-access screen. A record, so two keys
/// for the same organisation and month are equal and share one provider.
typedef RatingAccessKey = ({String organizationId, ReviewPeriod period});

final ratingAccessRepositoryProvider = Provider<RatingAccessRepository>((ref) {
  // Org-scoped like every repository provider, although these endpoints name
  // the organisation in the path: an organisation switch then drops every
  // cached month view with the rest of the graph, rather than leaving the one
  // feature that outlives it. See core/providers/org_scope_provider.dart.
  ref.watch(currentOrgIdProvider);
  return ApiRatingAccessRepository(dio: ref.read(dioProvider));
});

/// The clock the rating-access screen reads, so its status lines and date
/// limits are testable against a fixed day.
final ratingAccessClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// Every rating stage of one month for one organisation, as the server
/// resolves it.
///
/// autoDispose: a window is a function of the clock and of other super admins'
/// writes, so re-entering the screen re-reads rather than trusting a cache.
final ratingAccessMonthProvider = FutureProvider.autoDispose
    .family<RatingAccessMonth, RatingAccessKey>((ref, key) {
  return ref
      .watch(ratingAccessRepositoryProvider)
      .fetchMonth(key.organizationId, key.period);
});

/// The organisation's overrides, newest first.
final ratingAccessOverridesProvider = FutureProvider.autoDispose
    .family<List<RatingAccessOverride>, String>((ref, organizationId) {
  return ref
      .watch(ratingAccessRepositoryProvider)
      .fetchOverrides(organizationId);
});

/// Writes to rating access.
///
/// Every write invalidates the month view, the override history, and the two
/// review surfaces that embed rating windows — the quarterly sheet and the
/// monthly lists — so a super admin editing the organisation they are acting
/// in sees the sheet change at once instead of on its next refetch.
class RatingAccessActions {
  final Ref _ref;
  RatingAccessActions(this._ref);

  RatingAccessRepository get _repo => _ref.read(ratingAccessRepositoryProvider);

  /// Opens or closes one stage. See [RatingAccessRepository.setOverride].
  Future<RatingAccessMonth> set(
    String organizationId,
    ReviewPeriod period,
    ReviewStage stage, {
    required RatingAccessMode mode,
    String? openUntilDate,
    String? reason,
  }) async {
    final month = await _repo.setOverride(
      organizationId,
      period,
      stage,
      mode: mode,
      openUntilDate: openUntilDate,
      reason: reason,
    );
    _invalidate(organizationId, period);
    return month;
  }

  /// Puts one stage back on its deadline.
  Future<RatingAccessMonth> clear(
    String organizationId,
    ReviewPeriod period,
    ReviewStage stage,
  ) async {
    final month = await _repo.clearOverride(organizationId, period, stage);
    _invalidate(organizationId, period);
    return month;
  }

  /// Opens every stage in [stages] with the same end and reason. Null when
  /// [stages] is empty.
  ///
  /// One request per stage, in order, stopping at the first refusal. The
  /// caches are dropped even then: the stages before the refusal did change,
  /// and the screen must show the state the server actually holds.
  Future<RatingAccessMonth?> openAll(
    String organizationId,
    ReviewPeriod period,
    Iterable<ReviewStage> stages, {
    String? openUntilDate,
    String? reason,
  }) async {
    RatingAccessMonth? last;
    try {
      for (final stage in stages) {
        last = await _repo.setOverride(
          organizationId,
          period,
          stage,
          mode: RatingAccessMode.open,
          openUntilDate: openUntilDate,
          reason: reason,
        );
      }
    } finally {
      _invalidate(organizationId, period);
    }
    return last;
  }

  /// Puts every stage in [stages] back on its deadline. Same ordering and
  /// failure rule as [openAll].
  Future<RatingAccessMonth?> resetAll(
    String organizationId,
    ReviewPeriod period,
    Iterable<ReviewStage> stages,
  ) async {
    RatingAccessMonth? last;
    try {
      for (final stage in stages) {
        last = await _repo.clearOverride(organizationId, period, stage);
      }
    } finally {
      _invalidate(organizationId, period);
    }
    return last;
  }

  void _invalidate(String organizationId, ReviewPeriod period) {
    _ref.invalidate(ratingAccessMonthProvider(
      (organizationId: organizationId, period: period),
    ));
    _ref.invalidate(ratingAccessOverridesProvider(organizationId));
    // Whole families: which employees' sheets embed this month is not known
    // here, and a stale window offers a cell the server will refuse.
    _ref.invalidate(quarterlySheetProvider);
    _ref.invalidate(monthlyReviewListProvider);
  }
}

final ratingAccessActionsProvider =
    Provider<RatingAccessActions>((ref) => RatingAccessActions(ref));
