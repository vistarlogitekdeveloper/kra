import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../data/models/project_location.dart';
import '../providers/project_location_providers.dart';
import '../widgets/confirm_action_dialog.dart';
import '../widgets/empty_state.dart';

/// Locations management screen.
/// Lists project locations — create/edit/delete via bottom sheet.
class LocationsScreen extends ConsumerWidget {
  const LocationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locations = ref.watch(allLocationsForManagementProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.locationsTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
          tooltip: AppStrings.commonBack,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        onPressed: () => _openSheet(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text(AppStrings.commonAdd),
      ),
      body: RefreshIndicator(
        color: AppColors.primaryPurple,
        onRefresh: () async {
          ref.invalidate(allLocationsForManagementProvider);
          await ref.read(allLocationsForManagementProvider.future);
        },
        child: locations.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(16),
            physics: const NeverScrollableScrollPhysics(),
            children: const [
              ShimmerBox(height: 76, borderRadius: 14),
              SizedBox(height: 12),
              ShimmerBox(height: 76, borderRadius: 14),
              SizedBox(height: 12),
              ShimmerBox(height: 76, borderRadius: 14),
            ],
          ),
          error: (e, _) => ListView(
            padding: const EdgeInsets.symmetric(vertical: 60),
            children: [
              EmptyState(
                icon: Icons.error_outline_rounded,
                title: AppStrings.errorGeneric,
                message: e.toString(),
                actionLabel: AppStrings.commonRetry,
                onAction: () =>
                    ref.invalidate(allLocationsForManagementProvider),
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
                    icon: Icons.location_on_outlined,
                    title: AppStrings.locationsEmptyTitle,
                    message: AppStrings.locationsEmptyMessage,
                    actionLabel: AppStrings.locationsEmptyCta,
                    onAction: () => _openSheet(context, ref),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final loc = list[i];
                return _LocationTile(
                  location: loc,
                  onTap: () => _openSheet(context, ref, existing: loc),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _openSheet(
    BuildContext context,
    WidgetRef ref, {
    ProjectLocation? existing,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _LocationSheet(existing: existing),
    );
  }
}

class _LocationTile extends StatelessWidget {
  final ProjectLocation location;
  final VoidCallback onTap;
  const _LocationTile({required this.location, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      if (location.code != null && location.code!.isNotEmpty) location.code!,
      if (location.city != null && location.city!.isNotEmpty) location.city!,
      if (location.customer != null && location.customer!.isNotEmpty)
        location.customer!,
    ];
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryPurple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: AppColors.primaryPurple,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      location.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitleParts.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitleParts.join(' • '),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationSheet extends ConsumerStatefulWidget {
  final ProjectLocation? existing;
  const _LocationSheet({this.existing});

  @override
  ConsumerState<_LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends ConsumerState<_LocationSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _cityController;
  late final TextEditingController _stateController;
  late final TextEditingController _addressController;
  late final TextEditingController _customerController;
  bool _isSubmitting = false;
  bool _isDeleting = false;
  String? _serverError;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _codeController = TextEditingController(text: e?.code ?? '');
    _cityController = TextEditingController(text: e?.city ?? '');
    _stateController = TextEditingController(text: e?.state ?? '');
    _addressController = TextEditingController(text: e?.address ?? '');
    _customerController = TextEditingController(text: e?.customer ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _addressController.dispose();
    _customerController.dispose();
    super.dispose();
  }

  String? _trimToNull(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _submit() async {
    setState(() => _serverError = null);
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;
    setState(() => _isSubmitting = true);
    final actions = ref.read(locationActionsProvider);
    try {
      if (widget.existing == null) {
        await actions.create(
          name: _nameController.text.trim(),
          code: _trimToNull(_codeController),
          city: _trimToNull(_cityController),
          state: _trimToNull(_stateController),
          address: _trimToNull(_addressController),
          customer: _trimToNull(_customerController),
        );
      } else {
        await actions.update(widget.existing!.id, {
          'name': _nameController.text.trim(),
          'code': _trimToNull(_codeController),
          'city': _trimToNull(_cityController),
          'state': _trimToNull(_stateController),
          'address': _trimToNull(_addressController),
          'customer': _trimToNull(_customerController),
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.locationSaved)),
      );
      Navigator.of(context).pop();
    } on ApiError catch (e) {
      setState(() => _serverError = e.message);
    } catch (_) {
      setState(() => _serverError = AppStrings.errorGeneric);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.locationDeleteConfirmTitle,
      message: AppStrings.locationDeleteConfirmMessage,
      confirmLabel: AppStrings.commonDelete,
    );
    if (ok != true || !mounted) return;
    setState(() {
      _serverError = null;
      _isDeleting = true;
    });
    try {
      await ref.read(locationActionsProvider).delete(existing.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.locationDeleteSuccess)),
      );
      Navigator.of(context).pop();
    } on ApiError catch (e) {
      setState(() => _serverError = e.message);
    } catch (_) {
      setState(() => _serverError = AppStrings.errorGeneric);
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final busy = _isSubmitting || _isDeleting;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isEdit
                      ? AppStrings.locationFormEditTitle
                      : AppStrings.locationFormCreateTitle,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 18),
                if (_serverError != null) ...[
                  Text(
                    _serverError!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                  const SizedBox(height: 12),
                ],
                _LabeledInput(
                  label: AppStrings.locationFormName,
                  controller: _nameController,
                  icon: Icons.location_city_rounded,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? AppStrings.validationRequired
                      : null,
                ),
                const SizedBox(height: 14),
                _LabeledInput(
                  label: AppStrings.locationFormCode,
                  controller: _codeController,
                  icon: Icons.tag_rounded,
                ),
                const SizedBox(height: 14),
                _LabeledInput(
                  label: AppStrings.locationFormCity,
                  controller: _cityController,
                  icon: Icons.apartment_rounded,
                ),
                const SizedBox(height: 14),
                _LabeledInput(
                  label: AppStrings.locationFormState,
                  controller: _stateController,
                  icon: Icons.map_outlined,
                ),
                const SizedBox(height: 14),
                _LabeledInput(
                  label: AppStrings.locationFormAddress,
                  controller: _addressController,
                  icon: Icons.home_outlined,
                ),
                const SizedBox(height: 14),
                _LabeledInput(
                  label: AppStrings.locationFormCustomer,
                  controller: _customerController,
                  icon: Icons.business_outlined,
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: busy ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor:
                                  AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Icon(Icons.check_rounded),
                    label: const Text(
                      AppStrings.commonSave,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                if (isEdit) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: busy ? null : _delete,
                      icon: _isDeleting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                valueColor:
                                    AlwaysStoppedAnimation(AppColors.error),
                              ),
                            )
                          : const Icon(Icons.delete_outline_rounded,
                              color: AppColors.error),
                      label: const Text(
                        AppStrings.commonDelete,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LabeledInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final String? Function(String?)? validator;
  const _LabeledInput({
    required this.label,
    required this.controller,
    required this.icon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18),
          ),
        ),
      ],
    );
  }
}
