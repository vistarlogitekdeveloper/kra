import '../../../../core/api/json_parse.dart';
import '../../../auth/data/models/user.dart';
import 'monthly_kra_row.dart';
import 'review_stage.dart';

/// A calendar month a review belongs to. `month` is 1–12.
class ReviewPeriod {
  final int year;
  final int month;

  const ReviewPeriod(this.year, this.month);

  factory ReviewPeriod.fromDate(DateTime d) => ReviewPeriod(d.year, d.month);

  /// Stable key, e.g. "2026-06". Used for equality + map keys.
  String get key => '$year-${month.toString().padLeft(2, '0')}';

  /// e.g. "June 2026".
  String get label {
    const names = [
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
    final m = (month >= 1 && month <= 12) ? names[month] : '';
    return '$m $year';
  }

  /// A DateTime anchored at the given [day] of this period.
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

enum PayoutStatus {
  notReady,
  ready,
  paid;

  String toApiString() => name;

  static PayoutStatus fromApi(String? v) {
    switch ((v ?? '').trim().toUpperCase()) {
      case 'READY':
        return PayoutStatus.ready;
      case 'PAID':
        return PayoutStatus.paid;
      default:
        return PayoutStatus.notReady;
    }
  }
}

/// Per-stage audit record: who acted, when, and any comment.
class StageRecord {
  final StageStatus status;
  final String? actorId;
  final String? actorName;
  final DateTime? actedAt;
  final String? comment;

  const StageRecord({
    this.status = StageStatus.notStarted,
    this.actorId,
    this.actorName,
    this.actedAt,
    this.comment,
  });

  factory StageRecord.fromJson(Map<String, dynamic> json) => StageRecord(
        status: StageStatus.fromApi(JsonParse.parseString(json['status'])),
        actorId: JsonParse.parseString(json['actorId']),
        actorName: JsonParse.parseString(json['actorName']),
        actedAt: JsonParse.parseDate(json['actedAt']),
        comment: JsonParse.parseString(json['comment']),
      );

  Map<String, dynamic> toJson() => {
        'status': status.toApiString(),
        'actorId': actorId,
        'actorName': actorName,
        'actedAt': actedAt?.toIso8601String(),
        'comment': comment,
      };

  StageRecord copyWith({
    StageStatus? status,
    String? actorId,
    String? actorName,
    DateTime? actedAt,
    String? comment,
  }) {
    return StageRecord(
      status: status ?? this.status,
      actorId: actorId ?? this.actorId,
      actorName: actorName ?? this.actorName,
      actedAt: actedAt ?? this.actedAt,
      comment: comment ?? this.comment,
    );
  }
}

/// One employee's review for one calendar month, moving through the
/// 5-stage pipeline. This is the new replacement for the cycle-scoped
/// review — there is exactly one per (employee, month).
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
  final Map<ReviewStage, StageRecord> stageRecords;
  final List<MonthlyKraRow> rows;

  /// Per-employee monthly incentive the payout is computed against.
  final double eligibleAmount;
  final PayoutStatus payoutStatus;
  final DateTime? paidAt;

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
    this.eligibleAmount = 0,
    this.payoutStatus = PayoutStatus.notReady,
    this.paidAt,
  });

  StageRecord recordFor(ReviewStage stage) =>
      stageRecords[stage] ?? const StageRecord();

  /// Coarse role gate: the review is sitting on [currentStage] and [role]
  /// is allowed to act on it. Ownership/manager scoping is applied by the
  /// repository when it lists "my actionable reviews".
  bool isActionableBy(UserRole role) =>
      !currentStage.isTerminal && currentStage.actorRoles.contains(role);

  bool get isComplete => currentStage.isTerminal;

  /// Weighted 0–100 total of the scores recorded by [stage]. N/A handling
  /// isn't modelled here yet (mock); rows without a score contribute 0.
  double weightedScorePct(ReviewStage stage) {
    if (rows.isEmpty) return 0;
    double weighted = 0;
    double totalWeight = 0;
    for (final row in rows) {
      totalWeight += row.weightagePercent;
      final s = row.scoreFor(stage);
      if (s == null || row.maxScore <= 0) continue;
      weighted += (s.value / row.maxScore) * row.weightagePercent;
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
      if (rows.any((r) => r.scoreFor(stage) != null)) {
        return weightedScorePct(stage);
      }
    }
    return 0;
  }

  /// Projected payout = eligible × finalScore%.
  double get projectedPayout => eligibleAmount * finalScorePct / 100;

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
      eligibleAmount: JsonParse.parseDouble(json['eligibleAmount']) ?? 0,
      payoutStatus:
          PayoutStatus.fromApi(JsonParse.parseString(json['payoutStatus'])),
      paidAt: JsonParse.parseDate(json['paidAt']),
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
        'eligibleAmount': eligibleAmount,
        'payoutStatus': payoutStatus.toApiString(),
        'paidAt': paidAt?.toIso8601String(),
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
    double? eligibleAmount,
    PayoutStatus? payoutStatus,
    DateTime? paidAt,
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
      eligibleAmount: eligibleAmount ?? this.eligibleAmount,
      payoutStatus: payoutStatus ?? this.payoutStatus,
      paidAt: paidAt ?? this.paidAt,
    );
  }
}
