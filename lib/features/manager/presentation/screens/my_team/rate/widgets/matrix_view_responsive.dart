import 'package:flutter/material.dart';

import '../../../../../data/models/manager_review_detail.dart';
import 'matrix_accordion_view.dart';
import 'matrix_table_view.dart';

/// Responsive switcher between the table and accordion matrix views.
///
/// Breakpoint at 720px wide — matches the tablet-portrait threshold
/// used elsewhere in the app (HR home `_StatsGrid` swaps grids at
/// the same width).
class MatrixViewResponsive extends StatelessWidget {
  final ManagerReviewDetail review;
  final void Function(String monthlyScoreId, double? rating)
      onScoreChanged;
  final void Function(String monthlyScoreId, String? remark)
      onRemarkChanged;

  static const double _tabletBreakpoint = 720;

  const MatrixViewResponsive({
    super.key,
    required this.review,
    required this.onScoreChanged,
    required this.onRemarkChanged,
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
          );
        }
        return MatrixAccordionView(
          review: review,
          onScoreChanged: onScoreChanged,
          onRemarkChanged: onRemarkChanged,
        );
      },
    );
  }
}
