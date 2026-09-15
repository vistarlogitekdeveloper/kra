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

/// Whether [month] is the one currently OPEN for rating as of [now].
///
/// Lives here rather than in either view because both need it and neither
/// owns it. Defers to [ReviewPeriod.isOpenForRatingOn] so the matrix cannot
/// drift from the quarterly sheet or the employee home card.
///
/// Was `monthEnded`, which asked only whether the month had FINISHED and so
/// left every earlier month writable: a manager rating August could still
/// rewrite July. The submit rules still ask "has ended" — see
/// [MonthlyScore.isRatableOn] — because those are a different question.
///
/// A month with no date is treated as CLOSED: the matrix would otherwise
/// offer a writable cell for a month it cannot identify, which is the exact
/// failure this rule exists to stop.
bool monthOpenForRating(ManagerReviewMonth month, DateTime now) {
  final d = month.monthDate;
  if (d == null) return false;
  return ReviewPeriod.fromDate(d).isOpenForRatingOn(now);
}

/// Whether [month] has not finished yet, as opposed to having finished and
/// had its window close afterwards.
///
/// Both are read-only, so this decides only the WORDING. It goes through
/// [ReviewPeriod.isRatableOn] — the "has ended" question — which is exactly
/// what that predicate is still for now that the edit gate has its own.
bool monthIsFuture(ManagerReviewMonth month, DateTime now) {
  final d = month.monthDate;
  if (d == null) return false;
  return !ReviewPeriod.fromDate(d).isRatableOn(now);
}
