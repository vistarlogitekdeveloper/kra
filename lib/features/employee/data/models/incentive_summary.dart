import '../../../../core/api/json_parse.dart';
import 'enums.dart';
import 'monthly_incentive.dart';

/// Full GET /employee/incentive-summary response — quarterly snapshot
/// of what the logged-in employee has earned and is eligible for,
/// plus a per-month breakdown.
///
/// Eligibility precedence (highest to lowest):
///   Review.monthlyIncentiveAmount (snapshot at review creation)
///     → PerformanceIncentive[cycleId, grade]
///     → Employee.monthlyIncentiveAmount (org default)
///
/// `payableIfFinalizedNow` is the projected payout if HR finalised
/// the cycle right now — only populated once the cycle reaches
/// MANAGER_RATED_ALL.
class IncentiveSummary {
  final IncentiveCycleRef cycle;
  final String? grade;
  final double monthlyEligible;
  final double quarterlyEligible;
  final double earnedSoFar;
  final double? payableIfFinalizedNow;
  final ReviewState reviewState;
  final String currency;
  final List<MonthlyIncentive> monthly;

  const IncentiveSummary({
    required this.cycle,
    this.grade,
    required this.monthlyEligible,
    required this.quarterlyEligible,
    required this.earnedSoFar,
    this.payableIfFinalizedNow,
    required this.reviewState,
    this.currency = 'INR',
    this.monthly = const [],
  });

  /// 0–100 percentage. Returns 0 when [quarterlyEligible] is zero
  /// (avoids NaN in the snapshot card).
  double get earnedPercentage {
    if (quarterlyEligible <= 0) return 0;
    return (earnedSoFar / quarterlyEligible) * 100;
  }

  factory IncentiveSummary.fromJson(Map<String, dynamic> json) {
    return IncentiveSummary(
      cycle: IncentiveCycleRef.fromJson(
          JsonParse.parseMap(json['cycle']) ?? const {}),
      grade: JsonParse.parseString(json['grade']),
      monthlyEligible: JsonParse.parseDouble(json['monthlyEligible']) ?? 0,
      quarterlyEligible:
          JsonParse.parseDouble(json['quarterlyEligible']) ?? 0,
      earnedSoFar: JsonParse.parseDouble(json['earnedSoFar']) ?? 0,
      payableIfFinalizedNow:
          JsonParse.parseDouble(json['payableIfFinalizedNow']),
      reviewState: ReviewState.fromApi(
          JsonParse.parseString(json['reviewState']) ?? 'DRAFT'),
      currency: JsonParse.parseString(json['currency']) ?? 'INR',
      monthly: JsonParse.parseMapList(json['monthly'])
          .map(MonthlyIncentive.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'cycle': cycle.toJson(),
        'grade': grade,
        'monthlyEligible': monthlyEligible,
        'quarterlyEligible': quarterlyEligible,
        'earnedSoFar': earnedSoFar,
        'payableIfFinalizedNow': payableIfFinalizedNow,
        'reviewState': reviewState.toApiString(),
        'currency': currency,
        'monthly': monthly.map((e) => e.toJson()).toList(),
      };

  IncentiveSummary copyWith({
    IncentiveCycleRef? cycle,
    String? grade,
    double? monthlyEligible,
    double? quarterlyEligible,
    double? earnedSoFar,
    double? payableIfFinalizedNow,
    ReviewState? reviewState,
    String? currency,
    List<MonthlyIncentive>? monthly,
  }) {
    return IncentiveSummary(
      cycle: cycle ?? this.cycle,
      grade: grade ?? this.grade,
      monthlyEligible: monthlyEligible ?? this.monthlyEligible,
      quarterlyEligible: quarterlyEligible ?? this.quarterlyEligible,
      earnedSoFar: earnedSoFar ?? this.earnedSoFar,
      payableIfFinalizedNow:
          payableIfFinalizedNow ?? this.payableIfFinalizedNow,
      reviewState: reviewState ?? this.reviewState,
      currency: currency ?? this.currency,
      monthly: monthly ?? this.monthly,
    );
  }
}

class IncentiveCycleRef {
  final String id;
  final String name;
  final String? fyLabel;
  final int? quarterNum;

  const IncentiveCycleRef({
    required this.id,
    required this.name,
    this.fyLabel,
    this.quarterNum,
  });

  factory IncentiveCycleRef.fromJson(Map<String, dynamic> json) =>
      IncentiveCycleRef(
        id: JsonParse.parseString(json['id']) ?? '',
        name: JsonParse.parseString(json['name']) ?? '',
        fyLabel: JsonParse.parseString(json['fyLabel']),
        quarterNum: JsonParse.parseInt(json['quarterNum']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'fyLabel': fyLabel,
        'quarterNum': quarterNum,
      };

  IncentiveCycleRef copyWith({
    String? id,
    String? name,
    String? fyLabel,
    int? quarterNum,
  }) =>
      IncentiveCycleRef(
        id: id ?? this.id,
        name: name ?? this.name,
        fyLabel: fyLabel ?? this.fyLabel,
        quarterNum: quarterNum ?? this.quarterNum,
      );
}
