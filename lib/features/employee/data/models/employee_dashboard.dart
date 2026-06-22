import '../../../../core/api/json_parse.dart';
import '../../../../core/utils/monthly_deadlines.dart';
import 'enums.dart';

/// Aggregated payload for the Employee home screen. One round-trip
/// gives the home tab everything it needs.
///
/// All four top-level blocks are nullable — when the user has no
/// active cycle (between cycles, or before HR opens the first one)
/// the entire payload's `cycle / currentMonth / scorecard / incentive`
/// are `null`. The UI shows an empty-state in that case.
///
/// The user record is **not** carried here — the home screen reads
/// the logged-in user from the auth provider to avoid duplicating
/// state that's already in memory. The richer profile (manager,
/// projectLocation, defaultTemplate) lives at GET /employee/profile.
class EmployeeDashboard {
  final DashboardCycle? cycle;
  final DashboardCurrentMonth? currentMonth;
  final DashboardScorecard? scorecard;
  final DashboardIncentive? incentive;

  const EmployeeDashboard({
    this.cycle,
    this.currentMonth,
    this.scorecard,
    this.incentive,
  });

  /// True iff the user has an active cycle right now. Drives the
  /// home screen's empty-state vs. populated-state branch.
  bool get hasActiveCycle => cycle != null;

  /// Days from today to the self-rating deadline — the fixed
  /// [MonthlyDeadlines.selfRatingDay] (7th) of the current calendar
  /// month. Returns `null` when there is no active cycle (so the home
  /// banner stays hidden between cycles). Negative values mean the
  /// deadline has passed.
  int? get selfRatingDaysRemaining {
    if (cycle == null) return null;
    return MonthlyDeadlines.daysRemaining(MonthlyDeadlines.selfRating());
  }

  /// Convenience for the deadline banner — "is the self-rating
  /// deadline behind us?". Falls back to `false` when no deadline.
  bool get isSelfRatingOverdue {
    final days = selfRatingDaysRemaining;
    return days != null && days < 0;
  }

  factory EmployeeDashboard.fromJson(Map<String, dynamic> json) {
    return EmployeeDashboard(
      cycle: JsonParse.parseMap(json['cycle']) == null
          ? null
          : DashboardCycle.fromJson(JsonParse.parseMap(json['cycle'])!),
      currentMonth: JsonParse.parseMap(json['currentMonth']) == null
          ? null
          : DashboardCurrentMonth.fromJson(
              JsonParse.parseMap(json['currentMonth'])!),
      scorecard: JsonParse.parseMap(json['scorecard']) == null
          ? null
          : DashboardScorecard.fromJson(JsonParse.parseMap(json['scorecard'])!),
      incentive: JsonParse.parseMap(json['incentive']) == null
          ? null
          : DashboardIncentive.fromJson(JsonParse.parseMap(json['incentive'])!),
    );
  }

  Map<String, dynamic> toJson() => {
        'cycle': cycle?.toJson(),
        'currentMonth': currentMonth?.toJson(),
        'scorecard': scorecard?.toJson(),
        'incentive': incentive?.toJson(),
      };

  EmployeeDashboard copyWith({
    DashboardCycle? cycle,
    DashboardCurrentMonth? currentMonth,
    DashboardScorecard? scorecard,
    DashboardIncentive? incentive,
  }) {
    return EmployeeDashboard(
      cycle: cycle ?? this.cycle,
      currentMonth: currentMonth ?? this.currentMonth,
      scorecard: scorecard ?? this.scorecard,
      incentive: incentive ?? this.incentive,
    );
  }
}

class DashboardCycle {
  final String id;
  final String name;
  final String? fyLabel;
  final int? quarterNum;
  final String status;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? selfRatingDeadline;
  final DateTime? managerReviewDeadline;

  const DashboardCycle({
    required this.id,
    required this.name,
    this.fyLabel,
    this.quarterNum,
    required this.status,
    this.startDate,
    this.endDate,
    this.selfRatingDeadline,
    this.managerReviewDeadline,
  });

