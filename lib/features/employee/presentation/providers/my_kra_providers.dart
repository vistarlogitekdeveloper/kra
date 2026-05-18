import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/dio_client.dart';
import '../../data/models/my_kra_assignment.dart';
import '../../data/repositories/api_my_kra_repository.dart';
import '../../data/repositories/my_kra_repository.dart';

final myKraRepositoryProvider = Provider<MyKraRepository>((ref) {
  return ApiMyKraRepository(dio: ref.read(dioProvider));
});

/// Lists my KRA assignments, optionally scoped to a single cycle.
/// `family` keyed on `cycleId` (nullable string) so different cycle
/// drill-downs cache independently. autoDispose to free memory after
/// the user leaves the home / self-rate flow.
final myKraAssignmentsProvider = FutureProvider.autoDispose
    .family<List<MyKraAssignment>, String?>((ref, cycleId) async {
  final repo = ref.watch(myKraRepositoryProvider);
  return repo.listMyAssignments(cycleId: cycleId);
});

/// Convenience accessor — the assignment for the active cycle, which
/// is what the self-rate form needs. Most users have exactly one
/// assignment per cycle (the one matching their role's template).
final myActiveAssignmentProvider = FutureProvider.autoDispose
    .family<MyKraAssignment?, String?>((ref, cycleId) async {
  final list =
      await ref.watch(myKraAssignmentsProvider(cycleId).future);
  if (list.isEmpty) return null;
  // Most realistic case is one assignment per (employee, cycle); if
  // the backend ever returns multiple, the first one (sorted by the
  // server) is the canonical choice.
  return list.first;
});
