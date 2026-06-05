import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/router/app_router.dart';
import '../../providers/self_rate_providers.dart';
import '../../widgets/_formatters.dart';

/// Confirmation screen shown right after a successful submit. Deep-
/// linking here directly is supported but useless — without a recent
/// submission, the screen falls back to a generic "Back to home" CTA.
class SelfRateSuccessScreen extends ConsumerWidget {
  const SelfRateSuccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final review = ref.watch(selfRateProvider).lastSubmittedReview ??
        ref.watch(selfRateProvider).review;

    final managerDeadline = review?.reviewCycle?.managerReviewDeadline;
    final selfTotal = review?.finalAvgSelfPct;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 1),
              const _SuccessIllustration(),
              const SizedBox(height: 24),
              const Text(
                AppStrings.selfRateSuccessTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              if (managerDeadline != null)
                Text(
                  '${AppStrings.selfRateSuccessSubtitle} '
                  '${EmployeeFormatters.date(managerDeadline)}.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
              if (selfTotal != null) ...[
                const SizedBox(height: 22),
                _TotalCard(value: selfTotal),
              ],
              const Spacer(flex: 2),
              ElevatedButton(
                onPressed: () {
                  if (review != null) {
                    context.go(AppRoutes.employeeReviewDetail(review.id));
                  } else {
                    context.go(AppRoutes.employeeHistory);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  AppStrings.selfRateViewSubmission,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () {
                  // Drop the in-memory form state so re-entering the
                  // self-rate tab does a fresh load (and picks up the
                  // now-locked state).
                  ref.read(selfRateProvider.notifier).reset();
                  context.go(AppRoutes.employeeHome);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.divider),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  AppStrings.selfRateBackToHome,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuccessIllustration extends StatefulWidget {
  const _SuccessIllustration();

  @override
  State<_SuccessIllustration> createState() => _SuccessIllustrationState();
}

class _SuccessIllustrationState extends State<_SuccessIllustration>
    with TickerProviderStateMixin {
  late final AnimationController _ringController;
  late final AnimationController _checkController;

  late final Animation<double> _outerRing;
  late final Animation<double> _middleRing;
  late final Animation<double> _innerScale;
  late final Animation<double> _checkProgress;

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _outerRing = CurvedAnimation(
      parent: _ringController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
    );
    _middleRing = CurvedAnimation(
      parent: _ringController,
      curve: const Interval(0.15, 0.75, curve: Curves.easeOutCubic),
    );
    _innerScale = CurvedAnimation(
      parent: _ringController,
      curve: const Interval(0.3, 1.0, curve: Curves.elasticOut),
    );
    _checkProgress = CurvedAnimation(
      parent: _checkController,
      curve: Curves.easeOutCubic,
    );

    _ringController.forward();
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) _checkController.forward();
    });
  }

  @override
  void dispose() {
    _ringController.dispose();
    _checkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 132,
        height: 132,
        child: AnimatedBuilder(
          animation: Listenable.merge([_ringController, _checkController]),
          builder: (_, __) {
            return Stack(
              alignment: Alignment.center,
              children: [
                Transform.scale(
                  scale: _outerRing.value,
                  child: Container(
                    width: 132,
                    height: 132,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.success.withValues(alpha: 0.10),
                    ),
                  ),
                ),
                Transform.scale(
                  scale: _middleRing.value,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.success.withValues(alpha: 0.18),
                    ),
                  ),
                ),
                Transform.scale(
                  scale: _innerScale.value,
                  child: Container(
                    width: 62,
                    height: 62,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.success,
                    ),
                    child: ClipOval(
                      child: Align(
                        alignment: const Alignment(0, 0),
                        widthFactor: _checkProgress.value,
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  final double value;
  const _TotalCard({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              AppStrings.selfRateSuccessTotalLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Text(
            EmployeeFormatters.percent(value),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: AppColors.primaryPurple,
            ),
          ),
        ],
      ),
    );
  }
}
