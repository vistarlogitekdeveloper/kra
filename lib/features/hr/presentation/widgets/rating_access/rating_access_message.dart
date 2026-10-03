import 'package:flutter/material.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_strings.dart';

/// The rating-access screen's non-content states: an error with a retry, an
/// empty history, or the lock a non-super-admin sees.
class RatingAccessMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  /// Shows a Retry button when set.
  final VoidCallback? onRetry;

  /// Tint for the icon. Muted by default; errors pass [AppColors.error].
  final Color? accent;

  const RatingAccessMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? AppColors.primaryPurple;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tint.withValues(alpha: 0.12),
            ),
            child: Icon(icon, color: tint, size: 26),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text(AppStrings.commonRetry),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                minimumSize: const Size(48, 48),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
