import '../models/bulk_operation_result.dart';
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
    double? monthlyIncentiveAmount,
    DateTime? joinedDate,
  });

  /// Patches a subset of fields. Pass only the fields that changed —
  /// nulls in the map are sent verbatim (so they can clear a value).
  Future<Employee> update(String id, Map<String, dynamic> changes);

  /// Soft delete — flips `isActive` to false on the server.
  Future<void> deactivate(String id);

  /// Admin-only: fan out `deactivate` over every currently-active
  /// employee. The backend has no bulk endpoint, so we orchestrate
  /// client-side and report success / failure counts.
  Future<BulkOperationResult> deactivateAll();

  /// Admin-only: zero out the per-employee `monthlyIncentiveAmount`
  /// field on every active employee. This is what the admin-tools
  /// surface calls "delete all performance incentives" — the backend
  /// has no `DELETE /bonus-slabs` route, so clearing the per-employee
  /// amount is the only deletion it actually supports.
  Future<BulkOperationResult> clearAllIncentiveAmounts();
}
