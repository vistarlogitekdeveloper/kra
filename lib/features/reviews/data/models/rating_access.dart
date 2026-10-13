import '../../../../core/api/json_parse.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/enums/review_flow.dart';
import 'monthly_review.dart';
import 'rating_window.dart';
import 'review_flow.dart';
import 'review_stage.dart';

/// What a super-admin override does to one stage of one month. See
/// docs/RATING_ACCESS.md §3.5.
enum RatingAccessMode {
  /// Rate and edit until `openUntil`, or with no end.
  open,

  /// Shut, whatever the deadline says.
  closed;

  /// Exact wire names. Anything else is null: an override whose effect cannot
  /// be named is skipped rather than guessed at.
  static RatingAccessMode? fromApi(Object? value) {
    switch (JsonParse.parseString(value)?.trim().toUpperCase()) {
      case 'OPEN':
        return RatingAccessMode.open;
      case 'CLOSED':
        return RatingAccessMode.closed;
      default:
        return null;
    }
  }

  String toApiString() => name.toUpperCase();
}

/// The rating stage named by [value], by EXACT wire name, or null.
///
/// Never `ReviewStage.fromApi`, which files an unknown name under SELF_RATING
/// and would put an override on the wrong seat. INCENTIVE_PAYOUT and COMPLETED
/// are not ratings and are never gated, so they read as null too.
ReviewStage? ratingStageFromWire(Object? value) {
  final wire = JsonParse.parseString(value)?.trim().toUpperCase();
  if (wire == null) return null;
  for (final stage in ReviewStage.values) {
    if (stage.isRatingStage && stage.toApiString() == wire) return stage;
  }
  return null;
}

/// The stage named for the seat that rates it under [flow] — the server's
/// `stageLabel` (rating-access.rules.js), word for word, so this app and the
/// refusals the server writes use the same names.
///
/// Under ADMIN_ONLY the reporting-manager seat is MANAGEMENT, rating the KRAs
/// that HR and Accounts were not given. Keyed off the relationship gate rather
/// than the flow's name, so the label follows whoever actually rates.
String ratingStageLabel(ReviewStage stage, ReviewFlow flow) {
  switch (stage) {
    case ReviewStage.selfRating:
      return AppStrings.ratingAccessStageSelf;
    case ReviewStage.reportingManagerRating:
      return stageIsRelationshipGated(stage, flow)
          ? AppStrings.ratingAccessStageReportingManager
          : AppStrings.ratingAccessStageManagementRating;
    case ReviewStage.accountHrRating:
      return AppStrings.ratingAccessStageHr;
    case ReviewStage.financeRating:
      return AppStrings.ratingAccessStageAccounts;
    case ReviewStage.managementReview:
      return AppStrings.ratingAccessStageManagementReview;
    case ReviewStage.incentivePayout:
    case ReviewStage.completed:
      return stage.label;
  }
}

/// `YYYY-MM` → the month, or null.
///
/// Strict where `ReviewPeriod.parse` is lenient: that one reads garbage as
/// (0, 1), a real-looking month nobody asked for. Bounded to 2000–2100 like
/// the server's `parsePeriod`, so a typo cannot address the year 20260.
ReviewPeriod? parseRatingPeriod(Object? value) {
  final raw = JsonParse.parseString(value)?.trim();
  if (raw == null) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(raw);
  if (match == null) return null;
  return _validPeriod(
    int.tryParse(match.group(1) ?? ''),
    int.tryParse(match.group(2) ?? ''),
  );
}

ReviewPeriod? _validPeriod(int? year, int? month) {
  if (year == null || month == null) return null;
  if (year < 2000 || year > 2100 || month < 1 || month > 12) return null;
  return ReviewPeriod(year, month);
}

/// The `period` string of a rating-access payload, then its `year` + `month`,
/// so a payload that only carries the parts still reads.
ReviewPeriod? ratingPeriodOfJson(Map<String, dynamic> json) =>
    parseRatingPeriod(json['period']) ??
    _validPeriod(
      JsonParse.parseInt(json['year']),
      JsonParse.parseInt(json['month']),
    );

