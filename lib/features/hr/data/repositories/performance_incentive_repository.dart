import '../models/performance_incentive.dart';

abstract class PerformanceIncentiveRepository {
  Future<List<PerformanceIncentive>> listForCycle(String cycleId);

  Future<PerformanceIncentive> create({
    required String cycleId,
    required String grade,
    required double monthlyEligibleAmount,
    required double quarterlyEligibleAmount,
  });

  Future<PerformanceIncentive> update(String id, Map<String, dynamic> changes);
}
