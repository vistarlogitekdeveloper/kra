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

  const RatingWindow({
    required this.source,
    required this.closed,
    required this.opensAt,
    this.closesAt,
    this.deadlineAt,
  });

  /// Whether a rating may be entered at [now]. Both ends are inclusive, as on
  /// the server.
  bool isOpenAt(DateTime now) {
    if (closed || now.isBefore(opensAt)) return false;
    final end = closesAt;
    return end == null || !now.isAfter(end);
  }

  /// Whether a super admin has reopened this stage and it is still open at
  /// [now] — the case worth telling the user about.
  bool isReopenedAt(DateTime now) =>
      source == RatingWindowSource.opened && isOpenAt(now);

  /// One window, or null when [raw] is not a map with a parsable `opensAt` —
  /// a window with no opening instant cannot be evaluated, and guessing one
  /// would be guessing whether people may rate.
  static RatingWindow? fromJson(Object? raw) {
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
    );
  }

  /// The `ratingAccess` block of a review, keyed by EXACT stage wire name.
  ///
  /// Null when the block is absent or not a map — the backend predates rating
  /// access, and every gate keeps its previous rule. Never routed through
  /// `ReviewStage.fromApi`, which files an unknown name under SELF_RATING and
  /// would open or close the wrong stage. Unknown stages, non-rating stages and
  /// malformed entries are skipped; an empty result is treated as absent.
  static Map<ReviewStage, RatingWindow>? parseMap(Object? raw) {
    if (raw is! Map) return null;
    final byWireName = {
      for (final stage in ReviewStage.values) stage.toApiString(): stage,
    };
    final windows = <ReviewStage, RatingWindow>{};
    raw.forEach((key, value) {
      final stage = byWireName[key.toString().trim().toUpperCase()];
      if (stage == null || !stage.isRatingStage) return;
      final window = RatingWindow.fromJson(value);
      if (window != null) windows[stage] = window;
    });
    return windows.isEmpty ? null : windows;
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
      other.deadlineAt == deadlineAt;

  @override
  int get hashCode =>
      Object.hash(source, closed, opensAt, closesAt, deadlineAt);
}
