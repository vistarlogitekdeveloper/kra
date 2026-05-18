import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../providers/manager_rate_providers.dart';
import 'manager_comment_field.dart';
import 'matrix_view_responsive.dart';

/// Top-level matrix container used by the rate screen. Wires the
/// notifier through to the responsive view + comment field so the
/// screen layer stays compositional.
///
/// `readOnly: true` skips wiring the editor callbacks — used when
/// the rate screen wants to preview the matrix in review/edit modes
/// where the user has already left the cells.
class QuarterlyReviewMatrix extends ConsumerWidget {
  const QuarterlyReviewMatrix({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(managerRateProvider);
    final review = state.review;
    if (review == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MatrixViewResponsive(
          review: review,
          onScoreChanged: (id, rating) => ref
              .read(managerRateProvider.notifier)
              .setCellRating(id, rating),
          onRemarkChanged: (id, remark) => ref
              .read(managerRateProvider.notifier)
              .setCellRemark(id, remark),
        ),
        ManagerCommentField(
          value: state.managerComment,
          onChanged: (v) => ref
              .read(managerRateProvider.notifier)
              .setManagerComment(v),
        ),
      ],
    );
  }
}
