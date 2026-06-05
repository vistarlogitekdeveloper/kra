import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
import '../../../auth/presentation/widgets/branded_primary_button.dart';
import '../../../auth/presentation/widgets/branded_text_field.dart';
import '../../data/models/kra_template.dart';
import '../../data/models/kra_template_item.dart';
import '../providers/kra_template_providers.dart';
import '../widgets/confirm_action_dialog.dart';
import '../widgets/kra_item_input_row.dart';
import '../widgets/weightage_indicator.dart';

/// KRA template editor — the most complex form in the HR module.
///
/// Maintains a list of [KraTemplateItem]s with persistent text controllers
/// (one set per item) so reorder/edit operations don't reset the caret.
/// Submit is gated on weightage == 100% AND every item having a name.
class KraTemplateFormScreen extends ConsumerStatefulWidget {
  final String? templateId;
  const KraTemplateFormScreen({super.key, this.templateId});

  bool get isEdit => templateId != null;

  @override
  ConsumerState<KraTemplateFormScreen> createState() =>
      _KraTemplateFormScreenState();
}

class _KraTemplateFormScreenState
    extends ConsumerState<KraTemplateFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _role = 'EMPLOYEE';

  /// One row per KRA item. The associated controllers live in
  /// [_itemControllers] keyed by row index — kept in lock-step with this
  /// list when items are added, deleted or reordered.
  List<KraTemplateItem> _items = [];
  List<_ItemControllers> _itemControllers = [];

  bool _isSubmitting = false;
  bool _isDirty = false;
  bool _hydrated = false;
  String? _serverError;

  // KraTemplate.role is a free-form String on the backend (not bound to
  // UserRole), so seed data ships values like BD_MANAGER / WAREHOUSE_MGR.
  // Keep this list in sync with the Employees screen filter.
  static const _roles = [
    'EMPLOYEE',
    'MANAGER',
    'OPS',
    'OPS_EXCELLENCE',
    'HR',
    'HR_ADMIN',
    'FINANCE',
    'BD_MANAGER',
    'WAREHOUSE_MGR',
  ];

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => _markDirty());
    _descriptionController.addListener(() => _markDirty());
    if (!widget.isEdit) {
      _addBlankItem();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    for (final c in _itemControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _markDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
  }

  void _hydrateFrom(KraTemplate template) {
    if (_hydrated) return;
    _nameController.text = template.name;
    _descriptionController.text = template.description ?? '';
    _items = template.items
        .map((e) => e.copyWith())
        .toList(growable: true);
    // Dispose any controllers from a previous hydrate (defensive).
    for (final c in _itemControllers) {
      c.dispose();
    }
    _itemControllers = [
      for (final item in _items) _ItemControllers.fromItem(item),
    ];
    setState(() {
      _role = template.role;
      _hydrated = true;
      _isDirty = false;
    });
  }

  void _addBlankItem() {
    setState(() {
      _items.add(KraTemplateItem.empty(sortOrder: _items.length));
      _itemControllers.add(_ItemControllers.empty());
      _isDirty = true;
    });
  }

  /// Confirms before removing a KRA so an accidental tap on the trash
  /// icon doesn't silently drop a row the user spent time filling in.
  Future<void> _confirmDeleteItem(int index) async {
    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.kraItemDeleteConfirmTitle,
      message: AppStrings.kraItemDeleteConfirmMessage,
      confirmLabel: AppStrings.commonDelete,
    );
    if (ok == true) _deleteItem(index);
  }

  void _deleteItem(int index) {
    setState(() {
      _items.removeAt(index);
      _itemControllers[index].dispose();
      _itemControllers.removeAt(index);
      // Re-number sortOrder so the wire payload stays consistent.
      for (int i = 0; i < _items.length; i++) {
        _items[i] = _items[i].copyWith(sortOrder: i);
      }
      _isDirty = true;
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final movedItem = _items.removeAt(oldIndex);
      final movedCtrls = _itemControllers.removeAt(oldIndex);
      _items.insert(newIndex, movedItem);
      _itemControllers.insert(newIndex, movedCtrls);
      for (int i = 0; i < _items.length; i++) {
        _items[i] = _items[i].copyWith(sortOrder: i);
      }
      _isDirty = true;
    });
  }

  void _onItemChanged(int index, KraTemplateItem item) {
    // Avoid setState — controllers already hold the visible state. Just
    // update the model so totalWeightage recalculates on the next
    // rebuild triggered by the weightage controller's listener below.
    _items[index] = item.copyWith(sortOrder: index);
    setState(() => _isDirty = true);
  }

  double get _totalWeightage => _items.fold<double>(
        0,
        (sum, item) => sum + item.weightagePercent,
      );

  bool get _hasValidWeightage => (_totalWeightage - 100).abs() < 0.01;

  bool get _allItemsNamed =>
      _items.isNotEmpty && _items.every((i) => i.name.trim().isNotEmpty);

  bool get _canSubmit => _hasValidWeightage && _allItemsNamed && !_isSubmitting;

  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.employeeFormUnsavedTitle,
      message: AppStrings.employeeFormUnsavedMessage,
      confirmLabel: AppStrings.commonDiscard,
      icon: Icons.help_outline_rounded,
      accentColor: AppColors.accentOrange,
    );
    return ok == true;
  }

  Future<void> _submit() async {
    setState(() => _serverError = null);
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok || !_canSubmit) return;
    if (_items.isEmpty) {
      setState(() => _serverError = AppStrings.kraTemplateFormItemsRequired);
      return;
    }

    setState(() => _isSubmitting = true);
    final actions = ref.read(kraTemplateActionsProvider);
    try {
      final payload = KraTemplate(
        id: widget.templateId ?? '',
        name: _nameController.text.trim(),
        role: _role,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        items: _items,
      );
      if (widget.isEdit) {
        await actions.update(widget.templateId!, payload);
      } else {
        await actions.create(payload);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.kraTemplateFormSaved)),
      );
      context.pop();
    } on ApiError catch (e) {
      setState(() => _serverError = e.message);
    } catch (_) {
      setState(() => _serverError = AppStrings.errorGeneric);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = GoRouter.of(context);
        final confirmed = await _confirmDiscard();
        if (!mounted) return;
        if (confirmed) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            widget.isEdit
                ? AppStrings.kraTemplateFormEditTitle
                : AppStrings.kraTemplateFormCreateTitle,
          ),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        body: widget.isEdit && !_hydrated
            ? _buildEditLoader()
            : _buildBody(),
      ),
    );
  }

  Widget _buildEditLoader() {
    final detail = ref.watch(kraTemplateDetailProvider(widget.templateId!));
    return detail.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: KraTableSkeleton(),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            e.toString(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.error),
          ),
        ),
      ),
      data: (template) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _hydrateFrom(template);
        });
        // The post-frame callback flips `_hydrated` and the build
        // switches to the real form — this skeleton fills the gap.
        return const Padding(
          padding: EdgeInsets.all(16),
          child: KraTableSkeleton(),
        );
      },
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        // Sticky weightage indicator on top.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: WeightageIndicator(total: _totalWeightage),
        ),
        Expanded(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                if (_serverError != null) _ErrorBanner(message: _serverError!),
                BrandedTextField(
                  controller: _nameController,
                  label: AppStrings.kraTemplateFormName,
                  hint: AppStrings.kraTemplateFormNameHint,
                  prefixIcon: Icons.title_rounded,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? AppStrings.validationRequired
                      : null,
                ),
                const SizedBox(height: 14),
                _RoleDropdown(
                  value: _role,
                  roles: _roles,
                  onChanged: (v) {
                    setState(() {
                      _role = v;
                      _isDirty = true;
                    });
                  },
                ),
                const SizedBox(height: 14),
                BrandedTextField(
                  controller: _descriptionController,
                  label: AppStrings.kraTemplateFormDescription,
                  prefixIcon: Icons.description_outlined,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      AppStrings.kraTemplateFormItemsHeader,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '${_items.length} item${_items.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildItemsList(),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _addBlankItem,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text(AppStrings.kraTemplateFormAddItem),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryPurple,
                    side: BorderSide(
                      color: AppColors.primaryPurple
                          .withValues(alpha: 0.4),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                BrandedPrimaryButton(
                  label: AppStrings.commonSave,
                  onPressed: _canSubmit ? _submit : null,
                  isLoading: _isSubmitting,
                  icon: Icons.check_rounded,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemsList() {
    if (_items.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: const Text(
          AppStrings.kraTemplateFormItemsRequired,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    return ReorderableListView(
      shrinkWrap: true,
      buildDefaultDragHandles: false,
      physics: const NeverScrollableScrollPhysics(),
      onReorder: _reorder,
      children: [
        for (int i = 0; i < _items.length; i++)
          Padding(
            key: ValueKey(_itemControllers[i].id),
            padding: const EdgeInsets.only(bottom: 10),
            child: KraItemInputRow(
              index: i,
              item: _items[i],
              nameController: _itemControllers[i].name,
              descriptionController: _itemControllers[i].description,
              targetController: _itemControllers[i].target,
              trackingController: _itemControllers[i].tracking,
              weightageController: _itemControllers[i].weightage,
              onChanged: (item) => _onItemChanged(i, item),
              onDelete: () => _confirmDeleteItem(i),
            ),
          ),
      ],
    );
  }
}

/// Holds the five [TextEditingController]s for one row. We use a UUID-ish
/// id for ReorderableListView's per-row key so reorder operations don't
/// confuse Flutter into reusing the wrong row state.
class _ItemControllers {
  final String id;
  final TextEditingController name;
  final TextEditingController description;
  final TextEditingController target;
  final TextEditingController tracking;
  final TextEditingController weightage;

  _ItemControllers({
    required this.id,
    required this.name,
    required this.description,
    required this.target,
    required this.tracking,
    required this.weightage,
  });

  factory _ItemControllers.empty() {
    return _ItemControllers(
      id: UniqueKey().toString(),
      name: TextEditingController(),
      description: TextEditingController(),
      target: TextEditingController(),
      tracking: TextEditingController(),
      weightage: TextEditingController(),
    );
  }

  factory _ItemControllers.fromItem(KraTemplateItem item) {
    final w = item.weightagePercent;
    return _ItemControllers(
      id: item.id ?? UniqueKey().toString(),
      name: TextEditingController(text: item.name),
      description: TextEditingController(text: item.description ?? ''),
      target: TextEditingController(text: item.target ?? ''),
      tracking: TextEditingController(text: item.trackingMethod ?? ''),
      weightage: TextEditingController(
        text: w == 0 ? '' : (w == w.roundToDouble() ? w.toInt().toString() : w.toString()),
      ),
    );
  }

  void dispose() {
    name.dispose();
    description.dispose();
    target.dispose();
    tracking.dispose();
    weightage.dispose();
  }
}

class _RoleDropdown extends StatelessWidget {
  final String value;
  final List<String> roles;
  final ValueChanged<String> onChanged;
  const _RoleDropdown({
    required this.value,
    required this.roles,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // The backend stores template role as a free-form string, so a record
    // may arrive with a value the frontend hasn't enumerated yet. Merge it
    // in so DropdownButton's "exactly one matching item" assertion holds.
    final effectiveRoles = roles.contains(value) ? roles : [value, ...roles];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          AppStrings.kraTemplateFormRole,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        InputDecorator(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.work_outline_rounded, size: 20),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              items: [
                for (final r in effectiveRoles)
                  DropdownMenuItem(
                    value: r,
                    child: Text(_humanise(r)),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }

  String _humanise(String role) {
    // "WAREHOUSE_MGR" -> "Warehouse Mgr" so the dropdown reads naturally
    // regardless of which enum value the backend ships.
    return role
        .split('_')
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
        .join(' ');
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
