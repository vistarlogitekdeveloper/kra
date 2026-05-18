import '../../../../core/api/json_parse.dart';
import 'enums.dart';

/// One row in the `monthly` array returned by
/// GET /employee/incentive-summary.
///
/// Captures the rating progress AND the earned amount for a single
/// month inside the active cycle. `earnedAmount` only contributes to
/// the cycle-level `earnedSoFar` when [status] is
/// [MonthlyIncentiveStatus.complete] — pre-completion rows show 0
/// even if a self-rating exists.
class MonthlyIncentive {
  final String monthId;
  final String monthLabel;
  final DateTime? monthDate;

  /// Manager's weighted-average score for the month, 0–100.
  /// `null` until the manager completes their pass.
  final double? managerPct;

  /// Employee's weighted-average self-score, 0–100.
  /// `null` until the employee submits any rating for the month.
  final double? selfPct;

  /// Computed payout for the month — `managerPct/100 * monthlyEligible`
  /// when the row is COMPLETE, otherwise 0. Decimal-on-wire.
  final double earnedAmount;

  final MonthlyIncentiveStatus status;

  const MonthlyIncentive({
    required this.monthId,
    required this.monthLabel,
    this.monthDate,
    this.managerPct,
    this.selfPct,
    required this.earnedAmount,
    required this.status,
  });

  factory MonthlyIncentive.fromJson(Map<String, dynamic> json) {
    return MonthlyIncentive(
      monthId: JsonParse.parseString(json['monthId']) ?? '',
      monthLabel: JsonParse.parseString(json['monthLabel']) ?? '',
      monthDate: JsonParse.parseDate(json['monthDate']),
      managerPct: JsonParse.parseDouble(json['managerPct']),
      selfPct: JsonParse.parseDouble(json['selfPct']),
      earnedAmount: JsonParse.parseDouble(json['earnedAmount']) ?? 0,
      status: MonthlyIncentiveStatus.fromApi(
          JsonParse.parseString(json['status']) ?? 'NO_REVIEW'),
    );
  }

  Map<String, dynamic> toJson() => {
        'monthId': monthId,
        'monthLabel': monthLabel,
        'monthDate': monthDate?.toIso8601String(),
        'managerPct': managerPct,
        'selfPct': selfPct,
        'earnedAmount': earnedAmount,
        'status': status.toApiString(),
      };

  MonthlyIncentive copyWith({
    String? monthId,
    String? monthLabel,
    DateTime? monthDate,
    double? managerPct,
    double? selfPct,
    double? earnedAmount,
    MonthlyIncentiveStatus? status,
  }) {
    return MonthlyIncentive(
      monthId: monthId ?? this.monthId,
      monthLabel: monthLabel ?? this.monthLabel,
      monthDate: monthDate ?? this.monthDate,
      managerPct: managerPct ?? this.managerPct,
      selfPct: selfPct ?? this.selfPct,
      earnedAmount: earnedAmount ?? this.earnedAmount,
      status: status ?? this.status,
    );
  }
}
