import 'package:vistar_app/core/api/api_error.dart';
import 'package:vistar_app/core/enums/review_flow.dart';
import 'package:vistar_app/features/reviews/data/models/monthly_review.dart';
import 'package:vistar_app/features/reviews/data/models/rating_access.dart';
import 'package:vistar_app/features/reviews/data/models/rating_window.dart';
import 'package:vistar_app/features/reviews/data/models/review_stage.dart';
import 'package:vistar_app/features/reviews/data/repositories/rating_access_repository.dart';

// Fixtures for the rating-access tests. Instants follow the contract: a month
// opens at 00:00 IST on the 1st of the next month and each stage closes at
// 23:59:59.999 IST on its deadline day (docs/RATING_ACCESS.md §2).

const _ist = Duration(hours: 5, minutes: 30);

/// 00:00 IST on day 1 of [year]-[month].
DateTime istMonthStart(int year, int month) =>
    DateTime.utc(year, month, 1).subtract(_ist);

/// 23:59:59.999 IST on [year]-[month]-[day].
DateTime istEndOfDay(int year, int month, int day) =>
    DateTime.utc(year, month, day, 23, 59, 59, 999).subtract(_ist);

/// The published deadline days.
const Map<ReviewStage, int> deadlineDays = {
  ReviewStage.selfRating: 10,
  ReviewStage.reportingManagerRating: 13,
  ReviewStage.accountHrRating: 12,
  ReviewStage.financeRating: 12,
  ReviewStage.managementReview: 15,
};

/// The five rating stages in pipeline order, as the server lists them.
const List<ReviewStage> ratingStages = [
  ReviewStage.selfRating,
  ReviewStage.reportingManagerRating,
  ReviewStage.accountHrRating,
  ReviewStage.financeRating,
  ReviewStage.managementReview,
];

DateTime deadlineOf(ReviewPeriod period, ReviewStage stage) {
  final next = period.next;
  return istEndOfDay(next.year, next.month, deadlineDays[stage] ?? 15);
}

RatingWindow deadlineWindow(ReviewPeriod period, ReviewStage stage) {
  final next = period.next;
  final deadline = deadlineOf(period, stage);
  return RatingWindow(
    source: RatingWindowSource.deadline,
    closed: false,
    opensAt: istMonthStart(next.year, next.month),
    closesAt: deadline,
    deadlineAt: deadline,
  );
}

RatingWindow openedWindow(
  ReviewPeriod period,
  ReviewStage stage, {
  DateTime? until,
}) {
  final next = period.next;
  return RatingWindow(
    source: RatingWindowSource.opened,
    closed: false,
    opensAt: istMonthStart(next.year, next.month),
    closesAt: until,
    deadlineAt: deadlineOf(period, stage),
  );
}

RatingWindow closedWindow(ReviewPeriod period, ReviewStage stage) {
  final next = period.next;
  return RatingWindow(
    source: RatingWindowSource.closed,
    closed: true,
    opensAt: istMonthStart(next.year, next.month),
    deadlineAt: deadlineOf(period, stage),
  );
}

RatingAccessOverride overrideOf(
  ReviewPeriod period,
  ReviewStage stage,
  RatingAccessMode mode, {
  DateTime? openUntil,
  String? reason,
  DateTime? updatedAt,
  String? updatedByName = 'Super Admin',
}) =>
    RatingAccessOverride(
      id: 'ovr-${stage.toApiString()}-${period.key}',
      stage: stage,
      period: period,
      mode: mode,
      openUntil: openUntil,
      reason: reason,
      updatedAt: updatedAt ?? DateTime.utc(2026, 10, 1, 4, 30),
      updatedById: 'sa-1',
      updatedByName: updatedByName,
    );

/// A month with every stage on its deadline, no overrides.
RatingAccessMonth deadlineMonth(
  ReviewPeriod period, {
  ReviewFlow flow = ReviewFlow.standard,
  String organizationId = 'org-1',
  String organizationName = 'Vistar Logitek',
}) =>
    RatingAccessMonth(
      organizationId: organizationId,
      organizationName: organizationName,
      reviewFlow: flow,
      period: period,
      stages: [
        for (final stage in ratingStages)
          RatingAccessStage(
            stage: stage,
            window: deadlineWindow(period, stage),
          ),
      ],
    );

const august = ReviewPeriod(2026, 8);
const september = ReviewPeriod(2026, 9);
const july = ReviewPeriod(2026, 7);

/// August 2026 as of 2 Oct 2026, one stage in each interesting state:
///   SELF    reopened until 31 Oct (the rollout seed)
///   RM      on its deadline, which has passed
///   HR      closed by the super admin
///   FINANCE reopened with no end
///   MGMT    an OPEN override ending before the deadline — inert
RatingAccessMonth mixedAugust({ReviewFlow flow = ReviewFlow.standard}) {
  final seedEnd = istEndOfDay(2026, 10, 31);
  return RatingAccessMonth(
    organizationId: 'org-1',
    organizationName: 'Vistar Logitek',
    reviewFlow: flow,
    period: august,
    stages: [
      RatingAccessStage(
        stage: ReviewStage.selfRating,
        window: openedWindow(august, ReviewStage.selfRating, until: seedEnd),
        adminOverride: overrideOf(
          august,
          ReviewStage.selfRating,
          RatingAccessMode.open,
          openUntil: seedEnd,
          reason: 'Pre-opened at rollout: pending July/August ratings',
        ),
      ),
      RatingAccessStage(
        stage: ReviewStage.reportingManagerRating,
        window: deadlineWindow(august, ReviewStage.reportingManagerRating),
      ),
      RatingAccessStage(
        stage: ReviewStage.accountHrRating,
        window: closedWindow(august, ReviewStage.accountHrRating),
        adminOverride: overrideOf(
          august,
          ReviewStage.accountHrRating,
          RatingAccessMode.closed,
        ),
      ),
      RatingAccessStage(
        stage: ReviewStage.financeRating,
        window: openedWindow(august, ReviewStage.financeRating),
        adminOverride: overrideOf(
          august,
          ReviewStage.financeRating,
          RatingAccessMode.open,
        ),
      ),
      RatingAccessStage(
        stage: ReviewStage.managementReview,
        window: deadlineWindow(august, ReviewStage.managementReview),
        adminOverride: overrideOf(
          august,
          ReviewStage.managementReview,
          RatingAccessMode.open,
          openUntil: istEndOfDay(2026, 9, 14),
        ),
      ),
    ],
  );
}

