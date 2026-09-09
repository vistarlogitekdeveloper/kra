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

  /// The month whose rating window is open on [now] — the PREVIOUS calendar
  /// month, never the current one.
  ///
  /// A month is rated once it has finished: through September you rate August.
  /// The deadline schedule already assumed this and is what makes it provable
  /// rather than a preference — [MonthlyDeadlines] puts self-rating on the
  /// **10th**, so treating the current month as the one under review meant
  /// asking someone on 10 September to have finished rating a September that
  /// still had twenty days left to run.
  ///
  /// Every "which month are we rating?" decision must come through here.
  /// Before this existed the answer was derived independently in five places —
  /// the backend's `findCurrentMonth`, the employee dashboard's fallback, the
  /// month picker, the sheet's due-month banner and the cell gate — and they
  /// did not agree.
  factory ReviewPeriod.openForRating(DateTime now) =>
      ReviewPeriod.fromDate(now).previous;

  /// The month before this one, rolling the year back at January.
  ReviewPeriod get previous =>
      month == 1 ? ReviewPeriod(year - 1, 12) : ReviewPeriod(year, month - 1);

  /// The month after this one, rolling the year forward at December.
  ReviewPeriod get next =>
      month == 12 ? ReviewPeriod(year + 1, 1) : ReviewPeriod(year, month + 1);

  /// Calendar order, so months can be compared without unpacking them.
  /// Negative when this month is earlier than [other].
  int compareTo(ReviewPeriod other) =>
      year != other.year ? year - other.year : month - other.month;

  bool operator <=(ReviewPeriod other) => compareTo(other) <= 0;
  bool operator >(ReviewPeriod other) => compareTo(other) > 0;

  /// Whether this month may be rated as of [now] — i.e. it has ended.
  ///
  /// True for the open review month and anything older; false for the current
  /// calendar month and anything ahead of it.
  bool isRatableOn(DateTime now) => this <= ReviewPeriod.openForRating(now);

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

  /// Compact "Jul '26" — a 3-letter month + 2-digit year for tight table
  /// headers and month chips.
  String get shortLabel =>
      "${(month >= 1 && month <= 12) ? _names[month].substring(0, 3) : ''} "
      "'${year.toString().substring(2)}";

  /// India's fiscal-year quarter this month falls in:
  ///   Q1 = Apr–Jun, Q2 = Jul–Sep, Q3 = Oct–Dec, Q4 = Jan–Mar.
  int get fiscalQuarter {
    if (month >= 4 && month <= 6) return 1;
    if (month >= 7 && month <= 9) return 2;
    if (month >= 10 && month <= 12) return 3;
    return 4; // Jan–Mar
  }

  /// The calendar year India's fiscal year STARTS in for this period — the FY
  /// runs Apr→Mar, so Jan–Mar belong to the PREVIOUS April's fiscal year.
  int get fiscalYearStartYear => month >= 4 ? year : year - 1;

  /// e.g. "FY 2026–27".
  String get fiscalYearLabel {
    final start = fiscalYearStartYear;
    final end = (start + 1) % 100;
    return 'FY $start–${end.toString().padLeft(2, '0')}';
  }

  /// e.g. "Q2 · FY 2026–27".
  String get fiscalQuarterLabel => 'Q$fiscalQuarter · $fiscalYearLabel';

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

  /// When set, management has committed the review: the incentive is locked to
  /// the management scores and the Management column is read-only until it is
  /// reopened. Null while the management review is still open.
  final DateTime? managementLockedAt;

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
    this.managementLockedAt,
  });

  // ── Incentive convenience (delegates to [incentive]) ──────────────────
  double get eligibleAmount => incentive.eligibleAmount;
  PayoutStatus get payoutStatus => incentive.payoutStatus;
  DateTime? get paidAt => incentive.paidAt;

  /// True once management has locked the review (see [managementLockedAt]).
  bool get isManagementLocked => managementLockedAt != null;

  StageRecord? recordFor(ReviewStage stage) => stageRecords[stage];

  /// The record of a stage being sent BACK, if that is what last happened to it.
  ///
  /// Carries who returned it, when, and — in [StageRecord.comment] — why, which
  /// is what the person it landed back on needs to read.
  StageRecord? returnedRecordFor(ReviewStage stage) {
    final r = stageRecords[stage];
    return (r != null && r.returned) ? r : null;
  }

  /// True when [stage] was sent back for rework and is waiting to be redone.
  ///
  /// Only meaningful while the pipeline is actually sitting on the stage the work
  /// was returned TO — once it moves on again, the record is history.
  bool get selfRatingReturned =>
      currentStage == ReviewStage.selfRating &&
      returnedRecordFor(ReviewStage.reportingManagerRating) != null;

  /// Derived coarse status of [stage] on this review.
  StageStatus statusOf(ReviewStage stage) {
    if (stage.isTerminal) {
      return isComplete ? StageStatus.submitted : StageStatus.pending;
    }
    // A RETURNED record is not a completion: that submission pushed the review
    // backwards. Counting it as submitted would show the manager's stage as done
    // immediately after they sent the work back.
    final record = stageRecords[stage];
    if (record != null && !record.returned) return StageStatus.submitted;
    if (stage == currentStage) return StageStatus.inProgress;
    return StageStatus.pending;
  }

  /// Whether the caller can act on this review's [currentStage] right now.
  ///
  /// The two rating stages that involve a person are RELATIONSHIPS, not roles,
  /// and are resolved against this review when [userId] is supplied:
  ///   * self-rating → the owner ([employeeId]), whatever their role — managers
  ///     and HR admins have their own KRA to rate too;
  ///   * reporting-manager rating → this review's [managerId], whatever THEIR
  ///     role — every employee has a reporting manager, and that manager may
  ///     well be an HR admin or a senior manager rather than a manager-tier
  ///     role. Fails closed when [managerId] is null (no manager mapped).
  ///
  /// The org-level stages (account/HR rating, management review, incentive
  /// payout) remain role-gated via [ReviewStage.actorRoles].
  ///
  /// [userId] is optional only for backwards compatibility; omitting it makes
  /// the relationship stages unresolvable and therefore not actionable.
  bool isActionableBy(UserRole role, {String? userId}) {
    if (currentStage.isTerminal) return false;
    if (currentStage == ReviewStage.selfRating) {
      return userId != null && userId == employeeId;
    }
    if (currentStage == ReviewStage.reportingManagerRating) {
      return userId != null && managerId != null && userId == managerId;
    }
    return currentStage.actorRoles.contains(role);
  }

  bool get isComplete => currentStage.isTerminal;

  /// Weighted 0–100 total of the scores recorded by [stage]. Rows
  /// without a score (or N/A) drop out of both numerator and denominator.
  double weightedScorePct(ReviewStage stage) {
    double weighted = 0;
    double totalWeight = 0;
    for (final row in rows) {
      final value = row.scoreFor(stage)?.value;
      if (value == null || row.maxScore <= 0) continue;
      totalWeight += row.weightagePercent;
      weighted += (value / row.maxScore) * row.weightagePercent;
    }
    if (totalWeight <= 0) return 0;
    return (weighted * 100 / totalWeight).clamp(0, 100).toDouble();
  }

  /// The Review-cycle (cycle 2) score for a single KRA row, as a 0–100 %.
  ///
  /// A KRA is defined "in three parts": each KRA is ASSIGNED to exactly one
  /// reviewer (Reporting Manager / HR / Accounts — see [MonthlyKraRow.reviewStage]),
  /// so its Review score is that one reviewer's rating. Legacy rows with no
  /// assignment fall back to averaging whichever of the three rated it. Null
  /// until the relevant rater(s) have scored the row.
  double? reviewPctForRow(MonthlyKraRow row) {
    if (row.maxScore <= 0) return null;
    final assigned = row.reviewStage;
    if (assigned != null) {
      // Bound to a local so the null check promotes it — `s?.value` cannot
      // be promoted through the null-aware access, which is the only reason
      // the previous form needed two bang operators.
      final value = row.scoreFor(assigned)?.value;
      if (value == null) return null;
      return (value / row.maxScore) * 100;
    }
    // Legacy fallback: average whichever of the three raters scored the row.
    final present = <double>[];
    for (final stage in ReviewStage.reviewRaters) {
      final value = row.scoreFor(stage)?.value;
      if (value != null) present.add((value / row.maxScore) * 100);
    }
    if (present.isEmpty) return null;
    return present.reduce((a, b) => a + b) / present.length;
  }

  /// Weighted 0–100 total of the Review cycle — each KRA's [reviewPctForRow]
  /// weighted by its KRA weight. Rows nobody has reviewed drop out.
  double get reviewWeightedPct {
    double weighted = 0;
    double totalWeight = 0;
    for (final row in rows) {
      final pct = reviewPctForRow(row);
      if (pct == null) continue;
      totalWeight += row.weightagePercent;
      weighted += pct * row.weightagePercent;
    }
    if (totalWeight <= 0) return 0;
    return (weighted / totalWeight).clamp(0, 100).toDouble();
  }

  /// The final score for a single KRA row, as a 0–100 %, by cycle precedence
  /// applied PER ROW: management override (rework) → the row's Review score →
  /// self. Null until the row has any of the three.
  ///
  /// Precedence is per row, not per review: management reworks ONE KRA at a
  /// time, and each KRA's Review score comes from its own assigned reviewer —
  /// so a review can hold a management override on KRA A, a plain Review score
  /// on KRA B and only a self score on KRA C, each contributing its own final.
  double? finalPctForRow(MonthlyKraRow row) {
    if (row.maxScore <= 0) return null;
    final mgmt = row.scoreFor(ReviewStage.managementReview)?.value;
    if (mgmt != null) return (mgmt / row.maxScore) * 100;
    final review = reviewPctForRow(row);
    if (review != null) return review;
    final self = row.scoreFor(ReviewStage.selfRating)?.value;
    if (self != null) return (self / row.maxScore) * 100;
    return null;
  }

  /// The score that drives the incentive: the weighted total of every KRA's
  /// [finalPctForRow], so each KRA contributes its own furthest-along score.
  /// Rows nothing has touched drop from both numerator and denominator.
  double get finalScorePct {
    double weighted = 0;
    double totalWeight = 0;
    for (final row in rows) {
      final pct = finalPctForRow(row);
      if (pct == null) continue;
      totalWeight += row.weightagePercent;
      weighted += pct * row.weightagePercent;
    }
    if (totalWeight <= 0) return 0;
    return (weighted / totalWeight).clamp(0, 100).toDouble();
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
    // Pipeline order: self → the three Review raters → management override.
    for (final stage in const [
      ReviewStage.selfRating,
      ReviewStage.reportingManagerRating,
      ReviewStage.accountHrRating,
      ReviewStage.financeRating,
      ReviewStage.managementReview,
    ]) {
      if (rows.any((r) => r.scoreFor(stage)?.value != null)) found = stage;
    }
    return found;
  }

  /// True when the Review phase (cycle 2) is DONE for this review — every KRA
  /// has been scored by its single ASSIGNED reviewer (Reporting Manager / HR /
  /// Accounts). Because each KRA is owned by exactly one reviewer,
  /// [reviewPctForRow] is non-null precisely when that reviewer has rated it,
  /// so "all rows have a Review score" is the honest completion signal — not
  /// "the furthest of three raters happened to score something".
  bool get reviewPhaseComplete {
    if (rows.isEmpty) return false;
    for (final row in rows) {
      if (reviewPctForRow(row) == null) return false;
    }
    return true;
  }

  bool get _hasManagementScore =>
      rows.any((r) => r.scoreFor(ReviewStage.managementReview)?.value != null);

  /// Stage to show on dashboards, mapped to the conceptual pipeline
  /// (Self → Review → Management → Payout):
  ///   * Review phase fully done but management hasn't overridden yet →
  ///     Management Review (the pending next step). This is the key fix: a
  ///     review whose RM/HR/Accounts ratings are all in should read as
  ///     "Management Review", not as whichever rater scored last.
  ///   * otherwise the furthest stage that actually carries scores (or the
  ///     formal cursor if it's further along).
  ReviewStage get displayStage {
    if (reviewPhaseComplete && !_hasManagementScore) {
      // Don't regress a cursor that's already past management (payout/done).
      return ReviewStage.managementReview.pipelineIndex >=
              currentStage.pipelineIndex
          ? ReviewStage.managementReview
          : currentStage;
    }
    final scored = furthestScoredStage;
    if (scored == null) return currentStage;
    return scored.pipelineIndex >= currentStage.pipelineIndex
        ? scored
        : currentStage;
  }

  /// Status of [displayStage]:
  ///   * the Review phase is "in progress" (orange) until EVERY assigned
  ///     reviewer has rated — a partly-reviewed sheet must not read as done;
  ///   * Management Review surfaced because the Review phase finished but
  ///     management hasn't acted is likewise pending action (in progress);
  ///   * otherwise submitted once the displayed stage carries scores.
  StageStatus get displayStatus {
    if (isComplete) return StageStatus.submitted;
    final ds = displayStage;
    if (ds.reviewCycle == 2) {
      // A rater stage is only ever the display stage while the Review phase is
      // still underway (a complete one advances to Management Review above).
      return StageStatus.inProgress;
    }
    if (ds == ReviewStage.managementReview &&
        reviewPhaseComplete &&
        !_hasManagementScore) {
      return StageStatus.inProgress; // review done → awaiting management
    }
    final scored = furthestScoredStage;
    if (scored != null && scored == ds) return StageStatus.submitted;
    return statusOf(ds);
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
      managementLockedAt: JsonParse.parseDate(json['managementLockedAt']),
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
        'managementLockedAt': managementLockedAt?.toIso8601String(),
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
    DateTime? managementLockedAt,
    bool clearManagementLock = false,
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
      managementLockedAt: clearManagementLock
          ? null
          : (managementLockedAt ?? this.managementLockedAt),
    );
  }
}
