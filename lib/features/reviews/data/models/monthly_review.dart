import '../../../../core/api/json_parse.dart';
import '../../../auth/data/models/user.dart';
import 'incentive_snapshot.dart';
import 'monthly_kra_row.dart';
import 'review_stage.dart';
import 'stage_record.dart';
import 'stage_status.dart';

/// A calendar month a review belongs to. `month` is 1–12.
class ReviewPeriod {
  final int year;
  final int month;

  const ReviewPeriod(this.year, this.month);

  factory ReviewPeriod.fromDate(DateTime d) => ReviewPeriod(d.year, d.month);

  /// Stable key, e.g. "2026-06". Used for equality + map keys.
  String get key => '$year-${month.toString().padLeft(2, '0')}';

  static const _names = [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// e.g. "June 2026".
  String get label => '${(month >= 1 && month <= 12) ? _names[month] : ''} '
      '$year';

  /// A DateTime anchored at [day] of this period.
  DateTime dateOn(int day) => DateTime(year, month, day);

  factory ReviewPeriod.parse(String key) {
    final parts = key.split('-');
    return ReviewPeriod(
      int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0,
      int.tryParse(parts.length > 1 ? parts[1] : '') ?? 1,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReviewPeriod && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

/// One employee's review for one calendar month, moving through the
/// 5-stage pipeline. Exactly one exists per (employee, month) — the
/// replacement for the cycle-scoped review.
class MonthlyReview {
  final String id;
  final String employeeId;
  final String employeeName;
  final String employeeCode;
  final String? grade;
  final String? managerId;
  final String? managerName;

  final ReviewPeriod period;
  final ReviewStage currentStage;

  /// A record exists in this map only for **submitted** stages — its
  /// presence is the source of truth for "this stage is done".
  final Map<ReviewStage, StageRecord> stageRecords;
  final List<MonthlyKraRow> rows;

  final IncentiveSnapshot incentive;

  const MonthlyReview({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    this.employeeCode = '',
    this.grade,
    this.managerId,
    this.managerName,
    required this.period,
    this.currentStage = ReviewStage.selfRating,
    this.stageRecords = const {},
    this.rows = const [],
    this.incentive = const IncentiveSnapshot(),
  });

  // ── Incentive convenience (delegates to [incentive]) ──────────────────
  double get eligibleAmount => incentive.eligibleAmount;
  PayoutStatus get payoutStatus => incentive.payoutStatus;
  DateTime? get paidAt => incentive.paidAt;

  StageRecord? recordFor(ReviewStage stage) => stageRecords[stage];

  /// Derived coarse status of [stage] on this review.
  StageStatus statusOf(ReviewStage stage) {
    if (stage.isTerminal) {
      return isComplete ? StageStatus.submitted : StageStatus.pending;
    }
    if (stageRecords.containsKey(stage)) return StageStatus.submitted;
    if (stage == currentStage) return StageStatus.inProgress;
    return StageStatus.pending;
  }

  /// Coarse role gate: the review sits on [currentStage] and [role] can
  /// act on it. Ownership/manager scoping is applied by the repository.
  bool isActionableBy(UserRole role) =>
      !currentStage.isTerminal && currentStage.actorRoles.contains(role);

  bool get isComplete => currentStage.isTerminal;

  /// Weighted 0–100 total of the scores recorded by [stage]. Rows
  /// without a score (or N/A) drop out of both numerator and denominator.
  double weightedScorePct(ReviewStage stage) {
    double weighted = 0;
    double totalWeight = 0;
    for (final row in rows) {
      final s = row.scoreFor(stage);
      if (s == null || s.value == null || row.maxScore <= 0) continue;
      totalWeight += row.weightagePercent;
      weighted += (s.value! / row.maxScore) * row.weightagePercent;
    }
    if (totalWeight <= 0) return 0;
    return (weighted * 100 / totalWeight).clamp(0, 100).toDouble();
  }

  /// The agreed score that drives the incentive — the furthest-along
  /// rating stage that has any scores (manager → account/HR → self).
  double get finalScorePct {
    for (final stage in const [
      ReviewStage.reportingManagerRating,
      ReviewStage.accountHrRating,
      ReviewStage.selfRating,
    ]) {
      if (rows.any((r) => r.scoreFor(stage)?.value != null)) {
        return weightedScorePct(stage);
      }
    }
    return 0;
  }

  /// Projected payout = eligible × finalScore%.
  double get projectedPayout => eligibleAmount * finalScorePct / 100;

  /// The furthest-along rating stage that carries any recorded score, or
  /// null if nothing has been scored yet.
  ///
  /// Scores are entered in place via `save-scores`, which deliberately does
  /// NOT advance [currentStage]. So a review whose manager has already rated
  /// still reports `currentStage == selfRating`. Progress must therefore be
  /// read off the scores themselves, not the (frozen) pipeline cursor.
  ReviewStage? get furthestScoredStage {
    ReviewStage? found;
    for (final stage in const [
      ReviewStage.selfRating,
      ReviewStage.accountHrRating,
      ReviewStage.reportingManagerRating,
    ]) {
      if (rows.any((r) => r.scoreFor(stage)?.value != null)) found = stage;
    }
    return found;
  }

  /// Stage to show on dashboards: whichever is further along — the formal
  /// pipeline cursor or the furthest stage that actually has scores. This
  /// keeps the badge honest when rating happens via in-place `save-scores`.
  ReviewStage get displayStage {
    final scored = furthestScoredStage;
    if (scored == null) return currentStage;
    return scored.pipelineIndex >= currentStage.pipelineIndex
        ? scored
        : currentStage;
  }

  /// Status of [displayStage] — submitted once that stage carries scores.
  StageStatus get displayStatus {
    if (isComplete) return StageStatus.submitted;
    final scored = furthestScoredStage;
    if (scored != null && scored == displayStage) return StageStatus.submitted;
    return statusOf(displayStage);
  }

  factory MonthlyReview.fromJson(Map<String, dynamic> json) {
    final records = <ReviewStage, StageRecord>{};
    final rawRecords = JsonParse.parseMap(json['stageRecords']);
    if (rawRecords != null) {
      rawRecords.forEach((k, v) {
        final map = JsonParse.parseMap(v);
        if (map != null) {
          records[ReviewStage.fromApi(k)] = StageRecord.fromJson(map);
        }
      });
    }
    final period = json['period'] is String
        ? ReviewPeriod.parse(json['period'] as String)
        : ReviewPeriod(
            JsonParse.parseInt(json['year']) ?? 0,
            JsonParse.parseInt(json['month']) ?? 1,
          );
    // Incentive may arrive nested under `incentive`, or flat on the
    // review (eligibleAmount / payoutStatus / paidAt) — read both.
    final incentiveMap = JsonParse.parseMap(json['incentive']);
    final incentive = incentiveMap != null
        ? IncentiveSnapshot.fromJson(incentiveMap)
        : IncentiveSnapshot(
            eligibleAmount: JsonParse.parseDouble(json['eligibleAmount']) ?? 0,
            payoutStatus: PayoutStatus.fromApi(
                JsonParse.parseString(json['payoutStatus'])),
            paidAt: JsonParse.parseDate(json['paidAt']),
          );
    return MonthlyReview(
      id: JsonParse.parseString(json['id']) ?? '',
      employeeId: JsonParse.parseString(json['employeeId']) ?? '',
      employeeName: JsonParse.parseString(json['employeeName']) ?? '',
      employeeCode: JsonParse.parseString(json['employeeCode']) ?? '',
      grade: JsonParse.parseString(json['grade']),
      managerId: JsonParse.parseString(json['managerId']),
      managerName: JsonParse.parseString(json['managerName']),
      period: period,
      currentStage:
          ReviewStage.fromApi(JsonParse.parseString(json['currentStage'])),
      stageRecords: records,
      rows: JsonParse.parseMapList(json['rows'])
          .map(MonthlyKraRow.fromJson)
          .toList(),
      incentive: incentive,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'employeeId': employeeId,
        'employeeName': employeeName,
        'employeeCode': employeeCode,
        'grade': grade,
        'managerId': managerId,
        'managerName': managerName,
        'period': period.key,
        'currentStage': currentStage.toApiString(),
        'stageRecords':
            stageRecords.map((k, v) => MapEntry(k.toApiString(), v.toJson())),
        'rows': rows.map((r) => r.toJson()).toList(),
        'incentive': incentive.toJson(),
      };

  MonthlyReview copyWith({
    String? id,
    String? employeeId,
    String? employeeName,
    String? employeeCode,
    String? grade,
    String? managerId,
    String? managerName,
    ReviewPeriod? period,
    ReviewStage? currentStage,
    Map<ReviewStage, StageRecord>? stageRecords,
    List<MonthlyKraRow>? rows,
    IncentiveSnapshot? incentive,
  }) {
    return MonthlyReview(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      employeeName: employeeName ?? this.employeeName,
      employeeCode: employeeCode ?? this.employeeCode,
      grade: grade ?? this.grade,
      managerId: managerId ?? this.managerId,
      managerName: managerName ?? this.managerName,
      period: period ?? this.period,
      currentStage: currentStage ?? this.currentStage,
      stageRecords: stageRecords ?? this.stageRecords,
      rows: rows ?? this.rows,
      incentive: incentive ?? this.incentive,
    );
  }
}
