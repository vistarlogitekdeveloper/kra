import '../../../../core/api/json_parse.dart';

/// Payout lifecycle of a monthly review's incentive.
enum PayoutStatus {
  /// Not yet at (or past) the payout stage.
  pending,

  /// Finance/HR have marked the computed incentive as paid.
  paid,

  /// Payout skipped — e.g. a zero eligible amount.
  skipped;

  String toApiString() {
    switch (this) {
      case PayoutStatus.pending:
        return 'PENDING';
      case PayoutStatus.paid:
        return 'PAID';
      case PayoutStatus.skipped:
        return 'SKIPPED';
    }
  }

  static PayoutStatus fromApi(String? value) {
    switch ((value ?? '').trim().toUpperCase()) {
      case 'PAID':
        return PayoutStatus.paid;
      case 'SKIPPED':
        return PayoutStatus.skipped;
      // Legacy tokens from the earlier contract.
      case 'READY':
      case 'NOT_READY':
      case 'NOTREADY':
      case 'PENDING':
      default:
        return PayoutStatus.pending;
    }
  }
}

/// Incentive bookkeeping for a monthly review. Starts life with just an
/// [eligibleAmount] (copied from the employee record); [computedScorePct]
/// and [paidAt] fill in as the review advances.
class IncentiveSnapshot {
  /// The employee's configured monthly-incentive ceiling, snapshotted
  /// when the review is generated so a mid-month edit doesn't retro-
  /// change the review.
  final double eligibleAmount;

  /// Weighted % that drives the payout. `null` until a rating stage has
  /// scores.
  final double? computedScorePct;

  final PayoutStatus payoutStatus;
  final DateTime? paidAt;

  const IncentiveSnapshot({
    this.eligibleAmount = 0,
    this.computedScorePct,
    this.payoutStatus = PayoutStatus.pending,
    this.paidAt,
  });

  /// Final payable = ceiling × computedScorePct / 100. `null` until
  /// [computedScorePct] is set.
  double? get computedPayable {
    final pct = computedScorePct;
    if (pct == null) return null;
    return eligibleAmount * (pct / 100);
  }

  factory IncentiveSnapshot.fromJson(Map<String, dynamic> json) =>
      IncentiveSnapshot(
        eligibleAmount: JsonParse.parseDouble(json['eligibleAmount']) ?? 0,
        computedScorePct: JsonParse.parseDouble(json['computedScorePct']),
        payoutStatus:
            PayoutStatus.fromApi(JsonParse.parseString(json['payoutStatus'])),
        paidAt: JsonParse.parseDate(json['paidAt']),
      );

  Map<String, dynamic> toJson() => {
        'eligibleAmount': eligibleAmount,
        'computedScorePct': computedScorePct,
        'payoutStatus': payoutStatus.toApiString(),
        'paidAt': paidAt?.toIso8601String(),
      };

  IncentiveSnapshot copyWith({
    double? eligibleAmount,
    double? computedScorePct,
    PayoutStatus? payoutStatus,
    DateTime? paidAt,
  }) {
    return IncentiveSnapshot(
      eligibleAmount: eligibleAmount ?? this.eligibleAmount,
      computedScorePct: computedScorePct ?? this.computedScorePct,
      payoutStatus: payoutStatus ?? this.payoutStatus,
      paidAt: paidAt ?? this.paidAt,
    );
  }
}
