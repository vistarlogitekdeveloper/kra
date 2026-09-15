import '../models/employee.dart';

/// Contract for employee CRUD. UI binds to this, not the Dio impl —
/// drop in a fake/mock by registering a different provider.
abstract class EmployeeRepository {
  /// Lists employees with server-side pagination + filters. Throws
  /// [ApiError] (unwrapped from the envelope) on any failure.
  Future<EmployeePage> list({
    int page = 1,
    int pageSize = 20,
    String? search,
    String? role,
    bool? isActive,
  });

  Future<Employee> getById(String id);

  Future<Employee> create({
    required String employeeCode,
    required String fullName,
    required String email,
    required String role,

    /// Full grant set when the server supports multi-role; omit otherwise.
    /// See `FeatureFlags.multiRole`.
    List<String>? roles,
    String? position,
    String? department,
    String? projectLocationId,
    String? managerId,
    String? grade,
    double? monthlyIncentiveAmount,
    DateTime? joinedDate,
    String? password,
    bool? forcePasswordReset,

    /// Which organisation the new employee belongs to.
    ///
    /// Omit for "the caller's own", which is what the server assumes and what
    /// every role other than SUPER_ADMIN gets regardless. Only a super admin
    /// may name a different tenant; anyone else doing so is refused rather
    /// than quietly redirected.
    ///
    /// Create only. There is no equivalent on [update] because moving an
    /// existing employee between organisations would strand their reviews,
    /// KRA assignments, manager and location, all of which carry their own
    /// organizationId — the server's update path deliberately does not accept
    /// the field.
    String? organizationId,
  });

  /// Moves an existing employee to another organization.
  ///
  /// A named operation rather than a field on [update], because it is not one
  /// write: it relocates their KRA assignments and drops the manager and
  /// location references that only make sense in the old tenant. The server
  /// also REFUSES (409) when the employee has reviews — `kra.reviews` has no
  /// organization column, so history belongs to whichever organization ran the
  /// review cycle and cannot follow them.
  ///
  /// Super admin only.
  Future<Employee> transfer(String id, String organizationId);

  /// Patches a subset of fields. Pass only the fields that changed —
  /// nulls in the map are sent verbatim (so they can clear a value).
  Future<Employee> update(String id, Map<String, dynamic> changes);

  /// Soft delete — flips `isActive` to false on the server.
  Future<void> deactivate(String id);

  /// Admin-only: set a new login password for an employee via
  /// POST /employees/:id/set-password. Returns the updated employee.
  Future<Employee> setPassword(
    String id, {
    required String password,
    bool forcePasswordReset = false,
  });
}
