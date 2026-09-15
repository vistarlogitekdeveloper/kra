import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/error_text.dart';
import '../../../../core/api/api_error.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
import '../../data/models/kra_template.dart';
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
                message: userFacingError(e),
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
                  onClone: () => _clone(
                    context,
                    ref,
                    template,
                    list.map((t) => t.name),
                  ),
                  onDelete: () => _delete(context, ref, template.id),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Duplicates [template] under a name the user confirms.
  ///
  /// The name is asked for rather than derived because the API demands one and
  /// rejects duplicates with 409 — and because a copy almost always exists to
  /// be an exception for one employee, which is worth saying in its name.
  Future<void> _clone(
    BuildContext context,
    WidgetRef ref,
    KraTemplate template,
    Iterable<String> existingNames,
  ) async {
    final name = await _CloneNameDialog.show(
      context,
      initialName: suggestedCloneName(template.name, existingNames),
    );
    if (name == null || !context.mounted) return; // cancelled

    try {
      await ref.read(kraTemplateActionsProvider).clone(template.id, name: name);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(AppStrings.kraTemplatesCloneSuccess),
        ),
      );
    } on ApiError catch (e) {
      if (!context.mounted) return;
      // A 409 means the name is taken — the only failure the user can fix
      // themselves, so say so in those words instead of echoing the raw
      // "Template \"X\" already exists".
      final message = e.statusCode == 409
          ? AppStrings.kraTemplatesCloneNameTaken
          : e.message;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, String id) async {
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
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ...result.failed.map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${f.name} — ${f.reason}',
                    style: TextStyle(
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

/// Asks for the copy's name before duplicating a template.
///
/// Exists because the clone endpoint validates `name` (a missing one is a 400
/// VAL_001) and enforces uniqueness (409). Pre-filled with a free-looking
/// suggestion and fully selected, so confirming is one tap while renaming needs
/// no clearing first.
class _CloneNameDialog extends StatefulWidget {
  final String initialName;
  const _CloneNameDialog({required this.initialName});

  /// Returns the chosen name, or null if the user cancelled.
  static Future<String?> show(
    BuildContext context, {
    required String initialName,
  }) =>
      showDialog<String>(
        context: context,
        builder: (_) => _CloneNameDialog(initialName: initialName),
      );

  @override
  State<_CloneNameDialog> createState() => _CloneNameDialogState();
}

class _CloneNameDialogState extends State<_CloneNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  )..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initialName.length,
    );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Validates against the API's own rules, so an invalid name is caught here
  /// rather than coming back as a VAL_001 the user has to decode.
  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = AppStrings.kraTemplatesCloneNameRequired);
      return;
    }
    if (name.length > kKraTemplateNameMaxLength) {
      setState(() => _error =
          AppStrings.kraTemplatesCloneNameTooLong(kKraTemplateNameMaxLength));
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text(AppStrings.kraTemplatesCloneTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.kraTemplatesCloneMessage,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: kKraTemplateNameMaxLength,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              labelText: AppStrings.kraTemplatesCloneNameLabel,
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.commonCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text(AppStrings.kraTemplatesCloneCta),
        ),
      ],
    );
  }
}