typedef SetCall = ({
  String organizationId,
  ReviewPeriod period,
  ReviewStage stage,
  RatingAccessMode mode,
  String? openUntilDate,
  String? reason,
});

typedef ClearCall = ({
  String organizationId,
  ReviewPeriod period,
  ReviewStage stage,
});

/// An in-memory server: answers month views from [months], applies writes to
/// them the way the server resolves windows, and records every call.
class FakeRatingAccessRepository implements RatingAccessRepository {
  FakeRatingAccessRepository({
    Map<String, RatingAccessMonth>? months,
    List<RatingAccessOverride>? overrides,
  })  : months = months ?? {},
        overrides = overrides ?? [];

  /// By period key. A month that is not here answers 404 RES_001, which is
  /// what a backend without the endpoints says.
  final Map<String, RatingAccessMonth> months;
  List<RatingAccessOverride> overrides;

  /// Thrown, in order, by the next month fetches.
  final List<Object> monthFailures = [];

  /// Thrown by the next override-history fetch, once.
  Object? historyFailure;

  /// Thrown by the write whose 0-based index (across set and clear) matches.
  int? failWriteAt;
  Object writeFailure = const ApiError(
    type: ApiErrorType.validation,
    code: 'VAL_001',
    message: 'That date has already passed.',
    statusCode: 400,
  );

  final List<String> monthFetches = [];
  int historyFetches = 0;
  final List<SetCall> sets = [];
  final List<ClearCall> clears = [];
  int _writes = 0;

  @override
  Future<RatingAccessMonth> fetchMonth(
    String organizationId,
    ReviewPeriod period,
  ) async {
    monthFetches.add('$organizationId ${period.key}');
    if (monthFailures.isNotEmpty) throw monthFailures.removeAt(0);
    final month = months[period.key];
    if (month == null) throw _notFound;
    return month;
  }

  @override
  Future<List<RatingAccessOverride>> fetchOverrides(
    String organizationId,
  ) async {
    historyFetches++;
    final failure = historyFailure;
    if (failure != null) {
      historyFailure = null;
      throw failure;
    }
    return overrides;
  }

  @override
  Future<RatingAccessMonth> setOverride(
    String organizationId,
    ReviewPeriod period,
    ReviewStage stage, {
    required RatingAccessMode mode,
    String? openUntilDate,
    String? reason,
  }) async {
    sets.add((
      organizationId: organizationId,
      period: period,
      stage: stage,
      mode: mode,
      openUntilDate: openUntilDate,
      reason: reason,
    ));
    _failIfDue();
    final until = _endOfDay(openUntilDate);
    final deadline = deadlineOf(period, stage);
    final RatingWindow window;
    if (mode == RatingAccessMode.closed) {
      window = closedWindow(period, stage);
    } else if (until == null || until.isAfter(deadline)) {
      window = openedWindow(period, stage, until: until);
    } else {
      window = deadlineWindow(period, stage);
    }
    return _replace(
      period,
      RatingAccessStage(
        stage: stage,
        window: window,
        adminOverride: overrideOf(
          period,
          stage,
          mode,
          openUntil: until,
          reason: reason,
          updatedAt: DateTime.utc(2026, 10, 2, 6),
        ),
      ),
    );
  }

  @override
  Future<RatingAccessMonth> clearOverride(
    String organizationId,
    ReviewPeriod period,
    ReviewStage stage,
  ) async {
    clears.add((organizationId: organizationId, period: period, stage: stage));
    _failIfDue();
    return _replace(
      period,
      RatingAccessStage(stage: stage, window: deadlineWindow(period, stage)),
    );
  }

  void _failIfDue() {
    final index = _writes++;
    if (failWriteAt == index) throw writeFailure;
  }

  RatingAccessMonth _replace(ReviewPeriod period, RatingAccessStage entry) {
    final month = months[period.key];
    if (month == null) throw _notFound;
    final updated = RatingAccessMonth(
      organizationId: month.organizationId,
      organizationName: month.organizationName,
      reviewFlow: month.reviewFlow,
      period: month.period,
      stages: [
        for (final s in month.stages) s.stage == entry.stage ? entry : s,
      ],
    );
    months[period.key] = updated;
    return updated;
  }

  static DateTime? _endOfDay(String? date) {
    if (date == null) return null;
    final parts = date.split('-').map(int.parse).toList();
    return istEndOfDay(parts[0], parts[1], parts[2]);
  }

  static const _notFound = ApiError(
    type: ApiErrorType.notFound,
    code: 'RES_001',
    message: "We couldn't find what you were looking for.",
    statusCode: 404,
  );
}
