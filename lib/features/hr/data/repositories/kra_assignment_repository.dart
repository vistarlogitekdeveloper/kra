import '../models/kra_assignment.dart';
import '../models/kra_template_item.dart';

abstract class KraAssignmentRepository {
  Future<List<KraAssignment>> list({String? employeeId, String? cycleId});

  /// Single-employee assignment. Pass either [templateId] (snapshot from
  /// a template) or [items] (custom — built inline).
  Future<KraAssignment> create({
    required String employeeId,
    required String cycleId,
    String? templateId,
    List<KraTemplateItem>? items,
  });

  /// Patches an existing assignment. Will fail with `ASSIGNMENT_LOCKED`
  /// if [KraAssignment.isLocked] is true on the server.
  Future<KraAssignment> update(String id, Map<String, dynamic> changes);

  /// Bulk-assigns the same [templateId] to N employees in one round
  /// trip. Returns the freshly-created assignments.
  Future<List<KraAssignment>> bulkAssign({
    required List<String> employeeIds,
    required String cycleId,
    required String templateId,
  });
}
