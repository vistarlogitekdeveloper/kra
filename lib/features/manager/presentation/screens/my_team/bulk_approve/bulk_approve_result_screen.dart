import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../../../../core/router/app_router.dart';
import '../../../../data/models/bulk_approve_response.dart';
import '../../../providers/bulk_approve_providers.dart';
import 'widgets/approved_list.dart';
import 'widgets/skipped_list.dart';

/// Result screen for the bulk-approve flow. Renders three layouts:
///   1. Clean success (all approved)
///   2. Mixed (some approved, some skipped)
///   3. All skipped (nothing went through)
class BulkApproveResultScreen extends ConsumerWidget {
  const BulkApproveResultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bulkApproveProvider);
    final result = state.result;

    // Deep-link / refresh resilience: no result in memory means the
    // user landed here without going through confirm.
    if (result == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.go(AppRoutes.managerTeamList),
          ),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'No bulk-approve in progress.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: Text(
          _titleFor(result),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            ref.read(bulkApproveProvider.notifier).reset();
            context.go(AppRoutes.managerTeamList);
          },
        ),
      ),
      body: _Body(result: result),
      bottomNavigationBar: _ResultBar(
        result: result,
        onBackToTeam: () {
          ref.read(bulkApproveProvider.notifier).reset();
          context.go(AppRoutes.managerTeamList);
        },
      ),
    );
  }

  String _titleFor(BulkApproveResponse r) {
    if (r.approvedCount == 0) {
      return AppStrings.managerBulkApproveResultAllSkippedTitle;
    }
    if (r.skippedCount == 0) {
      return AppStrings.managerBulkApproveResultCleanTitle;
    }
    return AppStrings.managerBulkApproveResultMixedTitle;
  }
}

class _Body extends StatelessWidget {
  final BulkApproveResponse result;
  const _Body({required this.result});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        _CountsCard(result: result),
        const SizedBox(height: 18),
        if (result.approved.isNotEmpty)
          ApprovedList(items: result.approved),
        if (result.approved.isNotEmpty && result.skipped.isNotEmpty)
          const SizedBox(height: 18),
        if (result.skipped.isNotEmpty)
          SkippedList(items: result.skipped),
      ],
    );
  }
}

class _CountsCard extends StatelessWidget {
  final BulkApproveResponse result;
  const _CountsCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Stat(
              label: AppStrings.managerBulkApproveApprovedCount,
              value: result.approvedCount,
              accent: AppColors.success,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: AppColors.divider,
          ),
          Expanded(
            child: _Stat(
              label: AppStrings.managerBulkApproveSkippedCount,
              value: result.skippedCount,
              accent: result.skippedCount > 0
                  ? AppColors.accentOrange
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final Color accent;

  const _Stat({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: AppColors.textSecondary,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: accent,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}

class _ResultBar extends StatelessWidget {
  final BulkApproveResponse result;
  final VoidCallback onBackToTeam;
  const _ResultBar({
    required this.result,
    required this.onBackToTeam,
  });

  @override
  Widget build(BuildContext context) {
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
                child: ElevatedButton(
                  onPressed: onBackToTeam,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    result.skipped.isEmpty
                        ? AppStrings.managerBulkApproveBackToTeam
                        : AppStrings.managerBulkApproveRateIndividually,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
