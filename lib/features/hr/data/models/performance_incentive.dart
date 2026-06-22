import '../../../../core/api/json_parse.dart';

/// Maps an employee grade to the maximum monthly + quarterly performance
/// incentive amounts they are eligible for in a given review cycle. The
/// actual payout is `eligibleAmount * finalScore`.
class PerformanceIncentive {
  final String id;
  final String cycleId;
  final String grade;
  final double monthlyEligibleAmount;
  final double quarterlyEligibleAmount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PerformanceIncentive({
    required this.id,
    required this.cycleId,
    required this.grade,
    required this.monthlyEligibleAmount,
    required this.quarterlyEligibleAmount,
    this.createdAt,
    this.updatedAt,
  });

  factory PerformanceIncentive.fromJson(Map<String, dynamic> json) {
    return PerformanceIncentive(
      id: json['id'] as String,
      cycleId: (json['cycleId'] ?? '') as String,
      grade: (json['grade'] ?? '') as String,
      monthlyEligibleAmount:
          JsonParse.parseDouble(json['monthlyEligibleAmount']) ?? 0,
      quarterlyEligibleAmount:
          JsonParse.parseDouble(json['quarterlyEligibleAmount']) ?? 0,
      createdAt: JsonParse.parseDate(json['createdAt']),
      updatedAt: JsonParse.parseDate(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'cycleId': cycleId,
        'grade': grade,
        'monthlyEligibleAmount': monthlyEligibleAmount,
        'quarterlyEligibleAmount': quarterlyEligibleAmount,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  PerformanceIncentive copyWith({
    String? id,
    String? cycleId,
    String? grade,
    double? monthlyEligibleAmount,
    double? quarterlyEligibleAmount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PerformanceIncentive(
      id: id ?? this.id,
      cycleId: cycleId ?? this.cycleId,
      grade: grade ?? this.grade,
      monthlyEligibleAmount:
          monthlyEligibleAmount ?? this.monthlyEligibleAmount,
      quarterlyEligibleAmount:
          quarterlyEligibleAmount ?? this.quarterlyEligibleAmount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
