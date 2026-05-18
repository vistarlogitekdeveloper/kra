import '../models/bonus_slab.dart';

abstract class BonusSlabRepository {
  Future<List<BonusSlab>> listForCycle(String cycleId);

  Future<BonusSlab> create({
    required String cycleId,
    required String grade,
    required double monthlyEligibleAmount,
    required double quarterlyEligibleAmount,
  });

  Future<BonusSlab> update(String id, Map<String, dynamic> changes);
}
