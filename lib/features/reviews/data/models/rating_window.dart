import '../../../../core/api/json_parse.dart';
import 'review_stage.dart';

/// Why a stage's rating window for a month is what it is. See
/// docs/RATING_ACCESS.md §2.
enum RatingWindowSource {
  /// The stage's own deadline — the default rule.
  deadline,

  /// A super admin opened the stage past its deadline.
  opened,

  /// A super admin closed the stage.
  closed,

  /// The self-rating was sent back for rework and stays open to its owner.
  returned;

  /// Exact wire names. Anything else reads as [deadline]: whether the window is
  /// open is decided by its instants and by [RatingWindow.closed], which is
  /// carried separately, so an unrecognised source can never open a stage the
  /// server has closed.
  static RatingWindowSource fromApi(String? value) {
    switch ((value ?? '').trim().toUpperCase()) {
      case 'OPENED':
        return RatingWindowSource.opened;
      case 'CLOSED':
        return RatingWindowSource.closed;
      case 'RETURNED':
        return RatingWindowSource.returned;
      default:
        return RatingWindowSource.deadline;
    }
  }

  String toApiString() => name.toUpperCase();
}

/// When one rating stage of one review month accepts entries.
///
/// Resolved by the SERVER, which enforces the same answer on every write — this
/// copy exists so the sheet offers exactly the cells a save would be accepted
/// for, instead of discovering a refusal after the user has picked a value.
class RatingWindow {
  final RatingWindowSource source;

  /// Closed by a super admin: shut whatever the instants say.
  final bool closed;

  /// The month has ended. Nothing about a month opens before this.
  final DateTime opensAt;

  /// When entry closes. Null means no end — an open-ended reopen, or a
  /// self-rating returned for rework.
  final DateTime? closesAt;

  /// The stage's own deadline, for copy. Null when the server did not send it.
  final DateTime? deadlineAt;

  /// How far the server's clock was ahead of this device's when the window
  /// arrived (`serverNow` minus the device's clock). [isOpenAt] adds it to
  /// the device time it is given, so a phone whose clock is off neither
  /// offers a cell the server will refuse nor hides one it would accept.
  final Duration clockSkew;

  const RatingWindow({
    required this.source,
    required this.closed,
    required this.opensAt,
    this.closesAt,
    this.deadlineAt,
    this.clockSkew = Duration.zero,
  });

  /// A stage the server's `ratingAccess` block left out. Treated as CLOSED,
  /// never as "use the old rule": the server always sends all five stages, so
  /// a missing one means something is already wrong, and falling back to the
  /// looser client rules would offer cells the server refuses.
  static final RatingWindow missing = RatingWindow(
    source: RatingWindowSource.closed,
    closed: true,
    opensAt: DateTime.utc(1970),
  );

  /// Whether a rating may be entered at [now] (this device's clock). Both
  /// ends are inclusive, as on the server.
  bool isOpenAt(DateTime now) {
    final t = now.add(clockSkew);
    if (closed || t.isBefore(opensAt)) return false;
    final end = closesAt;
    return end == null || !t.isAfter(end);
  }

  /// Whether a super admin has reopened this stage and it is still open at
  /// [now] — the case worth telling the user about.
  bool isReopenedAt(DateTime now) =>
      source == RatingWindowSource.opened && isOpenAt(now);

  /// One window, or null when [raw] is not a map with a parsable `opensAt` —
  /// a window with no opening instant cannot be evaluated, and guessing one
  /// would be guessing whether people may rate.
  static RatingWindow? fromJson(
    Object? raw, {
    Duration clockSkew = Duration.zero,
  }) {
    final json = JsonParse.parseMap(raw);
    if (json == null) return null;
    final opensAt = JsonParse.parseDate(json['opensAt']);
    if (opensAt == null) return null;
    return RatingWindow(
      source: RatingWindowSource.fromApi(JsonParse.parseString(json['source'])),
      closed: JsonParse.parseBool(json['closed']) ?? false,
      opensAt: opensAt,
      closesAt: JsonParse.parseDate(json['closesAt']),
      deadlineAt: JsonParse.parseDate(json['deadlineAt']),
      clockSkew: clockSkew,
    );
  }

  /// [instant] as a wall-clock time in IST (UTC+05:30, no DST) — the business
  /// timezone every window is defined in. Format the result for display; a
  /// device elsewhere would otherwise show a 23:59 IST deadline as the next
  /// (or previous) calendar day.
  static DateTime toIst(DateTime instant) =>
      instant.toUtc().add(const Duration(hours: 5, minutes: 30));

  /// [serverNow] minus [receivedAt], or zero when the server sent no clock.
  static Duration skewOf(DateTime? serverNow, DateTime receivedAt) =>
      serverNow == null ? Duration.zero : serverNow.difference(receivedAt);

  /// The `ratingAccess` block of a review, keyed by EXACT stage wire name.
  ///
  /// Null ONLY when the block is absent or not a map — the backend predates
  /// rating access, and every gate keeps its previous rule. A block that is
  /// present but partly unusable stays present: the stages it lacks read as
  /// [missing] (closed) through `MonthlyReview.windowFor`. Never routed
  /// through `ReviewStage.fromApi`, which files an unknown name under
  /// SELF_RATING and would open or close the wrong stage. Unknown stages,
  /// non-rating stages and malformed entries are skipped.
  static Map<ReviewStage, RatingWindow>? parseMap(
    Object? raw, {
    Duration clockSkew = Duration.zero,
  }) {
    if (raw is! Map) return null;
    final byWireName = {
      for (final stage in ReviewStage.values) stage.toApiString(): stage,
    };
    final windows = <ReviewStage, RatingWindow>{};
    raw.forEach((key, value) {
      final stage = byWireName[key.toString().trim().toUpperCase()];
      if (stage == null || !stage.isRatingStage) return;
      final window = RatingWindow.fromJson(value, clockSkew: clockSkew);
      if (window != null) windows[stage] = window;
    });
    return windows;
  }

  Map<String, dynamic> toJson() => {
        'source': source.toApiString(),
        'closed': closed,
        'opensAt': opensAt.toUtc().toIso8601String(),
        'closesAt': closesAt?.toUtc().toIso8601String(),
        'deadlineAt': deadlineAt?.toUtc().toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      other is RatingWindow &&
      other.source == source &&
      other.closed == closed &&
      other.opensAt == opensAt &&
      other.closesAt == closesAt &&
      other.deadlineAt == deadlineAt &&
      other.clockSkew == clockSkew;

  @override
  int get hashCode =>
      Object.hash(source, closed, opensAt, closesAt, deadlineAt, clockSkew);
}
