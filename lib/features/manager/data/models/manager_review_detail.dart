import '../../../../core/api/json_parse.dart';
import '../../../employee/data/models/enums.dart';
import 'previous_review.dart';
import 'review_permissions.dart';
import 'review_row.dart';
import 'review_totals.dart';

/// Full payload for GET /manager/reviews/:reviewId.
///
/// Everything the manager-rate matrix screen needs to render is here:
/// the employee + cycle headers, the editable matrix, the totals
/// snapshot, the previous-quarters strip, the permission bundle, and
/// the manager's existing top-level comment.
class ManagerReviewDetail {
  final String id;
  final ReviewState state;
  final bool isLocked;

  final ManagerReviewEmployee employee;
  final ManagerReviewCycle cycle;

  final List<ReviewRow> rows;
  final ReviewTotals totals;
  final List<PreviousReview> previousReviews;
  final String? managerComment;

  final ReviewPermissions permissions;

  const ManagerReviewDetail({
    required this.id,
    required this.state,
    this.isLocked = false,
    required this.employee,
    required this.cycle,
    this.rows = const [],
    required this.totals,
    this.previousReviews = const [],
    this.managerComment,
    required this.permissions,
  });

  factory ManagerReviewDetail.fromJson(Map<String, dynamic> json) {
    final rowsJson = JsonParse.parseMapList(json['rows']);
    final rows = rowsJson.map(ReviewRow.fromJson).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return ManagerReviewDetail(
      id: JsonParse.parseString(json['id']) ?? '',
      state: ReviewState.fromApi(
          JsonParse.parseString(json['state']) ?? 'DRAFT'),
      isLocked: JsonParse.parseBool(json['isLocked']) ?? false,
      employee: ManagerReviewEmployee.fromJson(
          JsonParse.parseMap(json['employee']) ?? const {}),
      // Live backend names the cycle block `reviewCycle`; older
      // spec/mock payloads use `cycle`. Accept either.
      cycle: ManagerReviewCycle.fromJson(JsonParse.parseMap(json['reviewCycle']) ??
          JsonParse.parseMap(json['cycle']) ??
          const {}),
      rows: rows,
      totals: ReviewTotals.fromJson(
          JsonParse.parseMap(json['totals']) ?? const {}),
      previousReviews: JsonParse.parseMapList(json['previousReviews'])
          .map(PreviousReview.fromJson)
          .toList(),
      managerComment: JsonParse.parseString(json['managerComment']),
      permissions: ReviewPermissions.fromJson(
          JsonParse.parseMap(json['permissions']) ?? const {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'state': state.toApiString(),
        'isLocked': isLocked,
        'employee': employee.toJson(),
        'cycle': cycle.toJson(),
        'rows': rows.map((r) => r.toJson()).toList(),
        'totals': totals.toJson(),
        'previousReviews':
            previousReviews.map((p) => p.toJson()).toList(),
        'managerComment': managerComment,
        'permissions': permissions.toJson(),
      };

  ManagerReviewDetail copyWith({
    String? id,
    ReviewState? state,
    bool? isLocked,
    ManagerReviewEmployee? employee,
    ManagerReviewCycle? cycle,
    List<ReviewRow>? rows,
    ReviewTotals? totals,
    List<PreviousReview>? previousReviews,
    Object? managerComment = _sentinel,
    ReviewPermissions? permissions,
  }) {
    return ManagerReviewDetail(
      id: id ?? this.id,
      state: state ?? this.state,
      isLocked: isLocked ?? this.isLocked,
      employee: employee ?? this.employee,
      cycle: cycle ?? this.cycle,
      rows: rows ?? this.rows,
      totals: totals ?? this.totals,
      previousReviews: previousReviews ?? this.previousReviews,
      managerComment: identical(managerComment, _sentinel)
          ? this.managerComment
          : managerComment as String?,
      permissions: permissions ?? this.permissions,
    );
  }

  /// Replace one row in the matrix without rebuilding the rest.
  /// Used by the manager-rate notifier after every cell edit.
  ManagerReviewDetail withUpdatedRow(ReviewRow updated) {
    final out = [
      for (final r in rows)
        r.assignmentItemId == updated.assignmentItemId ? updated : r,
    ];
    return copyWith(rows: out);
  }

  static const _sentinel = Object();
}

/// Employee header card on the review detail / rate screens.
class ManagerReviewEmployee {
  final String id;
  final String name;
  final String employeeCode;
  final String? role;
  final String? projectLocation;

  const ManagerReviewEmployee({
    required this.id,
    required this.name,
    required this.employeeCode,
    this.role,
    this.projectLocation,
  });

  factory ManagerReviewEmployee.fromJson(Map<String, dynamic> json) =>
      ManagerReviewEmployee(
        id: JsonParse.parseString(json['id']) ?? '',
        name: JsonParse.parseString(json['name']) ?? '',
        employeeCode: JsonParse.parseString(json['employeeCode']) ?? '',
        role: JsonParse.parseString(json['role']),
        projectLocation: JsonParse.parseString(json['projectLocation']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'employeeCode': employeeCode,
        'role': role,
        'projectLocation': projectLocation,
      };
}

/// Cycle header card on the review detail / rate screens.
class ManagerReviewCycle {
  final String id;
  final String name;
  final String? fyLabel;
  final int? quarterNum;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? managerReviewDeadline;
  final List<ManagerReviewMonth> months;

  const ManagerReviewCycle({
    required this.id,
    required this.name,
    this.fyLabel,
    this.quarterNum,
    this.startDate,
    this.endDate,
    this.managerReviewDeadline,
    this.months = const [],
  });

  factory ManagerReviewCycle.fromJson(Map<String, dynamic> json) =>
      ManagerReviewCycle(
        id: JsonParse.parseString(json['id']) ?? '',
        name: JsonParse.parseString(json['name']) ?? '',
        fyLabel: JsonParse.parseString(json['fyLabel']),
        quarterNum: JsonParse.parseInt(json['quarterNum']),
        startDate: JsonParse.parseDate(json['startDate']),
        endDate: JsonParse.parseDate(json['endDate']),
        managerReviewDeadline:
            JsonParse.parseDate(json['managerReviewDeadline']),
        months: JsonParse.parseMapList(json['months'])
            .map(ManagerReviewMonth.fromJson)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'fyLabel': fyLabel,
        'quarterNum': quarterNum,
        'startDate': startDate?.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
        'managerReviewDeadline':
            managerReviewDeadline?.toIso8601String(),
        'months': months.map((m) => m.toJson()).toList(),
      };
}

class ManagerReviewMonth {
  final String id;
  final String monthLabel;
  final DateTime? monthDate;
  final ReviewMonthStatus status;

  const ManagerReviewMonth({
    required this.id,
    required this.monthLabel,
    this.monthDate,
    required this.status,
  });

  factory ManagerReviewMonth.fromJson(Map<String, dynamic> json) =>
      ManagerReviewMonth(
        id: JsonParse.parseString(json['id']) ?? '',
        monthLabel: JsonParse.parseString(json['monthLabel']) ?? '',
        monthDate: JsonParse.parseDate(json['monthDate']),
        status: ReviewMonthStatus.fromApi(
            JsonParse.parseString(json['status']) ?? 'OPEN'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'monthLabel': monthLabel,
        'monthDate': monthDate?.toIso8601String(),
        'status': status.toApiString(),
      };
}
