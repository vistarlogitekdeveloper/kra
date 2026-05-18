import 'package:flutter/material.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../../data/models/employee_dashboard.dart';
import '../../../widgets/_formatters.dart';

/// Quarterly incentive snapshot — earned-of-eligible with a progress bar.
///
/// Reads `dashboard.incentive` directly so the data is already in hand
/// from the home payload — no extra round-trip. Tapping anywhere on the
/// card invokes [onTap] (typically navigates to the History tab where
/// the per-month breakdown lives).
class IncentiveSnapshotCard extends StatelessWidget {
  final DashboardIncentive incentive;
  final VoidCallback onTap;

  const IncentiveSnapshotCard({
    super.key,
    required this.incentive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Server sends earnedPercentage as a 0–100 number ("75.83").
    // Clamp into [0, 1] for the linear progress widget — being defensive
    // here protects against any future contract change without crashing.
    final progress = (incentive.earnedPercentage / 100).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.divider),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.accentYellow.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.savings_rounded,
                        color: AppColors.accentOrange,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        AppStrings.homeIncentiveTitle,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textMuted,
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _AmountRow(
                  earned: incentive.earnedSoFar,
                  eligible: incentive.quarterlyEligible,
                ),
                const SizedBox(height: 12),
                _ProgressBar(progress: progress),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      EmployeeFormatters.percent(
                          incentive.earnedPercentage),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryPurple,
                      ),
                    ),
                    const Text(
                      AppStrings.homeIncentiveCaption,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  final double earned;
  final double eligible;
  const _AmountRow({required this.earned, required this.eligible});

  @override
  Widget build(BuildContext context) {
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          TextSpan(
            text: EmployeeFormatters.currencyInr(earned),
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.6,
            ),
          ),
          const TextSpan(
            text: ' ${AppStrings.homeIncentiveOf} ',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          TextSpan(
            text: EmployeeFormatters.currencyInr(eligible),
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double progress;
  const _ProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 10,
        child: Stack(
          children: [
            const ColoredBox(color: AppColors.divider),
            FractionallySizedBox(
              widthFactor: progress,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      AppColors.primaryPurple,
                      AppColors.accentOrange,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
