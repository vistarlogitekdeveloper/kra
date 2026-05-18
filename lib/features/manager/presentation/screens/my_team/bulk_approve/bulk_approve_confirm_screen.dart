import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../../../../core/network/connectivity_service.dart';
import '../../../../../../core/router/app_router.dart';
import '../../../../../hr/presentation/widgets/confirm_action_dialog.dart';
import '../../../../data/models/team_member.dart';
import '../../../providers/bulk_approve_providers.dart';
import '../../../providers/manager_team_providers.dart';
import 'widgets/selection_summary.dart';

/// Confirm screen for the bulk-approve flow. Receives the selected
/// review ids via the route's query string (`?ids=a,b,c`) and resolves
/// them to TeamMember rows by looking them up in the team list state.
///
/// Carries an optional overall comment that the backend applies to
/// every approved review.
class BulkApproveConfirmScreen extends ConsumerStatefulWidget {
  final List<String> reviewIds;
  const BulkApproveConfirmScreen({super.key, required this.reviewIds});

  @override
  ConsumerState<BulkApproveConfirmScreen> createState() =>
      _BulkApproveConfirmScreenState();
}

class _BulkApproveConfirmScreenState
    extends ConsumerState<BulkApproveConfirmScreen> {
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.managerBulkApproveConfirmTitle,
      message: AppStrings.managerBulkApproveConfirmMessage,
      confirmLabel: AppStrings.managerBulkApproveCta,
      cancelLabel: AppStrings.commonCancel,
      icon: Icons.check_circle_rounded,
      accentColor: AppColors.primaryPurple,
    );
    if (ok != true) return;
    final comment = _commentController.text.trim();
    final response = await ref
        .read(bulkApproveProvider.notifier)
        .submit(
          reviewIds: widget.reviewIds,
          comment: comment.isEmpty ? null : comment,
        );
    if (!mounted) return;
    if (response != null) {
      context.go(AppRoutes.managerTeamBulkApproveResult);
    } else {
      final err = ref.read(bulkApproveProvider).error;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(bulkApproveProvider);
    final isOnline = ref.watch(connectivityProvider).maybeWhen(
          data: (v) => v,
          orElse: () => true,
        );
    final members = _resolveMembers(ref, widget.reviewIds);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          AppStrings.managerBulkApproveTitle,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: AppStrings.commonCancel,
          onPressed: () => context.go(AppRoutes.managerTeamList),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          SelectionSummary(members: members),
          const SizedBox(height: 18),
          _CommentField(controller: _commentController),
        ],
      ),
      bottomNavigationBar: _ApproveBar(
        isSubmitting: flow.isSubmitting,
        isOffline: !isOnline,
        isReady: widget.reviewIds.isNotEmpty,
        onSubmit: _onSubmit,
      ),
    );
  }

  /// Resolves the supplied review-ids to the TeamMember rows we have
  /// cached in [managerTeamListProvider]. Members not found in the
  /// cache (e.g. page evicted) are skipped — the confirm screen still
  /// renders the row count from `reviewIds.length` so the manager
  /// knows what they're about to do.
  List<TeamMember> _resolveMembers(WidgetRef ref, List<String> ids) {
    final all = ref.read(managerTeamListProvider).members;
    final byReviewId = <String, TeamMember>{
      for (final m in all)
        if (m.reviewId != null) m.reviewId!: m,
    };
    final out = <TeamMember>[];
    for (final id in ids) {
      final match = byReviewId[id];
      if (match != null) out.add(match);
    }
    return out;
  }
}

class _CommentField extends StatelessWidget {
  final TextEditingController controller;
  const _CommentField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
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
            AppStrings.managerBulkApproveCommentLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLength: 500,
            minLines: 3,
            maxLines: 5,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.textPrimary,
              height: 1.5,
            ),
            decoration: InputDecoration(
              hintText: AppStrings.managerBulkApproveCommentHint,
              hintStyle: const TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
              filled: true,
              fillColor: AppColors.background,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: AppColors.divider, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: AppColors.divider, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.primaryPurple,
                  width: 1.4,
                ),
              ),
              counterStyle: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApproveBar extends StatelessWidget {
  final bool isSubmitting;
  final bool isOffline;
  final bool isReady;
  final Future<void> Function() onSubmit;

  const _ApproveBar({
    required this.isSubmitting,
    required this.isOffline,
    required this.isReady,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final canSubmit = isReady && !isSubmitting && !isOffline;
    final btn = ElevatedButton.icon(
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
      icon: isSubmitting
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.check_circle_rounded, size: 18),
      label: const Text(
        AppStrings.managerBulkApproveCta,
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
          child: SizedBox(
            width: double.infinity,
            child: isOffline
                ? Tooltip(
                    message:
                        AppStrings.managerRateOfflineTooltip,
                    child: btn,
                  )
                : btn,
          ),
        ),
      ),
    );
  }
}
