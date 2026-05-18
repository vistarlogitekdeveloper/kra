import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/dio_client.dart';
import '../../data/models/bonus_slab.dart';
import '../../data/repositories/api_bonus_slab_repository.dart';
import '../../data/repositories/bonus_slab_repository.dart';

final bonusSlabRepositoryProvider = Provider<BonusSlabRepository>((ref) {
  return ApiBonusSlabRepository(dio: ref.read(dioProvider));
});

/// All bonus slabs for a given cycle. Family keyed on cycleId so each
/// cycle's slabs are cached independently.
final bonusSlabsForCycleProvider = FutureProvider.autoDispose
    .family<List<BonusSlab>, String>((ref, cycleId) async {
  final repo = ref.watch(bonusSlabRepositoryProvider);
  return repo.listForCycle(cycleId);
});

class BonusSlabActions {
  final Ref ref;
  BonusSlabActions(this.ref);

  BonusSlabRepository get _repo => ref.read(bonusSlabRepositoryProvider);

  Future<BonusSlab> create({
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
    ref.invalidate(bonusSlabsForCycleProvider(cycleId));
    return created;
  }

  Future<BonusSlab> update(String id, Map<String, dynamic> changes) async {
    final updated = await _repo.update(id, changes);
    // The slab carries its cycleId so we can invalidate precisely.
    ref.invalidate(bonusSlabsForCycleProvider(updated.cycleId));
    return updated;
  }
}

final bonusSlabActionsProvider =
    Provider<BonusSlabActions>((ref) => BonusSlabActions(ref));
