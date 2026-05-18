import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';

/// Full-page empty state for the Employee surface — surfaced whenever
/// there is no active cycle assigned (between cycles, or before HR
/// opens the first one). Carries an optional retry action because the
/// underlying check is a network call.
class EmptyMyDashboard extends StatelessWidget {
  final VoidCallback? onRetry;
  final String? title;
  final String? message;

  const EmptyMyDashboard({
    super.key,
    this.onRetry,
    this.title,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
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
                  Icons.event_busy_rounded,
                  color: AppColors.primaryPurple,
                  size: 32,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                title ?? AppStrings.emptyDashboardTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message ?? AppStrings.emptyDashboardMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 22),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text(AppStrings.commonRefresh),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryPurple,
                    side: BorderSide(
                      color:
                          AppColors.primaryPurple.withValues(alpha: 0.40),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
