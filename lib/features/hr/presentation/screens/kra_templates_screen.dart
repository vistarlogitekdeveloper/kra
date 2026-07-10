import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
import '../providers/kra_template_providers.dart';
import '../widgets/confirm_action_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/kra_template_card.dart';

class KraTemplatesScreen extends ConsumerWidget {
  const KraTemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(kraTemplatesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.kraTemplatesTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            tooltip: AppStrings.kraTemplatesDeleteAllMenu,
            onSelected: (v) {
              if (v == 'deleteAll') _deleteAll(context, ref);
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(
                value: 'deleteAll',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_rounded,
                        color: AppColors.error, size: 20),
                    SizedBox(width: 10),
                    Text(
                      AppStrings.kraTemplatesDeleteAllMenu,
                      style: TextStyle(color: AppColors.error),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        onPressed: () => context.push(AppRoutes.hrTemplateNew),
        icon: const Icon(Icons.add_rounded),
        label: const Text(AppStrings.commonAdd),
      ),
      body: RefreshIndicator(
        color: AppColors.primaryPurple,
        onRefresh: () async {
          ref.invalidate(kraTemplatesProvider);
          await ref.read(kraTemplatesProvider.future);
        },
        child: templates.when(
          loading: () => ListView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: const [
              KraTableSkeleton(),
              SizedBox(height: 14),
              KraTableSkeleton(),
              SizedBox(height: 14),
              KraTableSkeleton(),
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
                onAction: () => ref.invalidate(kraTemplatesProvider),
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
                    icon: Icons.description_outlined,
                    title: AppStrings.kraTemplatesEmptyTitle,
                    message: AppStrings.kraTemplatesEmptyMessage,
                    actionLabel: AppStrings.kraTemplatesEmptyCta,
                    onAction: () => context.push(AppRoutes.hrTemplateNew),
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
                final template = list[i];
                return KraTemplateCard(
                  template: template,
                  onTap: () =>
                      context.push(AppRoutes.hrTemplateEdit(template.id)),
                  onClone: () => _clone(context, ref, template.id),
                  onDelete: () => _delete(context, ref, template.id),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _clone(
      BuildContext context, WidgetRef ref, String id) async {
    try {
      await ref.read(kraTemplateActionsProvider).clone(id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(AppStrings.kraTemplatesCloneSuccess),
        ),
      );
    } on ApiError catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, String id) async {
    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.kraTemplatesDeleteConfirmTitle,
      message: AppStrings.kraTemplatesDeleteConfirmMessage,
      confirmLabel: AppStrings.commonDelete,
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(kraTemplateActionsProvider).delete(id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(AppStrings.kraTemplatesDeleteSuccess),
        ),
      );
    } on ApiError catch (e) {
      if (!context.mounted) return;
      // A template used by existing reviews can't be hard-deleted (409).
      // Offer to archive it instead (soft-delete via ?force=true).
      if (e.statusCode == 409) {
        await _offerArchive(context, ref, id, e.message);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  Future<void> _offerArchive(
    BuildContext context,
    WidgetRef ref,
    String id,
    String reason,
  ) async {
    final archive = await ConfirmActionDialog.show(
      context,
      title: AppStrings.kraTemplatesArchiveConfirmTitle,
      message: reason,
      confirmLabel: AppStrings.kraTemplatesArchiveCta,
    );
    if (archive != true || !context.mounted) return;
    try {
      await ref.read(kraTemplateActionsProvider).delete(id, force: true);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.kraTemplatesArchiveSuccess)),
      );
    } on ApiError catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.kraTemplatesDeleteAllConfirmTitle,
      message: AppStrings.kraTemplatesDeleteAllConfirmMessage,
      confirmLabel: AppStrings.kraTemplatesDeleteAllCta,
    );
    if (ok != true || !context.mounted) return;

    BulkTemplateDeleteResult result;
    try {
      result = await ref.read(kraTemplateActionsProvider).deleteAll();
    } on ApiError catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!context.mounted) return;

    if (result.total == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.kraTemplatesDeleteAllNone)),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(AppStrings.kraTemplatesDeleteAllResultTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deleted ${result.deleted} of ${result.total} '
              'template${result.total == 1 ? '' : 's'}.',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (result.failed.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Skipped — the backend protects these:',
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ...result.failed.map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${f.name} — ${f.reason}',
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(AppStrings.commonClose),
          ),
        ],
      ),
    );
  }
}
