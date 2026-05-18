import '../../../../core/api/json_parse.dart';

/// Permission bundle returned alongside a review. Drives every
/// affordance on the manager-rate screens — never gate UI on review
/// state alone, because state alone doesn't account for deadlines or
/// role-specific business rules.
class ReviewPermissions {
  /// True when this manager may submit ratings right now.
  final bool canRate;

  /// True when this manager may edit a previously-submitted rating
  /// (typically state=MANAGER_RATED_ALL and pre-deadline).
  final bool canEdit;

  /// Days remaining until the manager-review deadline. Negative
  /// values mean the deadline has passed. `null` means the cycle
  /// doesn't have a deadline set.
  final int? deadlineRemaining;

  const ReviewPermissions({
    required this.canRate,
    required this.canEdit,
    this.deadlineRemaining,
  });

  /// Convenience — purely visual nudge for the deadline-warning card.
  bool get isUrgent =>
      deadlineRemaining != null &&
      deadlineRemaining! >= 0 &&
      deadlineRemaining! <= 3;

  bool get isOverdue =>
      deadlineRemaining != null && deadlineRemaining! < 0;

  factory ReviewPermissions.fromJson(Map<String, dynamic> json) =>
      ReviewPermissions(
        canRate: JsonParse.parseBool(json['canRate']) ?? false,
        canEdit: JsonParse.parseBool(json['canEdit']) ?? false,
        deadlineRemaining: JsonParse.parseInt(json['deadlineRemaining']),
      );

  Map<String, dynamic> toJson() => {
        'canRate': canRate,
        'canEdit': canEdit,
        'deadlineRemaining': deadlineRemaining,
      };

  ReviewPermissions copyWith({
    bool? canRate,
    bool? canEdit,
    Object? deadlineRemaining = _sentinel,
  }) {
    return ReviewPermissions(
      canRate: canRate ?? this.canRate,
      canEdit: canEdit ?? this.canEdit,
      deadlineRemaining: identical(deadlineRemaining, _sentinel)
          ? this.deadlineRemaining
          : deadlineRemaining as int?,
    );
  }

  static const _sentinel = Object();
}
