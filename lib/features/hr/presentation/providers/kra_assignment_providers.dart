import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/dio_client.dart';
import '../../data/models/bulk_assign_result.dart';
import '../../data/models/kra_assignment.dart';
import '../../data/models/kra_template_item.dart';
import '../../data/repositories/api_kra_assignment_repository.dart';
import '../../data/repositories/kra_assignment_repository.dart';

final kraAssignmentRepositoryProvider =
    Provider<KraAssignmentRepository>((ref) {
  return ApiKraAssignmentRepository(dio: ref.read(dioProvider));
});

class KraAssignmentFilter {
  final String? employeeId;
  const KraAssignmentFilter({this.employeeId});

  @override
  bool operator ==(Object other) =>
      other is KraAssignmentFilter && other.employeeId == employeeId;

  @override
  int get hashCode => employeeId.hashCode;
}

/// List of assignments, optionally filtered by employee. Use `family` so
/// each employee's list maintains its own cached list independently.
final kraAssignmentsProvider = FutureProvider.autoDispose
    .family<List<KraAssignment>, KraAssignmentFilter>((ref, filter) async {
  final repo = ref.watch(kraAssignmentRepositoryProvider);
  return repo.list(employeeId: filter.employeeId);
});

class KraAssignmentActions {
  final Ref ref;
  KraAssignmentActions(this.ref);

  KraAssignmentRepository get _repo =>
      ref.read(kraAssignmentRepositoryProvider);

  Future<KraAssignment> createFromTemplate({
    required String employeeId,
    required String templateId,
  }) async {
    final created = await _repo.create(
      employeeId: employeeId,
      templateId: templateId,
    );
    ref.invalidate(kraAssignmentsProvider);
    return created;
  }

  Future<KraAssignment> createCustom({
    required String employeeId,
    required List<KraTemplateItem> items,
  }) async {
    final created = await _repo.create(
      employeeId: employeeId,
      items: items,
    );
    ref.invalidate(kraAssignmentsProvider);
    return created;
  }

  Future<BulkAssignResult> bulkAssign({
    required List<String> employeeIds,
    required String templateId,
  }) async {
    final result = await _repo.bulkAssign(
      employeeIds: employeeIds,
      templateId: templateId,
    );
    ref.invalidate(kraAssignmentsProvider);
    return result;
  }

  Future<KraAssignment> update(String id, Map<String, dynamic> changes) async {
    final updated = await _repo.update(id, changes);
    ref.invalidate(kraAssignmentsProvider);
    return updated;
  }
}

final kraAssignmentActionsProvider =
    Provider<KraAssignmentActions>((ref) => KraAssignmentActions(ref));
