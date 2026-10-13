import '../models/bulk_assign_result.dart';
import '../models/kra_assignment.dart';
import '../models/kra_unassign_result.dart';
import '../models/kra_template_item.dart';

abstract class KraAssignmentRepository {
  Future<List<KraAssignment>> list({String? employeeId});

  /// Single-employee assignment. Pass either [templateId] (snapshot from
  /// a template) or [items] (custom — built inline).
  Future<KraAssignment> create({
    required String employeeId,
    String? templateId,
    List<KraTemplateItem>? items,
  });

  /// Patches an existing assignment. Will fail with `ASSIGNMENT_LOCKED`
  /// if [KraAssignment.isLocked] is true on the server.
  Future<KraAssignment> update(String id, Map<String, dynamic> changes);

  /// Unassigns ONE KRA assignment.
  ///
  /// A DRAFT review generated from it goes too; one carrying scores is KEPT,
  /// which the result reports so the caller can say so.
  Future<KraUnassignResult> unassign(String id);

  /// Clears EVERY KRA assignment for an employee, or just one cycle's.
  ///
  /// A count of 0 means they had none — a success, not a failure.
  Future<KraUnassignAllResult> unassignAllForEmployee(
    String employeeId, {
    String? cycleId,
  });

  /// Bulk-assigns the same [templateId] to N employees in one round
  /// trip. The backend is idempotent — employees that already have this
  /// template land in [BulkAssignResult.skippedEmployeeIds] rather than
  /// producing an error.
  Future<BulkAssignResult> bulkAssign({
    required List<String> employeeIds,
    required String templateId,
  });
}
