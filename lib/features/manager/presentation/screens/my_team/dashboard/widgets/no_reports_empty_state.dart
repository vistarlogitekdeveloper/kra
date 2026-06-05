import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../../../core/constants/app_colors.dart';
import '../../../../../../../core/constants/app_strings.dart';
import '../../../../../../../core/router/app_router.dart';

/// Full-screen empty state shown when the backend returns
/// `403 NO_DIRECT_REPORTS` — the user has manager role but no
/// assignments. Offers a one-tap jump into the employee surface so
/// they can still self-rate rather than hitting a dead end.
class NoReportsEmptyState extends StatelessWidget {
  const NoReportsEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryPurple.withValues(alpha: 0.10),
                ),
                child: const Icon(
                  Icons.groups_outlined,
                  color: AppColors.primaryPurple,
                  size: 32,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                AppStrings.managerDashboardNoReportsTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                AppStrings.managerDashboardNoReportsMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),
              ElevatedButton.icon(
                onPressed: () => context.go(AppRoutes.employeeHome),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.rate_review_outlined, size: 18),
                label: const Text(
                  AppStrings.managerDashboardNoReportsCta,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
