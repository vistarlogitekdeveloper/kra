import 'package:flutter/material.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../widgets/_formatters.dart';

/// Sticky bottom bar on the self-rate form. Shows the weighted total on
/// the left and a primary action button on the right.
///
/// The button label flips based on context:
///   - "Review →"        — pre-review (drives forward to summary screen)
///   - "Submit final"    — on the review screen itself
///   - "Submitting…"     — while the POST is in flight
///
/// The button auto-disables while not all cells are filled (server
/// would reject anyway), while offline (no chance of submission), and
/// while a submit is in flight. Tooltip explains why on hover.
class SelfRateSubmitBar extends StatelessWidget {
  final double weightedTotalPct;
  final String primaryLabel;
  final bool isPrimaryEnabled;
  final bool isSubmitting;
  final bool isAutoSaving;
  final bool isOffline;
  final VoidCallback? onPrimary;

  const SelfRateSubmitBar({
    super.key,
    required this.weightedTotalPct,
    required this.primaryLabel,
    required this.isPrimaryEnabled,
    this.isSubmitting = false,
    this.isAutoSaving = false,
    this.isOffline = false,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final canTap = isPrimaryEnabled && !isSubmitting && !isOffline;
    final button = ElevatedButton(
      onPressed: canTap ? onPrimary : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        disabledBackgroundColor:
            AppColors.primaryPurple.withValues(alpha: 0.25),
        disabledForegroundColor: Colors.white,
        padding:
            const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: isSubmitting
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              primaryLabel,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryPurple.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      AppStrings.selfRateLiveTotal,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          EmployeeFormatters.percent(weightedTotalPct),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (isAutoSaving) ...[
                          const SizedBox(width: 8),
                          _AutoSavingPill(),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (isOffline)
                Tooltip(
                  message: AppStrings.selfRateOfflineTooltip,
                  child: button,
                )
              else
                button,
            ],
          ),
        ),
      ),
    );
  }
}

class _AutoSavingPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_done_rounded, size: 11, color: AppColors.success),
          SizedBox(width: 4),
          Text(
            'Saved',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppColors.success,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
