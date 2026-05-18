import '../../../employee/data/models/enums.dart';
import '../models/enums.dart';
import '../models/fy_review_summary.dart';
import '../models/team_member.dart';
import '../models/team_member_profile.dart';
import 'manager_team_repository.dart';

/// In-memory fake of the team list. The five-person dataset mirrors
/// the names referenced in the spec's test checklist (Vikram, Sagar,
/// Neha, Pravin, Anita) so the UI exercises every review state in
/// development without round-tripping the backend.
class MockManagerTeamRepository implements ManagerTeamRepository {
  final Duration latency;

  const MockManagerTeamRepository({
    this.latency = const Duration(milliseconds: 300),
  });

  /// Master fixture — one row per direct report. Kept private so a
  /// test that mutates a member won't leak across tests; callers go
  /// through [listTeam] / [getMemberProfile] which return immutable
  /// copies.
  static final List<TeamMember> _fixtures = [
    const TeamMember(
      employeeId: 'emp-vikram',
      employeeCode: 'VLPL0210',
      fullName: 'Vikram Sinha',
      role: 'EMPLOYEE',
      projectLocation: 'Pune HQ',
      reviewId: 'rev-vikram-q1',
      reviewState: ReviewState.employeeSubmittedAll,
      selfTotal: 81.2,
      threeMonthTrend: [78.0, 80.0, 81.2],
    ),
    const TeamMember(
      employeeId: 'emp-sagar',
      employeeCode: 'VLPL0117',
      fullName: 'Sagar Patil',
      role: 'EMPLOYEE',
      projectLocation: 'Pune HQ',
      reviewId: 'rev-sagar-q1',
      reviewState: ReviewState.managerRatedAll,
      selfTotal: 91.0,
      managerTotal: 92.0,
      threeMonthTrend: [89.0, 90.5, 92.0],
    ),
    const TeamMember(
      employeeId: 'emp-neha',
      employeeCode: 'VLPL0089',
      fullName: 'Neha Kulkarni',
      role: 'EMPLOYEE',
      projectLocation: 'Mumbai',
      reviewId: 'rev-neha-q1',
      reviewState: ReviewState.finalized,
      selfTotal: 64.0,
      managerTotal: 63.5,
      finalTotal: 64.0,
      threeMonthTrend: [62.0, 63.5, 64.0],
    ),
    const TeamMember(
      employeeId: 'emp-pravin',
      employeeCode: 'VLPL0003',
      fullName: 'Pravin Joshi',
      role: 'EMPLOYEE',
      projectLocation: 'Pune HQ',
      reviewId: 'rev-pravin-q1',
      reviewState: ReviewState.inProgress,
      selfTotal: 44.0,
      threeMonthTrend: [null, 60.0, 44.0],
    ),
    const TeamMember(
      employeeId: 'emp-anita',
      employeeCode: 'VLPL0301',
      fullName: 'Anita Desai',
      role: 'EMPLOYEE',
      projectLocation: 'Mumbai',
      reviewId: 'rev-anita-q1',
      reviewState: ReviewState.draft,
      threeMonthTrend: [null, null, null],
    ),
  ];

  @override
  Future<TeamMemberPage> listTeam({
    String? cycleId,
    int page = 1,
    int pageSize = 20,
    String? search,
    ManagerTeamFilter filter = ManagerTeamFilter.all,
  }) async {
    await Future<void>.delayed(latency);
    final filtered = _fixtures.where((m) => _matches(m, filter, search)).toList();
    final start = (page - 1) * pageSize;
    final end = (start + pageSize).clamp(0, filtered.length);
    final slice =
        start >= filtered.length ? const <TeamMember>[] : filtered.sublist(start, end);
    return TeamMemberPage(
      members: slice,
      page: page,
      pageSize: pageSize,
      total: filtered.length,
      filterCounts: _filterCounts(),
    );
  }

  @override
  Future<TeamMemberProfile> getMemberProfile(String employeeId) async {
    await Future<void>.delayed(latency);
    final m = _fixtures.firstWhere(
      (x) => x.employeeId == employeeId,
      orElse: () => _fixtures.first,
    );
    return TeamMemberProfile(
      employeeId: m.employeeId,
      employeeCode: m.employeeCode,
      fullName: m.fullName,
      email: '${m.employeeCode.toLowerCase()}@vistar.test',
      phone: '+91 98XXX XX${m.employeeCode.substring(m.employeeCode.length - 3)}',
      role: m.role,
      department: 'Operations',
      grade: 'L2',
      position: 'Senior Operations Associate',
      projectLocation: m.projectLocation,
      joinedDate: DateTime(2023, 6, 1),
      monthlyIncentiveAmount: 7000,
      currentReviewId: m.reviewId,
      fyReviewSummary: FyReviewSummary(
        totalReviews: 4,
        finalizedCount: m.reviewState == ReviewState.finalized ||
                m.reviewState == ReviewState.acknowledged
            ? 4
            : 3,
        pendingCount: m.reviewState == ReviewState.finalized ||
                m.reviewState == ReviewState.acknowledged
            ? 0
            : 1,
        averageFinalScore:
            m.managerTotal ?? m.finalTotal ?? m.selfTotal ?? 70.0,
      ),
    );
  }

  // ───── Internals ─────

  bool _matches(
      TeamMember m, ManagerTeamFilter filter, String? search) {
    if (search != null && search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      if (!m.fullName.toLowerCase().contains(q) &&
          !m.employeeCode.toLowerCase().contains(q)) {
        return false;
      }
    }
    switch (filter) {
      case ManagerTeamFilter.all:
        return true;
      case ManagerTeamFilter.pendingMyReview:
        return m.reviewState == ReviewState.employeeSubmittedAll;
      case ManagerTeamFilter.completed:
        return m.reviewState == ReviewState.managerRatedAll ||
            m.reviewState == ReviewState.finalized ||
            m.reviewState == ReviewState.acknowledged;
      case ManagerTeamFilter.notSubmitted:
        return m.reviewState == ReviewState.draft ||
            m.reviewState == ReviewState.inProgress;
      case ManagerTeamFilter.overdue:
        return m.isOverdue;
    }
  }

  Map<String, int> _filterCounts() {
    int count(bool Function(TeamMember m) p) =>
        _fixtures.where(p).length;
    return {
      'ALL': _fixtures.length,
      'PENDING_MY_REVIEW':
          count((m) => m.reviewState == ReviewState.employeeSubmittedAll),
      'COMPLETED': count((m) =>
          m.reviewState == ReviewState.managerRatedAll ||
          m.reviewState == ReviewState.finalized ||
          m.reviewState == ReviewState.acknowledged),
      'NOT_SUBMITTED': count((m) =>
          m.reviewState == ReviewState.draft ||
          m.reviewState == ReviewState.inProgress),
      'OVERDUE': count((m) => m.isOverdue),
    };
  }
}
