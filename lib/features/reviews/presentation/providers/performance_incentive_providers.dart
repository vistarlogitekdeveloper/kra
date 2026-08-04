import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/monthly_review.dart';
import '../../data/models/performance_incentive_row.dart';
import 'monthly_review_providers.dart';

/// The month the Performance Incentive Sheet is anchored on — any month resolves
/// to its fiscal quarter (see [quarterMonthsFor]). Defaults to the dashboards'
/// selected period, so switching month there and opening the report stay in
/// sync; the report's own quarter arrows update this.
final performanceIncentiveAnchorProvider =
    StateProvider<ReviewPeriod?>((ref) => null);

/// The quarterly Performance Incentive Sheet: one [PerformanceIncentiveRow] per
/// employee, aggregated from the three monthly review lists of the quarter that
/// contains [anchor]. Role-scoped by the underlying list provider (HR / Accounts
/// / Management see the whole org).
final performanceIncentiveSheetProvider = FutureProvider.autoDispose
    .family<List<PerformanceIncentiveRow>, ReviewPeriod>((ref, anchor) async {
  // Same fetch+group-by-employee as the Review Dashboard (shared helper), then
  // number the rows 1..N in name order.
  final groups = await quarterSummariesByEmployee(ref, anchor);
  return [
    for (var i = 0; i < groups.length; i++)
      PerformanceIncentiveRow.build(
        srNo: i + 1,
        employeeId: groups[i].employeeId,
        months: groups[i].months,
      ),
  ];
});
