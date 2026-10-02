import 'package:flutter/material.dart';

import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/widgets/shimmer_box.dart';

/// Shimmer placeholders sized like the content they stand in for, so nothing
/// jumps when the month or the history arrives.
class RatingAccessSkeleton extends StatelessWidget {
  final int count;
  final double itemHeight;

  const RatingAccessSkeleton({
    super.key,
    required this.count,
    required this.itemHeight,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppStrings.ratingAccessLoading,
      child: ExcludeSemantics(
        child: Column(
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              ShimmerBox(height: itemHeight, borderRadius: 16),
            ],
          ],
        ),
      ),
    );
  }
}