  factory DashboardCycle.fromJson(Map<String, dynamic> json) => DashboardCycle(
        id: JsonParse.parseString(json['id']) ?? '',
        name: JsonParse.parseString(json['name']) ?? '',
        fyLabel: JsonParse.parseString(json['fyLabel']),
        quarterNum: JsonParse.parseInt(json['quarterNum']),
        status: JsonParse.parseString(json['status']) ?? '',
        startDate: JsonParse.parseDate(json['startDate']),
        endDate: JsonParse.parseDate(json['endDate']),
        selfRatingDeadline: JsonParse.parseDate(json['selfRatingDeadline']),
        managerReviewDeadline:
            JsonParse.parseDate(json['managerReviewDeadline']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'fyLabel': fyLabel,
        'quarterNum': quarterNum,
        'status': status,
        'startDate': startDate?.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'selfRatingDeadline': selfRatingDeadline?.toIso8601String(),
        'managerReviewDeadline': managerReviewDeadline?.toIso8601String(),
      };

  DashboardCycle copyWith({
    String? id,
    String? name,
    String? fyLabel,
    int? quarterNum,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? selfRatingDeadline,
    DateTime? managerReviewDeadline,
  }) {
    return DashboardCycle(
      id: id ?? this.id,
      name: name ?? this.name,
      fyLabel: fyLabel ?? this.fyLabel,
      quarterNum: quarterNum ?? this.quarterNum,
      status: status ?? this.status,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      selfRatingDeadline: selfRatingDeadline ?? this.selfRatingDeadline,
      managerReviewDeadline:
          managerReviewDeadline ?? this.managerReviewDeadline,
    );
  }
}

class DashboardCurrentMonth {
  final String id;
  final String monthLabel;
  final DateTime? monthDate;
  final ReviewMonthStatus status;

  const DashboardCurrentMonth({
    required this.id,
    required this.monthLabel,
    this.monthDate,
    required this.status,
  });

  factory DashboardCurrentMonth.fromJson(Map<String, dynamic> json) =>
      DashboardCurrentMonth(
        id: JsonParse.parseString(json['id']) ?? '',
        monthLabel: JsonParse.parseString(json['monthLabel']) ?? '',
        monthDate: JsonParse.parseDate(json['monthDate']),
        status: ReviewMonthStatus.fromApi(
            JsonParse.parseString(json['status']) ?? 'OPEN'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'monthLabel': monthLabel,
        'monthDate': monthDate?.toIso8601String(),
        'status': status.toApiString(),
      };

  DashboardCurrentMonth copyWith({
    String? id,
    String? monthLabel,
    DateTime? monthDate,
    ReviewMonthStatus? status,
  }) {
    return DashboardCurrentMonth(
      id: id ?? this.id,
      monthLabel: monthLabel ?? this.monthLabel,
      monthDate: monthDate ?? this.monthDate,
      status: status ?? this.status,
    );
  }
}

/// Snapshot of the current cycle's scoring progress.
///
/// `selfAvgPct` and `managerAvgPct` are weighted averages over all
/// rows × all rated months — both are capped at 100. Either may be
/// null when the corresponding pass hasn't started.
class DashboardScorecard {
  /// The active review's id — useful when the home card needs to
  /// deep-link to the review detail screen.
  final String reviewId;
  final ReviewState state;
  final double? selfAvgPct;
  final double? managerAvgPct;
  final int monthsCompleted;
  final int monthsTotal;

  const DashboardScorecard({
    required this.reviewId,
    required this.state,
    this.selfAvgPct,
    this.managerAvgPct,
    this.monthsCompleted = 0,
    this.monthsTotal = 0,
  });

  /// Fraction of the cycle's months completed (0.0 – 1.0). Used by
  /// the home progress indicator. Returns 0 when [monthsTotal] is 0
  /// to avoid divide-by-zero.
  double get progressFraction {
    if (monthsTotal <= 0) return 0;
    return (monthsCompleted / monthsTotal).clamp(0.0, 1.0);
  }

