import 'package:flutter/material.dart';

import '../../../../../data/models/manager_review_detail.dart';
import 'matrix_accordion_view.dart';
import 'matrix_table_view.dart';
import '../../../../../../reviews/data/models/monthly_review.dart';

/// Responsive switcher between the table and accordion matrix views.
///
/// Breakpoint at 720px wide — matches the tablet-portrait threshold
/// used elsewhere in the app (HR home `_StatsGrid` swaps grids at
/// the same width).
class MatrixViewResponsive extends StatelessWidget {
  final ManagerReviewDetail review;
  final void Function(String monthlyScoreId, double? rating) onScoreChanged;
  final void Function(String monthlyScoreId, String? remark) onRemarkChanged;

  /// Clock for the month-ratability rule, resolved once by the caller so both
  /// views and every cell agree on what "today" is.
  final DateTime now;

  static const double _tabletBreakpoint = 720;

  const MatrixViewResponsive({
    super.key,
    required this.review,
    required this.onScoreChanged,
    required this.onRemarkChanged,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _tabletBreakpoint;
        if (wide) {
          return MatrixTableView(
            review: review,
            onScoreChanged: onScoreChanged,
            onRemarkChanged: onRemarkChanged,
            now: now,
          );
        }
        return MatrixAccordionView(
          review: review,
          onScoreChanged: onScoreChanged,
          onRemarkChanged: onRemarkChanged,
          now: now,
        );
      },
    );
  }
}

/// Whether [month] has finished as of [now], and so may be rated.
///
/// Lives here rather than in either view because both need it and neither
/// owns it. Defers to [ReviewPeriod.isRatableOn] so the matrix cannot drift
/// from the quarterly sheet or the employee home card.
///
/// A month with no date is treated as NOT ended: the matrix would otherwise
/// offer a writable cell for a month it cannot identify, which is the exact
/// failure this rule exists to stop.
bool monthEnded(ManagerReviewMonth month, DateTime now) {
  final d = month.monthDate;
  if (d == null) return false;
  return ReviewPeriod.fromDate(d).isRatableOn(now);
}