/// One super-admin override: organisation × stage × month.
class RatingAccessOverride {
  final String id;
  final ReviewStage stage;
  final ReviewPeriod period;
  final RatingAccessMode mode;

  /// End of the reopen. Null means no end for [RatingAccessMode.open], and is
  /// always null for [RatingAccessMode.closed].
  final DateTime? openUntil;
  final String? reason;
  final DateTime? updatedAt;
  final String? updatedById;
  final String? updatedByName;

  const RatingAccessOverride({
    required this.id,
    required this.stage,
    required this.period,
    required this.mode,
    this.openUntil,
    this.reason,
    this.updatedAt,
    this.updatedById,
    this.updatedByName,
  });

  /// Null when [raw] is not a map, or its stage, mode or month cannot be read.
  ///
  /// [fallbackPeriod] covers an override embedded in a month view, where the
  /// month is implied by the view.
  static RatingAccessOverride? fromJson(
    Object? raw, {
    ReviewPeriod? fallbackPeriod,
  }) {
    final json = JsonParse.parseMap(raw);
    if (json == null) return null;
    final stage = ratingStageFromWire(json['stage']);
    final mode = RatingAccessMode.fromApi(json['mode']);
    final period = ratingPeriodOfJson(json) ?? fallbackPeriod;
    if (stage == null || mode == null || period == null) return null;
    final reason = JsonParse.parseString(json['reason'])?.trim();
    return RatingAccessOverride(
      id: JsonParse.parseString(json['id']) ?? '',
      stage: stage,
      period: period,
      mode: mode,
      openUntil: mode == RatingAccessMode.open
          ? JsonParse.parseDate(json['openUntil'])
          : null,
      reason: (reason == null || reason.isEmpty) ? null : reason,
      updatedAt: JsonParse.parseDate(json['updatedAt']),
      updatedById: JsonParse.parseString(json['updatedById']),
      updatedByName: JsonParse.parseString(json['updatedByName']),
    );
  }

  /// Whether an OPEN override's end has passed at [now]. An override with no
  /// end, or a CLOSED one, never ends on its own.
  bool hasEndedAt(DateTime now) {
    final until = openUntil;
    return mode == RatingAccessMode.open && until != null && now.isAfter(until);
  }

  /// Sort order for lists: the most recently changed first, undated last.
  static int newestFirst(RatingAccessOverride a, RatingAccessOverride b) {
    final at = a.updatedAt;
    final bt = b.updatedAt;
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  }
}

/// One stage of a month view: the window the server resolved for it, and the
/// override behind that window, if any.
class RatingAccessStage {
  final ReviewStage stage;

  /// Org-level: the month view carries no per-review rework state, so this is
  /// never RETURNED.
  final RatingWindow window;

  /// The super admin's override for this stage and month. Named so because a
  /// member called `override` would shadow the `@override` annotation.
  final RatingAccessOverride? adminOverride;

  const RatingAccessStage({
    required this.stage,
    required this.window,
    this.adminOverride,
  });

  /// An OPEN override that changes nothing: it ends on or before the stage's
  /// deadline, so the server resolved the deadline instead (§2, row 5). The
  /// server refuses to SET one, but a row can still become one when the
  /// deadline day is moved by configuration after it was set.
  bool get overrideIsInert =>
      adminOverride?.mode == RatingAccessMode.open &&
      window.source == RatingWindowSource.deadline;

  /// Null when the stage or its window cannot be read: a window without an
  /// opening instant cannot be evaluated, and guessing one would be guessing
  /// whether people may rate. A malformed override, or one filed under a
  /// different stage, is dropped and the stage kept.
  static RatingAccessStage? fromJson(
    Object? raw, {
    ReviewPeriod? period,
    Duration clockSkew = Duration.zero,
  }) {
    final json = JsonParse.parseMap(raw);
    if (json == null) return null;
    final stage = ratingStageFromWire(json['stage']);
    final window = RatingWindow.fromJson(json['window'], clockSkew: clockSkew);
    if (stage == null || window == null) return null;
    final parsed =
        RatingAccessOverride.fromJson(json['override'], fallbackPeriod: period);
    return RatingAccessStage(
      stage: stage,
      window: window,
      adminOverride: parsed?.stage == stage ? parsed : null,
    );
  }
}

