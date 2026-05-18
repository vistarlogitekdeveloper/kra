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
    String? department,
    String? projectLocationId,
    String? managerId,
    String? grade,
    DateTime? joinedDate,
  });

  /// Patches a subset of fields. Pass only the fields that changed —
  /// nulls in the map are sent verbatim (so they can clear a value).
  Future<Employee> update(String id, Map<String, dynamic> changes);

  /// Soft delete — flips `isActive` to false on the server.
  Future<void> deactivate(String id);
}
