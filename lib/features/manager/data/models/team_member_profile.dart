import '../../../../core/api/json_parse.dart';
import 'fy_review_summary.dart';

/// Full payload for GET /manager/team/:employeeId. Profile tab on
/// the team-member screen renders directly from this; the Current
/// Review tab reuses [ManagerReviewDetail].
class TeamMemberProfile {
  final String employeeId;
  final String employeeCode;
  final String fullName;
  final String email;
  final String? phone;
  final String? role;
  final String? department;
  final String? grade;
  final String? position;
  final String? projectLocation;
  final DateTime? joinedDate;
  final double? monthlyIncentiveAmount;
  final FyReviewSummary? fyReviewSummary;

  /// Current-cycle review id (if any) — drives the "Current Review"
  /// tab. `null` means no assignment for the active cycle.
  final String? currentReviewId;

  const TeamMemberProfile({
    required this.employeeId,
    required this.employeeCode,
    required this.fullName,
    required this.email,
    this.phone,
    this.role,
    this.department,
    this.grade,
    this.position,
    this.projectLocation,
    this.joinedDate,
    this.monthlyIncentiveAmount,
    this.fyReviewSummary,
    this.currentReviewId,
  });

  factory TeamMemberProfile.fromJson(Map<String, dynamic> json) =>
      TeamMemberProfile(
        employeeId: JsonParse.parseString(json['employeeId']) ?? '',
        employeeCode:
            JsonParse.parseString(json['employeeCode']) ?? '',
        fullName: JsonParse.parseString(json['fullName']) ?? '',
        email: JsonParse.parseString(json['email']) ?? '',
        phone: JsonParse.parseString(json['phone']),
        role: JsonParse.parseString(json['role']),
        department: JsonParse.parseString(json['department']),
        grade: JsonParse.parseString(json['grade']),
        position: JsonParse.parseString(json['position']),
        projectLocation:
            JsonParse.parseString(json['projectLocation']),
        joinedDate: JsonParse.parseDate(json['joinedDate']),
        monthlyIncentiveAmount:
            JsonParse.parseDouble(json['monthlyIncentiveAmount']),
        fyReviewSummary:
            JsonParse.parseMap(json['fyReviewSummary']) == null
                ? null
                : FyReviewSummary.fromJson(
                    JsonParse.parseMap(json['fyReviewSummary'])!),
        currentReviewId:
            JsonParse.parseString(json['currentReviewId']),
      );

  Map<String, dynamic> toJson() => {
        'employeeId': employeeId,
        'employeeCode': employeeCode,
        'fullName': fullName,
        'email': email,
        'phone': phone,
        'role': role,
        'department': department,
        'grade': grade,
        'position': position,
        'projectLocation': projectLocation,
        'joinedDate': joinedDate?.toIso8601String(),
        'monthlyIncentiveAmount': monthlyIncentiveAmount,
        'fyReviewSummary': fyReviewSummary?.toJson(),
        'currentReviewId': currentReviewId,
      };
}
