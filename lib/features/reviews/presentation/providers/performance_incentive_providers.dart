import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/monthly_review.dart';
import '../../data/models/monthly_review_summary.dart';
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
  final months = quarterMonthsFor(anchor);
  // Watch all three months synchronously (before any await), then fetch them in
  // parallel via the shared, cached list provider.
  final futures = [
    for (final m in months) ref.watch(monthlyReviewListProvider(m).future),
  ];
  final lists = await Future.wait(futures);

  // Group every month's summary under its employee, keeping month order.
  final byEmp = <String, List<MonthlyReviewSummary?>>{};
  final names = <String, String>{};
  for (var i = 0; i < lists.length; i++) {
    for (final s in lists[i]) {
      final row = byEmp.putIfAbsent(
          s.employeeId, () => List<MonthlyReviewSummary?>.filled(3, null));
      row[i] = s;
      names[s.employeeId] = s.employeeName;
    }
  }

  // Ordered by employee name, numbered 1..N.
  final ids = byEmp.keys.toList()
    ..sort((a, b) =>
        (names[a] ?? '').toLowerCase().compareTo((names[b] ?? '').toLowerCase()));
  return [
    for (var i = 0; i < ids.length; i++)
      PerformanceIncentiveRow.build(
        srNo: i + 1,
        employeeId: ids[i],
        months: byEmp[ids[i]]!,
      ),
  ];
});
