import 'package:flutter/material.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/enums/review_flow.dart';
import '../../../../reviews/data/models/rating_access.dart';

/// Which organisation this is, and which pipeline it runs — the flow decides
/// which stage cards exist and what the reporting-manager seat is called.
class RatingAccessHeader extends StatelessWidget {
  final RatingAccessMonth month;

  const RatingAccessHeader({super.key, required this.month});

  @override
  Widget build(BuildContext context) {
    // The tint carries the distinction; the text stays at full contrast.
    final standard = month.reviewFlow == ReviewFlow.standard;
    final badge = standard ? AppColors.textMuted : AppColors.accentOrange;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            month.organizationName ?? month.organizationId,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: badge.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${AppStrings.orgFlowLabel}: ${month.reviewFlow.displayName}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            AppStrings.ratingAccessIntro,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
