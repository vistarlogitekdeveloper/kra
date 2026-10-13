import 'package:flutter/material.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../reviews/data/models/monthly_review.dart';

/// One chip per month, newest first. Scrolls sideways rather than wrapping, so
/// six months never push the stage cards down a phone screen, and sizes to its
/// labels so a large text scale grows the row instead of clipping it.
class RatingAccessMonthChips extends StatelessWidget {
  final List<ReviewPeriod> periods;
  final ReviewPeriod selected;

  /// False while a write is in flight: switching month mid-write would land
  /// its confirmation on a different month.
  final bool enabled;
  final ValueChanged<ReviewPeriod> onSelect;

  const RatingAccessMonthChips({
    super.key,
    required this.periods,
    required this.selected,
    required this.enabled,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final period in periods) ...[
            if (period != periods.first) const SizedBox(width: 8),
            ChoiceChip(
              label: Text(period.label),
              selected: period == selected,
              showCheckmark: false,
              // Padded on every platform: desktop themes shrink-wrap chips
              // below the 48 px touch target.
              materialTapTargetSize: MaterialTapTargetSize.padded,
              selectedColor: AppColors.primaryPurple,
              backgroundColor: AppColors.primaryPurple.withValues(alpha: 0.08),
              side: BorderSide.none,
              labelStyle: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: period == selected ? onPrimary : AppColors.textPrimary,
              ),
              onSelected: enabled
                  ? (_) {
                      if (period != selected) onSelect(period);
                    }
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}
