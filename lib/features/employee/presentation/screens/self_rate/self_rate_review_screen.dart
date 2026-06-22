import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/network/connectivity_service.dart';
import '../../../../../core/router/app_router.dart';
import '../../../../hr/presentation/widgets/confirm_action_dialog.dart';
import '../../../data/models/kra_score_entry.dart';
import '../../providers/self_rate_providers.dart';
import '../../widgets/_formatters.dart';
import '../../widgets/score_pill.dart';

/// Pre-submit summary screen. Shows the user every cell they entered
/// with the final weighted total, then offers a deliberately heavy
/// "Submit final" button because the action is hard to reverse.
///
/// If the user lands here with an empty form state (e.g. via a deep
/// link) we just bounce them back to the form.
class SelfRateReviewScreen extends ConsumerStatefulWidget {
  const SelfRateReviewScreen({super.key});

  @override
  ConsumerState<SelfRateReviewScreen> createState() =>
      _SelfRateReviewScreenState();
}

class _SelfRateReviewScreenState extends ConsumerState<SelfRateReviewScreen> {
  @override
  void initState() {
    super.initState();
    // Empty form → user deep-linked here; punt back to the form.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = ref.read(selfRateProvider);
      if (s.entries.isEmpty || s.review == null) {
        if (mounted) context.go(AppRoutes.employeeSelfRate);
      }
    });
  }

  Future<void> _onSubmit() async {
    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.selfRateConfirmTitle,
      message: AppStrings.selfRateConfirmMessage,
      confirmLabel: AppStrings.selfRateConfirmSubmit,
      cancelLabel: AppStrings.selfRateBackToEdit,
      icon: Icons.send_rounded,
      accentColor: AppColors.primaryPurple,
    );
    if (ok != true) return;
    final updated = await ref.read(selfRateProvider.notifier).submit();
    if (!mounted) return;
    if (updated != null) {
      context.go(AppRoutes.employeeSelfRateSuccess);
    } else {
      // Error flows back via state.submitError — the snackbar fires from
      // the form screen's listener. The review screen stays put so the
      // user can retry without losing the summary view.
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(selfRateProvider);
    final isOnline = ref.watch(connectivityProvider).maybeWhen(
          data: (v) => v,
          orElse: () => true,
        );
    final monthLabel =
        state.entries.isNotEmpty ? state.entries.first.monthLabel : '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          monthLabel.isEmpty
              ? AppStrings.selfRateTitle
              : '${AppStrings.commonView} — $monthLabel',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go(AppRoutes.employeeSelfRate),
          tooltip: AppStrings.selfRateBackToEdit,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          _TotalHero(weightedTotalPct: state.weightedTotalPct),
          for (final entry in state.entries)
            _ReviewRow(
              entry: entry,
              onTap: () => context.go(AppRoutes.employeeSelfRate),
            ),
        ],
      ),
      bottomNavigationBar: _ReviewSubmitBar(
        isSubmitting: state.isSubmitting,
        isOffline: !isOnline,
        onBackToEdit: () => context.go(AppRoutes.employeeSelfRate),
        onSubmit: _onSubmit,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Hero summary block at top
// ─────────────────────────────────────────────────────────────────────

class _TotalHero extends StatelessWidget {
  final double weightedTotalPct;
  const _TotalHero({required this.weightedTotalPct});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryPurple,
            AppColors.primaryPurpleLight,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryPurple.withValues(alpha: 0.20),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              AppStrings.selfRateLiveTotal,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Text(
            EmployeeFormatters.percent(weightedTotalPct),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// One read-only row per entry
// ─────────────────────────────────────────────────────────────────────

class _ReviewRow extends StatelessWidget {
  final KraScoreEntry entry;
  final VoidCallback onTap;
  const _ReviewRow({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasRemark = entry.selfRemark.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.itemName,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      EmployeeFormatters.weightagePercent(
                          entry.weightagePercent),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(width: 10),
                    ScorePill(
                      score: entry.isNotApplicable ? null : entry.selfRating,
                      maxScore: entry.maxScore,
                      tone: ScorePillTone.self,
                      small: true,
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
                if (entry.isNotApplicable)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Marked N/A',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                if (hasRemark)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.format_quote_rounded,
                          size: 14,
                          color: AppColors.primaryPurple,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            entry.selfRemark,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textSecondary,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (entry.hasAttachment)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.attach_file_rounded,
                          size: 14,
                          color: AppColors.primaryPurple,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            entry.attachmentName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Bottom action bar
// ─────────────────────────────────────────────────────────────────────

class _ReviewSubmitBar extends StatelessWidget {
  final bool isSubmitting;
  final bool isOffline;
  final VoidCallback onBackToEdit;
  final Future<void> Function() onSubmit;
  const _ReviewSubmitBar({
    required this.isSubmitting,
    required this.isOffline,
    required this.onBackToEdit,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final canSubmit = !isSubmitting && !isOffline;
    final submitButton = ElevatedButton(
      onPressed: canSubmit ? onSubmit : null,
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
      child: isSubmitting
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Text(
              AppStrings.selfRateSubmitButton,
              style: TextStyle(
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
                child: OutlinedButton(
                  onPressed: isSubmitting ? null : onBackToEdit,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.divider),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    AppStrings.selfRateBackToEdit,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: isOffline
                    ? Tooltip(
                        message: AppStrings.selfRateOfflineTooltip,
                        child: submitButton,
                      )
                    : submitButton,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