/// `GET /organizations/:organizationId/rating-access/:period` — every rating
/// stage of one month for one organisation, as the server resolved it.
class RatingAccessMonth {
  final String organizationId;
  final String? organizationName;

  /// The flow of the organisation in the PATH — never the acting one, which is
  /// a different organisation whenever the super admin has not switched in.
  final ReviewFlow reviewFlow;
  final ReviewPeriod period;

  /// Pipeline order, one entry per stage.
  final List<RatingAccessStage> stages;

  /// The server's clock when it answered. Null from a server that predates it.
  final DateTime? serverNow;

  /// [serverNow] minus this device's clock when the answer arrived; zero when
  /// the server sent no clock. Windows are the server's instants, so they are
  /// read against the server's time — see [serverTimeAt].
  final Duration clockSkew;

  const RatingAccessMonth({
    required this.organizationId,
    this.organizationName,
    required this.reviewFlow,
    required this.period,
    required this.stages,
    this.serverNow,
    this.clockSkew = Duration.zero,
  });

  /// The server's time at the device instant [deviceNow]: what every window of
  /// this month is evaluated against, so a device whose clock is off neither
  /// shows a closed stage as open nor an open one as closed.
  DateTime serverTimeAt(DateTime deviceNow) => deviceNow.add(clockSkew);

  /// Null when no month can be read, or not one stage parses — a month with
  /// nothing to show is a malformed answer, not an empty one.
  ///
  /// [receivedAt] is the device's clock when the response arrived; with the
  /// payload's `serverNow` it gives [clockSkew].
  static RatingAccessMonth? fromJson(
    Object? raw, {
    String? fallbackOrganizationId,
    ReviewPeriod? fallbackPeriod,
    DateTime? receivedAt,
  }) {
    final json = JsonParse.parseMap(raw);
    if (json == null) return null;
    final period = ratingPeriodOfJson(json) ?? fallbackPeriod;
    if (period == null) return null;
    final serverNow = JsonParse.parseDate(json['serverNow']);
    // Every window is read against the server's time, so a device whose clock
    // is off shows the same open/closed answer the server will enforce.
    final clockSkew = (serverNow == null || receivedAt == null)
        ? Duration.zero
        : serverNow.difference(receivedAt);

    final byStage = <ReviewStage, RatingAccessStage>{};
    final rawStages = json['stages'];
    if (rawStages is List) {
      for (final entry in rawStages) {
        final parsed = RatingAccessStage.fromJson(
          entry,
          period: period,
          clockSkew: clockSkew,
        );
        // First entry wins, so a duplicated stage cannot flip a card.
        if (parsed != null) byStage.putIfAbsent(parsed.stage, () => parsed);
      }
    }
    if (byStage.isEmpty) return null;

    final name = JsonParse.parseString(json['organizationName'])?.trim();
    return RatingAccessMonth(
      organizationId: JsonParse.parseString(json['organizationId']) ??
          fallbackOrganizationId ??
          '',
      organizationName: (name == null || name.isEmpty) ? null : name,
      reviewFlow: ReviewFlow.fromApi(JsonParse.parseString(json['reviewFlow'])),
      period: period,
      stages: byStage.values.toList()
        ..sort((a, b) => a.stage.pipelineIndex - b.stage.pipelineIndex),
      serverNow: serverNow,
      clockSkew: clockSkew,
    );
  }

  RatingAccessStage? stageFor(ReviewStage stage) {
    for (final entry in stages) {
      if (entry.stage == stage) return entry;
    }
    return null;
  }

  /// The stages this organisation's flow uses — under ADMIN_ONLY, everything
  /// but the self-rating.
  List<RatingAccessStage> get stagesInFlow => [
        for (final entry in stages)
          if (stageIsInFlow(entry.stage, reviewFlow)) entry,
      ];

  /// Whether any stage the flow uses carries an override.
  bool get hasOverrideInFlow =>
      stagesInFlow.any((entry) => entry.adminOverride != null);
}
