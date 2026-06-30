/// Lifecycle of a review cycle. Status transitions are server-driven —
/// the client cannot move a cycle from CLOSED back to ACTIVE.
enum ReviewCycleStatus {
  draft,
  active,
  closed;

  static ReviewCycleStatus fromApi(String value) {
    final normalized = value.trim().toLowerCase();
    return ReviewCycleStatus.values.firstWhere(
      (e) => e.name == normalized,
      orElse: () => ReviewCycleStatus.draft,
    );
  }

  String toApiString() => name.toUpperCase();

  String get displayName {
    switch (this) {
      case ReviewCycleStatus.draft:
        return 'Draft';
      case ReviewCycleStatus.active:
        return 'Active';
      case ReviewCycleStatus.closed:
        return 'Closed';
    }
  }
}

/// One review cycle (typically a fiscal quarter). Carries the four
/// stage deadlines that the workflow gates progression on.
class ReviewCycle {
  final String id;
  final String name;
  final ReviewCycleStatus status;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime? selfRatingDeadline;
  final DateTime? managerReviewDeadline;
  final DateTime? opsScoringDeadline;
  final DateTime? financeScoringDeadline;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ReviewCycle({
    required this.id,
    required this.name,
    required this.status,
    required this.startDate,
    required this.endDate,
    this.selfRatingDeadline,
    this.managerReviewDeadline,
    this.opsScoringDeadline,
    this.financeScoringDeadline,
    this.createdAt,
    this.updatedAt,
  });

  /// Days from now to [endDate]. Negative if the cycle has already ended.
  /// Useful for the "12 days remaining" pill on the HR home screen.
  int get daysRemaining {
    final now = DateTime.now();
    return endDate.difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  factory ReviewCycle.fromJson(Map<String, dynamic> json) {
    return ReviewCycle(
      id: json['id'] as String,
      name: (json['name'] ?? '') as String,
      status: ReviewCycleStatus.fromApi((json['status'] ?? 'DRAFT') as String),
      startDate: _parseDate(json['startDate']) ?? DateTime.now(),
      endDate: _parseDate(json['endDate']) ?? DateTime.now(),
      selfRatingDeadline: _parseDate(json['selfRatingDeadline']),
      managerReviewDeadline: _parseDate(json['managerReviewDeadline']),
      opsScoringDeadline: _parseDate(json['opsScoringDeadline']),
      financeScoringDeadline: _parseDate(json['financeScoringDeadline']),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'status': status.toApiString(),
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'selfRatingDeadline': selfRatingDeadline?.toIso8601String(),
        'managerReviewDeadline': managerReviewDeadline?.toIso8601String(),
        'opsScoringDeadline': opsScoringDeadline?.toIso8601String(),
        'financeScoringDeadline': financeScoringDeadline?.toIso8601String(),
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  ReviewCycle copyWith({
    String? id,
    String? name,
    ReviewCycleStatus? status,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? selfRatingDeadline,
    DateTime? managerReviewDeadline,
    DateTime? opsScoringDeadline,
    DateTime? financeScoringDeadline,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ReviewCycle(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      selfRatingDeadline: selfRatingDeadline ?? this.selfRatingDeadline,
      managerReviewDeadline:
          managerReviewDeadline ?? this.managerReviewDeadline,
      opsScoringDeadline: opsScoringDeadline ?? this.opsScoringDeadline,
      financeScoringDeadline:
          financeScoringDeadline ?? this.financeScoringDeadline,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }
}
