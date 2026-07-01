import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/monthly_deadlines.dart';
import '../../../../core/widgets/monthly_deadline_notice.dart';
import '../../../employee/presentation/widgets/_formatters.dart';
import '../../data/models/monthly_kra_row.dart';
import '../../data/models/monthly_review.dart';
import '../../data/models/review_stage.dart';
import '../../data/models/row_score.dart';
import '../providers/monthly_review_providers.dart';
import '../widgets/monthly_review_widgets.dart';

/// Review detail + the current-stage action. One screen drives every stage:
/// rating stages show editable score inputs, Management Review shows
/// approve/return, Incentive Payout shows "mark paid". When the signed-in
/// user can't act on the current stage it's read-only with a "waiting on…"
/// banner.
class MonthlyReviewDetailScreen extends ConsumerStatefulWidget {
  final String reviewId;
  const MonthlyReviewDetailScreen({super.key, required this.reviewId});

  @override
  ConsumerState<MonthlyReviewDetailScreen> createState() =>
      _MonthlyReviewDetailScreenState();
}

class _MonthlyReviewDetailScreenState
    extends ConsumerState<MonthlyReviewDetailScreen> {
  final Map<String, TextEditingController> _scoreCtrls = {};
  final Map<String, TextEditingController> _remarkCtrls = {};
  final TextEditingController _commentCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    for (final c in _scoreCtrls.values) {
      c.dispose();
    }
    for (final c in _remarkCtrls.values) {
      c.dispose();
    }
    _commentCtrl.dispose();
    super.dispose();
  }

  TextEditingController _scoreCtrl(MonthlyKraRow row, ReviewStage stage) {
    return _scoreCtrls.putIfAbsent(row.id, () {
      final existing = row.scoreFor(stage);
      return TextEditingController(
        text: existing?.value == null
            ? ''
            : EmployeeFormatters.score(existing!.value!),
      );
    });
  }

  TextEditingController _remarkCtrl(MonthlyKraRow row, ReviewStage stage) {
    return _remarkCtrls.putIfAbsent(
      row.id,
      () => TextEditingController(text: row.scoreFor(stage)?.remark ?? ''),
    );
  }

  // Mock phase: gate purely on role — the list is already scoped to what
  // this user can see (own review / team / org), and the real backend will
  // enforce per-record ownership (own review, own direct report) in Phase 4.
  bool _canAct(MonthlyReview review, ReviewScope scope) =>
      review.isActionableBy(scope.role);

  @override
  Widget build(BuildContext context) {
    final reviewAsync = ref.watch(monthlyReviewDetailProvider(widget.reviewId));
    final scope = ref.watch(currentReviewScopeProvider);

    // Title shows the employee once loaded so the app bar isn't a repeat
    // of the dashboard. Falls back to the section label during the async
    // fetch and any error state.
    final title = reviewAsync.maybeWhen(
      data: (r) => r.employeeName,
      orElse: () => AppStrings.monthlyReviewsTitleAll,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: reviewAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(e.toString(),
                style: const TextStyle(color: AppColors.error)),
          ),
        ),
        data: (review) => _body(review, scope),
      ),
    );
  }

  Widget _body(MonthlyReview review, ReviewScope? scope) {
    final stage = review.currentStage;
    final canAct = scope != null && _canAct(review, scope);
    final isRating = stage.isRatingStage;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _Header(review: review),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: StageTimeline(review: review),
        ),
        if (!stage.isTerminal && stage.deadlineDay != null)
          MonthlyDeadlineNotice(
            title: stage.label,
            deadline:
                MonthlyDeadlines.forStage(stage, review.period.dateOn(1))!,
          ),
        const SizedBox(height: 12),
        // KRA rows
        for (final row in review.rows)
          _RowCard(
            row: row,
            editingStage: canAct && isRating ? stage : null,
            scoreCtrl: _scoreCtrl(row, stage),
            remarkCtrl: _remarkCtrl(row, stage),
          ),
        const SizedBox(height: 8),
        _IncentiveCard(review: review),
        const SizedBox(height: 16),
        _actionArea(review, scope, canAct),
      ],
    );
  }

  Widget _actionArea(MonthlyReview review, ReviewScope? scope, bool canAct) {
    if (review.currentStage.isTerminal) {
      return const _InfoBanner(
        icon: Icons.verified_rounded,
        color: AppColors.success,
        text: 'This review is complete.',
      );
    }
    if (!canAct) {
      return _InfoBanner(
        icon: Icons.hourglass_bottom_rounded,
        color: AppColors.textSecondary,
        text: '${AppStrings.monthlyReviewsWaitingOn} '
            '${review.currentStage.label}.',
      );
    }
    final stage = review.currentStage;
    if (stage.isRatingStage) {
      return _primaryButton(
        AppStrings.monthlyReviewSubmit,
        Icons.check_rounded,
        () => _submitRating(review, scope!, stage),
      );
    }
    if (stage == ReviewStage.managementReview) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _commentCtrl,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: AppStrings.monthlyReviewCommentLabel,
                filled: true,
                fillColor: AppColors.surface,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _submitting
                        ? null
                        : () => _decide(review, scope!, approved: false),
                    icon:
                        const Icon(Icons.undo_rounded, color: AppColors.error),
                    label: const Text(
                      AppStrings.monthlyReviewReturn,
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _submitting
                        ? null
                        : () => _decide(review, scope!, approved: true),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text(AppStrings.monthlyReviewApprove),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    // Incentive payout
    return _primaryButton(
      AppStrings.monthlyReviewMarkPaid,
      Icons.payments_rounded,
      () => _markPaid(review, scope!),
    );
  }

  Widget _primaryButton(String label, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _submitting ? null : onTap,
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Icon(icon),
          label:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryPurple,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────

  Future<void> _submitRating(
    MonthlyReview review,
    ReviewScope scope,
    ReviewStage stage,
  ) async {
    final scores = <String, RowScore>{};
    for (final row in review.rows) {
      final raw = _scoreCtrl(row, stage).text.trim();
      final parsed = double.tryParse(raw);
      if (parsed == null || parsed < 0 || parsed > row.maxScore) {
        _snack('Enter a score 0–${EmployeeFormatters.score(row.maxScore)} '
            'for "${row.name}".');
        return;
      }
      final remark = _remarkCtrl(row, stage).text.trim();
      scores[row.id] =
          RowScore(value: parsed, remark: remark.isEmpty ? null : remark);
    }
    await _run(
      () => ref.read(monthlyReviewRepositoryProvider).submitStage(
            review.id,
            stage,
            rowScores: scores,
            actorId: scope.userId,
            actorName: scope.userName,
          ),
      AppStrings.monthlyReviewSubmitted,
    );
  }

  Future<void> _decide(
    MonthlyReview review,
    ReviewScope scope, {
    required bool approved,
  }) async {
    final comment = _commentCtrl.text.trim();
    // Reject an empty-comment return — the reporting manager needs a
    // reason to redo their stage, otherwise the return is unactionable.
    if (!approved && comment.isEmpty) {
      _snack('Add a comment before returning the review.');
      return;
    }
    await _run(
      () => ref.read(monthlyReviewRepositoryProvider).submitStage(
            review.id,
            ReviewStage.managementReview,
            approved: approved,
            comment: comment.isEmpty ? null : comment,
            actorId: scope.userId,
            actorName: scope.userName,
          ),
      approved
          ? AppStrings.monthlyReviewApproved
          : AppStrings.monthlyReviewReturned,
    );
  }

  Future<void> _markPaid(MonthlyReview review, ReviewScope scope) async {
    await _run(
      () => ref.read(monthlyReviewRepositoryProvider).markPaid(
            review.id,
            actorId: scope.userId,
            actorName: scope.userName,
          ),
      AppStrings.monthlyReviewPaid,
    );
  }

  Future<void> _run(
      Future<MonthlyReview> Function() action, String successMsg) async {
    setState(() => _submitting = true);
    try {
      await action();
      // Refresh every surface that shows this review.
      ref.invalidate(monthlyReviewDetailProvider(widget.reviewId));
      ref.invalidate(availablePeriodsProvider);
      // The list family is keyed by period — invalidate the whole family.
      ref.invalidate(monthlyReviewListProvider);
      if (!mounted) return;
      _snack(successMsg);
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) _snack(AppStrings.monthlyReviewActionFailed);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

// ── Pieces ────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final MonthlyReview review;
  const _Header({required this.review});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
        color: AppColors.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            review.employeeName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${review.period.label}'
            '${review.grade != null ? ' · ${review.grade}' : ''}',
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  final MonthlyKraRow row;

  /// When non-null, the row shows an editable input for this stage.
  final ReviewStage? editingStage;
  final TextEditingController scoreCtrl;
  final TextEditingController remarkCtrl;

  const _RowCard({
    required this.row,
    required this.editingStage,
    required this.scoreCtrl,
    required this.remarkCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
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
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                EmployeeFormatters.weightagePercent(row.weightagePercent),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Existing per-stage scores.
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final s in const [
                ReviewStage.selfRating,
                ReviewStage.accountHrRating,
                ReviewStage.reportingManagerRating,
              ])
                if (row.scoreFor(s)?.value != null)
                  _ScoreChip(
                    label: s.label,
                    value: '${EmployeeFormatters.score(row.scoreFor(s)!.value!)}'
                        '/${EmployeeFormatters.score(row.maxScore)}',
                  ),
            ],
          ),
          if (editingStage != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: TextField(
                    controller: scoreCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d{0,3}(\.\d{0,1})?')),
                    ],
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: AppStrings.monthlyReviewScoreHint,
                      suffixText: '/${EmployeeFormatters.score(row.maxScore)}',
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: remarkCtrl,
                    minLines: 1,
                    maxLines: 2,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: AppStrings.monthlyReviewRemarkHint,
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  final String label;
  final String value;
  const _ScoreChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryPurple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _IncentiveCard extends StatelessWidget {
  final MonthlyReview review;
  const _IncentiveCard({required this.review});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryPurple.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.primaryPurple.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(AppStrings.monthlyReviewProjectedPayout,
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(
                  EmployeeFormatters.currencyInr(review.projectedPayout),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryPurple,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                  '${AppStrings.monthlyReviewEligible}: '
                  '${EmployeeFormatters.currencyInr(review.eligibleAmount)}',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textMuted)),
              const SizedBox(height: 2),
              Text(
                EmployeeFormatters.percent(review.finalScorePct),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: color, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
