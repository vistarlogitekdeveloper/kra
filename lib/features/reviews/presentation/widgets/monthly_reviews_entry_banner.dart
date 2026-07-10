import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/router/app_router.dart';

/// Temporary entry point into the new monthly-review pipeline, shown on
/// each role's landing screen. Phase 3 replaces this with proper shell
/// navigation; for now it lets every login reach the new dashboards.
class MonthlyReviewsEntryBanner extends StatelessWidget {
  const MonthlyReviewsEntryBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: AppColors.primaryPurple,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push(AppRoutes.monthlyReviews),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.calendar_month_rounded,
                    color: Colors.white, size: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppStrings.monthlyReviewsNavPreview,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
