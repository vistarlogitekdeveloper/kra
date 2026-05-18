import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../widgets/empty_state.dart';

/// Bulk Setup wizard entry point.
/// 4-step: filter → select → preview → execute.
class BulkSetupScreen extends StatelessWidget {
  const BulkSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.bulkSetupTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
          tooltip: AppStrings.commonBack,
        ),
      ),
      body: const Center(
        child: EmptyState(
          icon: Icons.group_add_outlined,
          title: AppStrings.bulkSetupTitle,
          message:
              'Select a review cycle to find eligible employees and create bulk KRA assignments.',
        ),
      ),
    );
  }
}
