import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../widgets/empty_state.dart';

/// Reports tab placeholder. Real charts (payout, distribution, exports)
/// land in Step 7 — kept as an explicit "coming soon" so HR users
/// understand what to expect.
class HrReportsScreen extends StatelessWidget {
  const HrReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.hrReportsTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: EmptyState(
          icon: Icons.insights_rounded,
          title: AppStrings.hrReportsComingSoonTitle,
          message: AppStrings.hrReportsComingSoonMessage,
        ),
      ),
    );
  }
}