  factory DashboardScorecard.fromJson(Map<String, dynamic> json) =>
      DashboardScorecard(
        reviewId: JsonParse.parseString(json['reviewId']) ?? '',
        state: ReviewState.fromApi(
            JsonParse.parseString(json['state']) ?? 'DRAFT'),
        selfAvgPct: JsonParse.parseDouble(json['selfAvgPct']),
        managerAvgPct: JsonParse.parseDouble(json['managerAvgPct']),
        monthsCompleted: JsonParse.parseInt(json['monthsCompleted']) ?? 0,
        monthsTotal: JsonParse.parseInt(json['monthsTotal']) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'reviewId': reviewId,
        'state': state.toApiString(),
        'selfAvgPct': selfAvgPct,
        'managerAvgPct': managerAvgPct,
        'monthsCompleted': monthsCompleted,
        'monthsTotal': monthsTotal,
      };

  DashboardScorecard copyWith({
    String? reviewId,
    ReviewState? state,
    double? selfAvgPct,
    double? managerAvgPct,
    int? monthsCompleted,
    int? monthsTotal,
  }) {
    return DashboardScorecard(
      reviewId: reviewId ?? this.reviewId,
      state: state ?? this.state,
      selfAvgPct: selfAvgPct ?? this.selfAvgPct,
      managerAvgPct: managerAvgPct ?? this.managerAvgPct,
      monthsCompleted: monthsCompleted ?? this.monthsCompleted,
      monthsTotal: monthsTotal ?? this.monthsTotal,
    );
  }
}

class DashboardIncentive {
  final double monthlyEligible;
  final double quarterlyEligible;

  /// Earned across manager-completed months so far. Increments as
  /// each month closes — always ≤ [quarterlyEligible].
  final double earnedSoFar;

  /// Projected payout if HR finalised the cycle right now. Often
  /// `null` until the cycle reaches MANAGER_RATED_ALL.
  final double? payableSoFar;

  /// ISO 4217 currency code — always 'INR' in the current rollout
  /// but kept here so a future multi-currency setup needs no model
  /// change.
  final String currency;

  const DashboardIncentive({
    required this.monthlyEligible,
    required this.quarterlyEligible,
    required this.earnedSoFar,
    this.payableSoFar,
    this.currency = 'INR',
  });

  /// Convenience getter — earned / eligible as a 0–100 percentage.
  /// Drops to 0 when [quarterlyEligible] is zero (avoids NaN).
  double get earnedPercentage {
    if (quarterlyEligible <= 0) return 0;
    return (earnedSoFar / quarterlyEligible) * 100;
  }

  factory DashboardIncentive.fromJson(Map<String, dynamic> json) =>
      DashboardIncentive(
        monthlyEligible: JsonParse.parseDouble(json['monthlyEligible']) ?? 0,
        quarterlyEligible:
            JsonParse.parseDouble(json['quarterlyEligible']) ?? 0,
        earnedSoFar: JsonParse.parseDouble(json['earnedSoFar']) ?? 0,
        payableSoFar: JsonParse.parseDouble(json['payableSoFar']),
        currency: JsonParse.parseString(json['currency']) ?? 'INR',
      );

  Map<String, dynamic> toJson() => {
        'monthlyEligible': monthlyEligible,
        'quarterlyEligible': quarterlyEligible,
        'earnedSoFar': earnedSoFar,
        'payableSoFar': payableSoFar,
        'currency': currency,
      };

  DashboardIncentive copyWith({
    double? monthlyEligible,
    double? quarterlyEligible,
    double? earnedSoFar,
    double? payableSoFar,
    String? currency,
  }) {
    return DashboardIncentive(
      monthlyEligible: monthlyEligible ?? this.monthlyEligible,
      quarterlyEligible: quarterlyEligible ?? this.quarterlyEligible,
      earnedSoFar: earnedSoFar ?? this.earnedSoFar,
      payableSoFar: payableSoFar ?? this.payableSoFar,
      currency: currency ?? this.currency,
    );
  }
}
