import '../../../../core/api/json_parse.dart';
import '../../../employee/data/models/enums.dart';

/// One row in GET /manager/team. Carries the manager-facing summary
/// of a direct report's current-cycle review — enough to render the
/// list tile without an extra fetch.
class TeamMember {
  final String employeeId;
  final String employeeCode;
  final String fullName;
  final String? role;
  final String? projectLocation;

  /// Current-cycle review id — `null` if no assignment exists yet.
  final String? reviewId;
  final ReviewState reviewState;

  /// Manager total once the manager has rated. `selfTotal`/`finalTotal`
  /// optional alternates so the tile can show the most-current score
  /// without the consumer cherry-picking.
  final double? selfTotal;
  final double? managerTotal;
  final double? finalTotal;

  /// `true` if the cycle deadline has passed and the manager hasn't
  /// finalised. Drives the "Overdue" badge on the tile.
  final bool isOverdue;

  /// Last 3 months' weighted scores (oldest → newest). `null` entries
  /// render as grey dots in the trend strip widget.
  final List<double?> threeMonthTrend;

  const TeamMember({
    required this.employeeId,
    required this.employeeCode,
    required this.fullName,
    this.role,
    this.projectLocation,
    this.reviewId,
    required this.reviewState,
    this.selfTotal,
    this.managerTotal,
    this.finalTotal,
    this.isOverdue = false,
    this.threeMonthTrend = const [],
  });

  /// True if the manager is currently being asked to review this row —
  /// drives the tile's CTA-style badge.
  bool get isReadyForMyReview =>
      reviewState == ReviewState.employeeSubmittedAll && reviewId != null;

  factory TeamMember.fromJson(Map<String, dynamic> json) {
    final trendList = (json['threeMonthTrend'] as List?) ?? const [];
    // The live backend identifies the member with `id`/`name`, exposes
    // `projectLocation` as an object, and nests the review summary under
    // `currentReview.{id,state,selfTotal,…}`. Older spec/mock payloads
    // put all of it flat at the top level. Read the live shape first,
    // fall back to the flat one so both work.
    final review = JsonParse.parseMap(json['currentReview']);
    final loc = JsonParse.parseMap(json['projectLocation']);
    return TeamMember(
      employeeId: JsonParse.parseString(json['id']) ??
          JsonParse.parseString(json['employeeId']) ??
          '',
      employeeCode: JsonParse.parseString(json['employeeCode']) ?? '',
      fullName: JsonParse.parseString(json['name']) ??
          JsonParse.parseString(json['fullName']) ??
          '',
      role: JsonParse.parseString(json['role']),
      // `projectLocation` is an object on the wire — take its name, not
      // its stringified form. Flat string payloads still read directly.
      projectLocation: loc != null
          ? JsonParse.parseString(loc['name'])
          : JsonParse.parseString(json['projectLocation']),
      reviewId: JsonParse.parseString(review?['id']) ??
          JsonParse.parseString(json['reviewId']),
      reviewState: ReviewState.fromApi(
          JsonParse.parseString(review?['state']) ??
              JsonParse.parseString(json['reviewState']) ??
              'DRAFT'),
      selfTotal: JsonParse.parseDouble(review?['selfTotal']) ??
          JsonParse.parseDouble(json['selfTotal']),
      managerTotal: JsonParse.parseDouble(review?['managerTotal']) ??
          JsonParse.parseDouble(json['managerTotal']),
      finalTotal: JsonParse.parseDouble(review?['finalTotal']) ??
          JsonParse.parseDouble(json['finalTotal']),
      isOverdue: JsonParse.parseBool(review?['isOverdue']) ??
          JsonParse.parseBool(json['isOverdue']) ??
          false,
      threeMonthTrend: trendList
          .map((v) => JsonParse.parseDouble(v))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
        'employeeId': employeeId,
        'employeeCode': employeeCode,
        'fullName': fullName,
        'role': role,
        'projectLocation': projectLocation,
        'reviewId': reviewId,
        'reviewState': reviewState.toApiString(),
        'selfTotal': selfTotal,
        'managerTotal': managerTotal,
        'finalTotal': finalTotal,
        'isOverdue': isOverdue,
        'threeMonthTrend': threeMonthTrend,
      };

  TeamMember copyWith({
    String? employeeId,
    String? employeeCode,
    String? fullName,
    String? role,
    String? projectLocation,
    Object? reviewId = _sentinel,
    ReviewState? reviewState,
    Object? selfTotal = _sentinel,
    Object? managerTotal = _sentinel,
    Object? finalTotal = _sentinel,
    bool? isOverdue,
    List<double?>? threeMonthTrend,
  }) {
    return TeamMember(
      employeeId: employeeId ?? this.employeeId,
      employeeCode: employeeCode ?? this.employeeCode,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      projectLocation: projectLocation ?? this.projectLocation,
      reviewId: identical(reviewId, _sentinel)
          ? this.reviewId
          : reviewId as String?,
      reviewState: reviewState ?? this.reviewState,
      selfTotal: identical(selfTotal, _sentinel)
          ? this.selfTotal
          : selfTotal as double?,
      managerTotal: identical(managerTotal, _sentinel)
          ? this.managerTotal
          : managerTotal as double?,
      finalTotal: identical(finalTotal, _sentinel)
          ? this.finalTotal
          : finalTotal as double?,
      isOverdue: isOverdue ?? this.isOverdue,
      threeMonthTrend: threeMonthTrend ?? this.threeMonthTrend,
    );
  }

  static const _sentinel = Object();
}

/// Paginated wrapper for the team list, mirroring the other modules'
/// `*Page` types so the shared `PagedListView` controller pattern
/// just works.
class TeamMemberPage {
  final List<TeamMember> members;
  final int page;
  final int pageSize;
  final int total;

  /// Per-bucket counts so the filter chips can show a count badge
  /// without an extra round-trip. Keys mirror `ManagerTeamFilter`
  /// enum values' `toApiString()` output, plus `all`.
  final Map<String, int> filterCounts;

  const TeamMemberPage({
    required this.members,
    this.page = 1,
    this.pageSize = 20,
    this.total = 0,
    this.filterCounts = const {},
  });

  bool get hasMore => members.length + ((page - 1) * pageSize) < total;
}
