import '../models/employee_profile.dart';

/// Contract for the logged-in user's own profile.
///
/// The endpoint returns a richer shape than the HR module's
/// `Employee` (`position`, `phone`, nested `manager` with role,
/// `projectLocation` with city/state/customer, `defaultTemplate`,
/// `monthlyIncentiveAmount`) — modelled here as [EmployeeProfile]
/// rather than re-using the HR class.
///
/// PATCH /employee/profile accepts only `phone` and `photoUrl` from
/// the employee themselves; everything else is HR-only and rejected
/// with 403 if attempted here.
abstract class MyProfileRepository {
  Future<EmployeeProfile> fetchMyProfile();

  /// Patches the editable subset of profile fields. Pass only the
  /// keys that changed — sending unchanged keys is harmless but
  /// wastes bandwidth. Allowed keys: `phone`, `photoUrl`.
  Future<EmployeeProfile> updateMyProfile(Map<String, dynamic> changes);
}
