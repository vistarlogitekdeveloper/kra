import '../models/employee.dart';

/// Contract for the Bulk Setup wizard's backend calls.
///
/// Three-phase flow:
///   1. Find eligible employees (who don't have an assignment for the
///      selected cycle yet)
///   2. Preview the assignment that would be created (dry-run)
///   3. Execute (create reviews + assignments in one batch POST)
///
/// The endpoint at `/kra-assignments/bulk` handles the execute step;
/// the eligibility check reuses the `/employees` endpoint with a
/// filter. This interface hides those implementation details from the
/// UI layer.
abstract class BulkSetupRepository {
  /// Returns employees that are eligible for bulk assignment in the
  /// given [cycleId] — i.e. those without an existing KRA assignment
  /// for this cycle. Optional [locationId] and [role] narrow the set.
  Future<List<Employee>> fetchEligibleEmployees({
    required String cycleId,
    String? locationId,
    String? role,
  });

  /// Creates KRA reviews + assignments for [employeeIds] under
  /// [cycleId] using [templateId]. Returns the number of created
  /// records on success.
  ///
  /// The backend does this in a transaction — either all succeed or
  /// none do; partial failures are not possible.
  Future<int> executeBulkSetup({
    required String cycleId,
    required String templateId,
    required List<String> employeeIds,
  });
}
