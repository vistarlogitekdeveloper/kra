import '../models/enums.dart';
import '../models/team_member.dart';
import '../models/team_member_profile.dart';

/// Contract for the manager's team list + per-member profile lookups.
abstract class ManagerTeamRepository {
  /// Paginated list of direct reports for the active cycle. All
  /// filter params are optional — the bare call returns "all reports
  /// for the active cycle, page 1".
  Future<TeamMemberPage> listTeam({
    String? cycleId,
    int page = 1,
    int pageSize = 20,
    String? search,
    ManagerTeamFilter filter = ManagerTeamFilter.all,
  });

  /// Single team-member profile + FY summary.
  Future<TeamMemberProfile> getMemberProfile(String employeeId);
}
