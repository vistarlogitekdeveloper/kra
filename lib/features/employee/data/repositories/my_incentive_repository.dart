import '../models/incentive_summary.dart';

/// Contract for the quarterly incentive snapshot.
///
/// `cycleId` is **required** by the backend (no implicit-active-cycle
/// fallback) — pass the active cycle id from the dashboard payload
/// or from a cycle filter on the history tab.
abstract class MyIncentiveRepository {
  Future<IncentiveSummary> fetchIncentiveSummary({required String cycleId});
}
