import '../models/bulk_assign_result.dart';
import '../models/kra_assignment.dart';
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

  /// Bulk-assigns the same [templateId] to N employees in one round
  /// trip. The backend is idempotent — employees that already have this
  /// template land in [BulkAssignResult.skippedEmployeeIds] rather than
  /// producing an error.
  Future<BulkAssignResult> bulkAssign({
    required List<String> employeeIds,
    required String templateId,
  });
}
