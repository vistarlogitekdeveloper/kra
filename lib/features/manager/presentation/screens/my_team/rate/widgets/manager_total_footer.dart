import 'package:flutter/material.dart';

import '../../../../../../../core/constants/app_colors.dart';
import '../../../../../../../core/constants/app_strings.dart';
import '../../../../../../../core/network/connectivity_service.dart';
import '../../../../../../employee/presentation/widgets/_formatters.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sticky bottom bar on the manager-rate screen. Shows the live
/// weighted-total estimate on the left and the primary CTA on the
/// right. Mirrors the employee self-rate submit bar so the two flows
/// feel cohesive.
class ManagerTotalFooter extends ConsumerWidget {
  final double weightedTotalPct;
  final int filledCount;
  final int totalCount;

  final String primaryLabel;
  final bool isPrimaryEnabled;
  final bool isSubmitting;
  final VoidCallback? onPrimary;

  /// Set when the user taps "Review" with missing scores so we can
  /// nudge them visually without a blocking dialog.
  final String? incompleteHint;

  const ManagerTotalFooter({
    super.key,
    required this.weightedTotalPct,
    required this.filledCount,
    required this.totalCount,
    required this.primaryLabel,
    required this.isPrimaryEnabled,
    required this.onPrimary,
    this.isSubmitting = false,
    this.incompleteHint,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(connectivityProvider).maybeWhen(
          data: (v) => v,
          orElse: () => true,
        );
    final canTap =
        isPrimaryEnabled && !isSubmitting && isOnline;
    final disabledReason = !isOnline
        ? AppStrings.selfRateOfflineTooltip
        : (!isPrimaryEnabled
            ? AppStrings.managerRateIncompleteScores
            : null);

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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      AppStrings.managerRateTotalLabel,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
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
                        const SizedBox(width: 8),
                        _Count(filled: filledCount, total: totalCount),
                      ],
                    ),
                  ],
                ),
              ),
              if (disabledReason != null)
                Tooltip(message: disabledReason, child: button)
              else
                button,
            ],
          ),
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  final int filled;
  final int total;
  const _Count({required this.filled, required this.total});

  @override
  Widget build(BuildContext context) {
    final isDone = total > 0 && filled >= total;
    final fg = isDone ? AppColors.success : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '$filled / $total',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: fg,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
