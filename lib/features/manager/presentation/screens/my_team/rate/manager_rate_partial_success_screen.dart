import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../../../../core/router/app_router.dart';
import '../../../../../employee/presentation/widgets/_formatters.dart';
import '../../../../data/models/transition_error.dart';
import '../../../providers/manager_rate_providers.dart';

/// Shown when POST manager-rate returned `transitioned: false`. The
/// manager's scores are saved but the review didn't advance state —
/// usually because Ops/Finance haven't filled their parts yet.
///
/// Two CTAs:
///   - "Try submit again" → resubmit (in case of transient failures)
///   - "Back to review" → review detail screen (canonical exit)
class ManagerRatePartialSuccessScreen extends ConsumerWidget {
  final String reviewId;
  const ManagerRatePartialSuccessScreen({super.key, required this.reviewId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(managerRateProvider);
    final transitionError =
        state.lastSubmitResponse?.transitionError;
    final managerTotal =
        state.lastSubmitResponse?.totals.managerTotal;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          AppStrings.managerRatePartialTitle,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () =>
              context.go(AppRoutes.managerReviewDetail(reviewId)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          const _Illustration(),
          const SizedBox(height: 22),
          const Text(
            AppStrings.managerRatePartialSubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          if (transitionError != null)
            _ReasonCard(error: transitionError),
          if (managerTotal != null) ...[
            const SizedBox(height: 14),
            _TotalSaved(value: managerTotal),
          ],
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: state.isSubmitting
                ? null
                : () async {
                    final response = await ref
                        .read(managerRateProvider.notifier)
                        .submit();
                    if (!context.mounted) return;
                    if (response != null && response.transitioned) {
                      context.go(
                          AppRoutes.managerRateSuccess(reviewId));
                    }
                  },
            icon: state.isSubmitting
                ? const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
            label: const Text(
              AppStrings.managerRatePartialTryAgain,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryPurple,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  AppColors.primaryPurple.withValues(alpha: 0.25),
              disabledForegroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () {
              ref.read(managerRateProvider.notifier).reset();
              context.go(
                AppRoutes.managerReviewDetail(reviewId),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.divider),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              AppStrings.managerRatePartialBackToReview,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _Illustration extends StatelessWidget {
  const _Illustration();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accentOrange.withValues(alpha: 0.14),
            ),
          ),
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accentOrange,
            ),
            child: const Icon(
              Icons.hourglass_bottom_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReasonCard extends StatelessWidget {
  final TransitionError error;
  const _ReasonCard({required this.error});

  /// Translate the structured error code into a user-friendly string.
  String _userMessage() {
    switch (error.code) {
      case 'INCOMPLETE_AFTER_COPY':
        return AppStrings.managerRateErrorIncompleteAfterCopy;
      case 'MONTH_LOCKED':
        return AppStrings.managerRateErrorMonthLocked;
      default:
        return error.message;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.accentOrange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.accentOrange.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.accentOrange,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _userMessage(),
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalSaved extends StatelessWidget {
  final double value;
  const _TotalSaved({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              AppStrings.managerRateTotalLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            EmployeeFormatters.percent(value),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryPurple,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}
