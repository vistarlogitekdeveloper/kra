import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/dio_client.dart';
import '../../data/models/performance_incentive.dart';
import '../../data/repositories/api_performance_incentive_repository.dart';
import '../../data/repositories/performance_incentive_repository.dart';

final performanceIncentiveRepositoryProvider =
    Provider<PerformanceIncentiveRepository>((ref) {
  return ApiPerformanceIncentiveRepository(dio: ref.read(dioProvider));
});

/// All performance incentives for a given cycle. Family keyed on cycleId
/// so each cycle's incentives are cached independently.
final performanceIncentivesForCycleProvider = FutureProvider.autoDispose
    .family<List<PerformanceIncentive>, String>((ref, cycleId) async {
  final repo = ref.watch(performanceIncentiveRepositoryProvider);
  return repo.listForCycle(cycleId);
});

class PerformanceIncentiveActions {
  final Ref ref;
  PerformanceIncentiveActions(this.ref);

  PerformanceIncentiveRepository get _repo =>
      ref.read(performanceIncentiveRepositoryProvider);

  Future<PerformanceIncentive> create({
    required String cycleId,
    required String grade,
    required double monthlyEligibleAmount,
    required double quarterlyEligibleAmount,
  }) async {
    final created = await _repo.create(
      cycleId: cycleId,
      grade: grade,
      monthlyEligibleAmount: monthlyEligibleAmount,
      quarterlyEligibleAmount: quarterlyEligibleAmount,
    );
    ref.invalidate(performanceIncentivesForCycleProvider(cycleId));
    return created;
  }

  Future<PerformanceIncentive> update(
      String id, Map<String, dynamic> changes) async {
    final updated = await _repo.update(id, changes);
    // The incentive carries its cycleId so we can invalidate precisely.
    ref.invalidate(performanceIncentivesForCycleProvider(updated.cycleId));
    return updated;
  }
}

final performanceIncentiveActionsProvider =
    Provider<PerformanceIncentiveActions>(
        (ref) => PerformanceIncentiveActions(ref));
