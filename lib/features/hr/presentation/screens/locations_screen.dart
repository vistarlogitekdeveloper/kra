import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../widgets/empty_state.dart';

/// Locations management screen.
/// Lists project locations — create/edit/delete via bottom sheet.
class LocationsScreen extends StatelessWidget {
  const LocationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.locationsTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
          tooltip: AppStrings.commonBack,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        onPressed: () {
          // TODO(step2): navigate to location form
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text(AppStrings.commonAdd),
      ),
      body: const Center(
        child: EmptyState(
          icon: Icons.location_on_outlined,
          title: AppStrings.locationsEmptyTitle,
          message: AppStrings.locationsEmptyMessage,
          actionLabel: AppStrings.locationsEmptyCta,
        ),
      ),
    );
  }
}
