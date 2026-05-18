import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../../../../core/network/connectivity_service.dart';
import '../../../../../../core/router/app_router.dart';
import '../../../../../employee/data/models/enums.dart';
import '../../../../../employee/presentation/widgets/_formatters.dart';
import '../../../../../hr/presentation/widgets/confirm_action_dialog.dart';
import '../../../../data/models/monthly_score.dart';
import '../../../../data/models/review_row.dart';
import '../../../providers/manager_rate_providers.dart';

/// Pre-submit summary. Read-only table of the manager's ratings,
/// totals, and the overall comment. Submit triggers the POST and
/// routes to the appropriate post-submit screen depending on whether
/// the review transitioned.
class ManagerRateReviewScreen extends ConsumerStatefulWidget {
  final String reviewId;
  const ManagerRateReviewScreen({super.key, required this.reviewId});

  @override
  ConsumerState<ManagerRateReviewScreen> createState() =>
      _ManagerRateReviewScreenState();
}

class _ManagerRateReviewScreenState
    extends ConsumerState<ManagerRateReviewScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(managerRateProvider);
      // Deep-link / refresh resilience: if the rate state is empty
      // (notifier was disposed), drop back to the rate screen so the
      // load runs there.
      if (state.review == null || !state.isComplete) {
        if (state.review == null) {
          context.go(AppRoutes.managerRate(widget.reviewId));
        }
      }
    });
  }

  Future<void> _onSubmit() async {
    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.managerRateConfirmTitle,
      message: AppStrings.managerRateConfirmMessage,
      confirmLabel: AppStrings.managerRateSubmitCta,
      cancelLabel: AppStrings.commonCancel,
      icon: Icons.send_rounded,
      accentColor: AppColors.primaryPurple,
    );
    if (ok != true) return;
    final response =
        await ref.read(managerRateProvider.notifier).submit();
    if (!mounted || response == null) {
      // submitError is shown via snackbar by the parent listener.
      final err = ref.read(managerRateProvider).submitError;
      if (err != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err)),
        );
        ref.read(managerRateProvider.notifier).clearSubmitError();
      }
      return;
    }
    if (!context.mounted) return;
    if (response.transitioned) {
      context.go(AppRoutes.managerRateSuccess(widget.reviewId));
    } else {
      context.go(AppRoutes.managerRatePartial(widget.reviewId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(managerRateProvider);
    final review = state.review;
    final isOnline = ref.watch(connectivityProvider).maybeWhen(
          data: (v) => v,
          orElse: () => true,
        );

    if (review == null) {
      // Notifier still loading after a hot reload / deep link. Show a
      // tiny placeholder and let the post-frame redirect kick in.
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryPurple),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          AppStrings.managerRateReviewTitle,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: AppStrings.managerRateBackToEdit,
          onPressed: () =>
              context.go(AppRoutes.managerRate(widget.reviewId)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          _TotalHero(weightedTotalPct: state.weightedTotalPct),
          for (final row in review.rows)
            _RowSummary(
              row: row,
              months: review.cycle.months
                  .where((m) => m.status == ReviewMonthStatus.open)
                  .map((m) => m.id)
                  .toList(),
            ),
          if (state.managerComment.trim().isNotEmpty)
            _CommentSummary(comment: state.managerComment),
        ],
      ),
      bottomNavigationBar: _SubmitBar(
        isSubmitting: state.isSubmitting,
        isOffline: !isOnline,
        onBackToEdit: () =>
            context.go(AppRoutes.managerRate(widget.reviewId)),
        onSubmit: _onSubmit,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Hero summary
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
              AppStrings.managerRateTotalLabel,
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
// One row summary card per KRA
// ─────────────────────────────────────────────────────────────────────

class _RowSummary extends StatelessWidget {
  final ReviewRow row;
  final List<String> months;
  const _RowSummary({required this.row, required this.months});

  @override
  Widget build(BuildContext context) {
    final hasRemark = row.monthlyScores
        .any((c) => (c.managerRemark ?? '').trim().isNotEmpty);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
                  row.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                EmployeeFormatters.weightagePercent(row.weightagePercent),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final m in months)
                _MonthValueChip(
                  cell: row.monthlyScores.firstWhere(
                    (c) => c.monthId == m,
                    orElse: () => MonthlyScore(
                      monthlyScoreId: '',
                      monthId: m,
                      monthLabel: '',
                    ),
                  ),
                  maxScore: row.maxScore,
                ),
            ],
          ),
          if (hasRemark) ...[
            const Divider(color: AppColors.divider, height: 22),
            for (final c in row.monthlyScores)
              if ((c.managerRemark ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _RemarkLine(
                    monthLabel: c.monthLabel,
                    remark: c.managerRemark!,
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _MonthValueChip extends StatelessWidget {
  final MonthlyScore cell;
  final double maxScore;
  const _MonthValueChip({required this.cell, required this.maxScore});

  @override
  Widget build(BuildContext context) {
    final label = cell.isNotApplicable
        ? 'N/A'
        : cell.managerRating == null
            ? '—'
            : EmployeeFormatters.scoreOutOf(cell.managerRating!, maxScore);
    final filled = !cell.isNotApplicable && cell.managerRating != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: filled
            ? AppColors.primaryPurple.withValues(alpha: 0.12)
            : AppColors.divider.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            cell.monthLabel.toUpperCase(),
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: filled
                  ? AppColors.primaryPurple
                  : AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: filled
                  ? AppColors.primaryPurpleDark
                  : AppColors.textMuted,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _RemarkLine extends StatelessWidget {
  final String monthLabel;
  final String remark;
  const _RemarkLine({required this.monthLabel, required this.remark});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.accentOrange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            monthLabel.toUpperCase(),
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: AppColors.accentOrange,
              letterSpacing: 0.4,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            remark,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textPrimary,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _CommentSummary extends StatelessWidget {
  final String comment;
  const _CommentSummary({required this.comment});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            AppStrings.managerRateCommentLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            comment,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.textPrimary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Submit bar
// ─────────────────────────────────────────────────────────────────────

class _SubmitBar extends StatelessWidget {
  final bool isSubmitting;
  final bool isOffline;
  final VoidCallback onBackToEdit;
  final Future<void> Function() onSubmit;
  const _SubmitBar({
    required this.isSubmitting,
    required this.isOffline,
    required this.onBackToEdit,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final canSubmit = !isSubmitting && !isOffline;
    final submit = ElevatedButton(
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
              AppStrings.managerRateSubmitCta,
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
                    AppStrings.managerRateBackToEdit,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: isOffline
                    ? Tooltip(
                        message: AppStrings.managerRateOfflineTooltip,
                        child: submit,
                      )
                    : submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
