import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../../../core/widgets/slow_load_hint.dart';
import '../../../auth/data/models/user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../providers/review_cycle_providers.dart';
import '../widgets/confirm_action_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/review_cycle_card.dart';

class ReviewCyclesScreen extends ConsumerWidget {
  const ReviewCyclesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cycles = ref.watch(reviewCyclesProvider);

    // "Delete all" is a destructive admin power — limit it to the elevated
    // roles (ADMIN / HR_ADMIN).
    final authState = ref.watch(authStateProvider);
    final role = authState is AuthAuthenticated ? authState.user.role : null;
    final canWipe = role == UserRole.admin || role == UserRole.hrAdmin;
    final hasCycles = cycles.maybeWhen(
      data: (list) => list.isNotEmpty,
      orElse: () => false,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.reviewCyclesTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          if (canWipe && hasCycles)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              color: AppColors.error,
              tooltip: AppStrings.reviewCyclesDeleteAllTooltip,
              onPressed: () => _deleteAll(context, ref),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        onPressed: () => context.push(AppRoutes.hrCycleNew),
        icon: const Icon(Icons.add_rounded),
        label: const Text(AppStrings.commonAdd),
      ),
      body: RefreshIndicator(
        color: AppColors.primaryPurple,
        onRefresh: () => ref.read(reviewCyclesProvider.notifier).refresh(),
        child: cycles.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(16),
            children: const [
              SlowLoadHint(),
              ShimmerBox(height: 160, borderRadius: 16),
              SizedBox(height: 14),
              ShimmerBox(height: 160, borderRadius: 16),
              SizedBox(height: 14),
              ShimmerBox(height: 160, borderRadius: 16),
            ],
          ),
          error: (e, _) => ListView(
            padding: const EdgeInsets.symmetric(vertical: 60),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              EmptyState(
                icon: Icons.error_outline_rounded,
                title: AppStrings.errorGeneric,
                message: e.toString(),
                actionLabel: AppStrings.commonRetry,
                onAction: () =>
                    ref.read(reviewCyclesProvider.notifier).refresh(),
              ),
            ],
          ),
          data: (list) {
            if (list.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 60),
                  EmptyState(
                    icon: Icons.event_available_rounded,
                    title: AppStrings.reviewCyclesEmptyTitle,
                    message: AppStrings.reviewCyclesEmptyMessage,
                    actionLabel: AppStrings.reviewCyclesEmptyCta,
                    onAction: () => context.push(AppRoutes.hrCycleNew),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final cycle = list[i];
                return ReviewCycleCard(
                  cycle: cycle,
                  onActivate: () => _activate(context, ref, cycle.id),
                  onClose: () => _close(context, ref, cycle.id),
                  onDelete: () => _delete(context, ref, cycle.id, cycle.name),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _activate(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.reviewCyclesActivateConfirmTitle,
      message: AppStrings.reviewCyclesActivateConfirmMessage,
      confirmLabel: AppStrings.reviewCyclesActivate,
      icon: Icons.play_arrow_rounded,
      accentColor: AppColors.success,
    );
    if (ok != true || !context.mounted) return;
    final success =
        await ref.read(reviewCyclesProvider.notifier).activateOptimistic(id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? AppStrings.reviewCyclesActivateSuccess
              : AppStrings.reviewCyclesActivateFailed,
        ),
        backgroundColor: success ? AppColors.textPrimary : AppColors.error,
      ),
    );
  }

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.reviewCyclesDeleteAllTitle,
      message: AppStrings.reviewCyclesDeleteAllMessage,
      confirmLabel: AppStrings.reviewCyclesDeleteAllConfirm,
      icon: Icons.delete_sweep_outlined,
      accentColor: AppColors.error,
    );
    if (ok != true || !context.mounted) return;
    final result = await ref.read(reviewCyclesProvider.notifier).deleteAll();
    if (!context.mounted) return;
    final message = result.failed == 0
        ? 'Deleted ${result.deleted} '
            'cycle${result.deleted == 1 ? '' : 's'}.'
        : 'Deleted ${result.deleted}, but ${result.failed} could not be '
            'removed (the server refused — they may be locked).';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            result.failed == 0 ? AppColors.textPrimary : AppColors.error,
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    String id,
    String name,
  ) async {
    final ok = await ConfirmActionDialog.show(
      context,
      title: 'Delete review cycle?',
      message: 'Permanently removes "$name" and every assignment + review '
          'tied to it. This cannot be undone.',
      confirmLabel: 'Delete cycle',
      icon: Icons.delete_outline_rounded,
      accentColor: AppColors.error,
    );
    if (ok != true || !context.mounted) return;
    final success =
        await ref.read(reviewCyclesProvider.notifier).deleteOptimistic(id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? 'Cycle deleted.'
            : 'Could not delete cycle. It may have active reviews.'),
        backgroundColor: success ? AppColors.textPrimary : AppColors.error,
      ),
    );
  }

  Future<void> _close(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.reviewCyclesCloseConfirmTitle,
      message: AppStrings.reviewCyclesCloseConfirmMessage,
      confirmLabel: AppStrings.reviewCyclesClose,
    );
    if (ok != true || !context.mounted) return;
    final success =
        await ref.read(reviewCyclesProvider.notifier).closeOptimistic(id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? AppStrings.reviewCyclesCloseSuccess
              : AppStrings.reviewCyclesCloseFailed,
        ),
        backgroundColor: success ? AppColors.textPrimary : AppColors.error,
      ),
    );
  }
}
