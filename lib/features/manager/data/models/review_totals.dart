import '../../../../core/api/json_parse.dart';

/// Snapshot of the four cumulative score totals on a review, all
/// 0-100 percentages. Each is nullable because not every rater pass
/// has run yet — `managerTotal` is null on EMPLOYEE_SUBMITTED_ALL,
/// `finalTotal` is null until FINALIZED, etc.
///
/// `incentiveAmount` joins the totals here so the UI can render the
/// finalised review's payout in one consistent place.
class ReviewTotals {
  final double? selfTotal;
  final double? managerTotal;
  final double? opsTotal;
  final double? financeTotal;
  final double? finalTotal;

  /// Computed payout when the review is finalised. Decimal-on-wire
  /// (e.g. `"5325.00"`) — currency-format at the call site, not here.
  final double? incentiveAmount;

  const ReviewTotals({
    this.selfTotal,
    this.managerTotal,
    this.opsTotal,
    this.financeTotal,
    this.finalTotal,
    this.incentiveAmount,
  });

  factory ReviewTotals.fromJson(Map<String, dynamic> json) => ReviewTotals(
        selfTotal: JsonParse.parseDouble(json['selfTotal']),
        managerTotal: JsonParse.parseDouble(json['managerTotal']),
        opsTotal: JsonParse.parseDouble(json['opsTotal']),
        financeTotal: JsonParse.parseDouble(json['financeTotal']),
        finalTotal: JsonParse.parseDouble(json['finalTotal']),
        incentiveAmount: JsonParse.parseDouble(json['incentiveAmount']),
      );

  Map<String, dynamic> toJson() => {
        'selfTotal': selfTotal,
        'managerTotal': managerTotal,
        'opsTotal': opsTotal,
        'financeTotal': financeTotal,
        'finalTotal': finalTotal,
        'incentiveAmount': incentiveAmount,
      };

  ReviewTotals copyWith({
    Object? selfTotal = _sentinel,
    Object? managerTotal = _sentinel,
    Object? opsTotal = _sentinel,
    Object? financeTotal = _sentinel,
    Object? finalTotal = _sentinel,
    Object? incentiveAmount = _sentinel,
  }) {
    return ReviewTotals(
      selfTotal: identical(selfTotal, _sentinel)
          ? this.selfTotal
          : selfTotal as double?,
      managerTotal: identical(managerTotal, _sentinel)
          ? this.managerTotal
          : managerTotal as double?,
      opsTotal: identical(opsTotal, _sentinel)
          ? this.opsTotal
          : opsTotal as double?,
      financeTotal: identical(financeTotal, _sentinel)
          ? this.financeTotal
          : financeTotal as double?,
      finalTotal: identical(finalTotal, _sentinel)
          ? this.finalTotal
          : finalTotal as double?,
      incentiveAmount: identical(incentiveAmount, _sentinel)
          ? this.incentiveAmount
          : incentiveAmount as double?,
    );
  }

  static const _sentinel = Object();
}
