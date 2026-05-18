import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/dio_client.dart';
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
  final String? cycleId;
  const KraAssignmentFilter({this.employeeId, this.cycleId});

  @override
  bool operator ==(Object other) =>
      other is KraAssignmentFilter &&
      other.employeeId == employeeId &&
      other.cycleId == cycleId;

  @override
  int get hashCode => Object.hash(employeeId, cycleId);
}

/// List of assignments. Pass either employeeId or cycleId via the filter
/// — the API ANDs them. Use `family` so each (employeeId, cycleId) pair
/// maintains its own cached list independently.
final kraAssignmentsProvider = FutureProvider.autoDispose
    .family<List<KraAssignment>, KraAssignmentFilter>((ref, filter) async {
  final repo = ref.watch(kraAssignmentRepositoryProvider);
  return repo.list(employeeId: filter.employeeId, cycleId: filter.cycleId);
});

class KraAssignmentActions {
  final Ref ref;
  KraAssignmentActions(this.ref);

  KraAssignmentRepository get _repo =>
      ref.read(kraAssignmentRepositoryProvider);

  Future<KraAssignment> createFromTemplate({
    required String employeeId,
    required String cycleId,
    required String templateId,
  }) async {
    final created = await _repo.create(
      employeeId: employeeId,
      cycleId: cycleId,
      templateId: templateId,
    );
    ref.invalidate(kraAssignmentsProvider);
    return created;
  }

  Future<KraAssignment> createCustom({
    required String employeeId,
    required String cycleId,
    required List<KraTemplateItem> items,
  }) async {
    final created = await _repo.create(
      employeeId: employeeId,
      cycleId: cycleId,
      items: items,
    );
    ref.invalidate(kraAssignmentsProvider);
    return created;
  }

  Future<List<KraAssignment>> bulkAssign({
    required List<String> employeeIds,
    required String cycleId,
    required String templateId,
  }) async {
    final created = await _repo.bulkAssign(
      employeeIds: employeeIds,
      cycleId: cycleId,
      templateId: templateId,
    );
    ref.invalidate(kraAssignmentsProvider);
    return created;
  }

  Future<KraAssignment> update(String id, Map<String, dynamic> changes) async {
    final updated = await _repo.update(id, changes);
    ref.invalidate(kraAssignmentsProvider);
    return updated;
  }
}

final kraAssignmentActionsProvider =
    Provider<KraAssignmentActions>((ref) => KraAssignmentActions(ref));
