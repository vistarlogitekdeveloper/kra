import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
import '../../data/models/bulk_assign_result.dart';
import '../../data/models/employee.dart';
import '../../data/models/kra_template.dart';
import '../providers/employee_providers.dart';
import '../providers/kra_assignment_providers.dart';
import '../providers/kra_template_providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/kra_template_card.dart';
import '../widgets/weightage_indicator.dart';

/// 3-step KRA assignment wizard:
///   1. Pick employees (multi-select with search)
///   2. Pick template (filtered list)
///   3. Review & confirm
///
/// Assignment is per-employee (monthly reviews are generated from the
/// assigned template each month) — there is no review-cycle to pick.
///
/// State is held in [_AssignWizardState] so step transitions don't
/// re-fetch data. Bulk-assign happens on the final step's confirm tap.
class KraAssignScreen extends ConsumerStatefulWidget {
  /// Optional employee id to pre-select on entering the wizard —
  /// pushed in by the employee-detail "Assign KRA" CTA so the user
  /// doesn't have to search/select the same person twice.
  final String? preselectEmployeeId;

  const KraAssignScreen({super.key, this.preselectEmployeeId});

  @override
  ConsumerState<KraAssignScreen> createState() => _KraAssignScreenState();
}

class _KraAssignScreenState extends ConsumerState<KraAssignScreen> {
  int _step = 0;

  final Set<String> _selectedEmployeeIds = {};

  @override
  void initState() {
    super.initState();
    final id = widget.preselectEmployeeId;
    if (id != null && id.isNotEmpty) {
      _selectedEmployeeIds.add(id);
    }
  }

  String _employeeSearch = '';
  KraTemplate? _selectedTemplate;
  bool _isSubmitting = false;
  bool _isLoadingTemplate = false;
  String? _serverError;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.kraAssignTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: _step == 0
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() => _step -= 1),
              ),
      ),
      body: Column(
        children: [
          _StepIndicator(activeStep: _step),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _buildStep(),
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _Step1Employees(
          key: const ValueKey('step1'),
          search: _employeeSearch,
          onSearchChanged: (v) => setState(() => _employeeSearch = v),
          selectedIds: _selectedEmployeeIds,
          onToggle: (id) => setState(() {
            if (_selectedEmployeeIds.contains(id)) {
              _selectedEmployeeIds.remove(id);
            } else {
              _selectedEmployeeIds.add(id);
            }
          }),
        );
      case 1:
        return _Step2Template(
          key: const ValueKey('step2'),
          selected: _selectedTemplate,
          isLoading: _isLoadingTemplate,
          onSelect: _onPickTemplate,
        );
      case 2:
        return _Step3Review(
          key: const ValueKey('step3'),
          selectedEmployeeCount: _selectedEmployeeIds.length,
          selectedTemplate: _selectedTemplate!,
          serverError: _serverError,
        );
      default:
        return const SizedBox();
    }
  }

  bool get _canAdvance {
    switch (_step) {
      case 0:
        return _selectedEmployeeIds.isNotEmpty;
      case 1:
        // The templates LIST endpoint returns no items[] — only a count —
        // so a freshly-tapped template can't be validated until we hydrate
        // it via getById. _onPickTemplate does that; until it resolves we
        // hold the Next button disabled.
        return !_isLoadingTemplate &&
            _selectedTemplate != null &&
            _selectedTemplate!.hasWeightageData &&
            _selectedTemplate!.hasValidWeightage;
      case 2:
        return !_isSubmitting;
      default:
        return false;
    }
  }

  /// Hydrates the tapped template before advancing. The list endpoint
  /// strips `items[]` (only `_count.items` survives) so we need a getById
  /// round-trip to populate weightages, otherwise both the Next-button
  /// gate and the step-3 summary read zero items and zero weightage.
  Future<void> _onPickTemplate(KraTemplate? tpl) async {
    if (tpl == null) {
      setState(() => _selectedTemplate = null);
      return;
    }
    // Already hydrated by a previous tap in this session — no need to
    // refetch, the model carries items[] already.
    if (_selectedTemplate?.id == tpl.id &&
        _selectedTemplate!.hasWeightageData) {
      return;
    }
    setState(() {
      _selectedTemplate = tpl;
      _isLoadingTemplate = true;
    });
    try {
      final full =
          await ref.read(kraTemplateRepositoryProvider).getById(tpl.id);
      if (!mounted || _selectedTemplate?.id != tpl.id) return;
      setState(() {
        _selectedTemplate = full;
        _isLoadingTemplate = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingTemplate = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.combinedMessage)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingTemplate = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.errorGeneric)),
      );
    }
  }

  Widget _buildBottomBar() {
    final isLast = _step == 2;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(
              color: AppColors.divider.withValues(alpha: 0.6),
            ),
          ),
        ),
        child: Row(
          children: [
            if (_step > 0) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _step -= 1),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.divider),
                    foregroundColor: AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    AppStrings.commonBack,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _canAdvance
                    ? () => isLast ? _confirm() : setState(() => _step += 1)
                    : null,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : Icon(
                        isLast
                            ? Icons.check_rounded
                            : Icons.arrow_forward_rounded,
                      ),
                label: Text(
                  isLast ? AppStrings.commonConfirm : AppStrings.commonNext,
                  style: const TextStyle(fontWeight: FontWeight.w800),
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
          ],
        ),
      ),
    );
  }

  Future<void> _confirm() async {
    setState(() {
      _isSubmitting = true;
      _serverError = null;
    });
    try {
      final result = await ref.read(kraAssignmentActionsProvider).bulkAssign(
            employeeIds: _selectedEmployeeIds.toList(),
            templateId: _selectedTemplate!.id,
          );
      if (!mounted) return;
      // Backend is idempotent: employees who already have this template
      // come back under `skippedEmployeeIds`. Surface that honestly
      // instead of pretending we created N rows.
      final msg = _formatBulkResultMessage(result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      context.pop();
    } on ApiError catch (e) {
      setState(() => _serverError = e.combinedMessage);
    } catch (_) {
      setState(() => _serverError = AppStrings.errorGeneric);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _formatBulkResultMessage(BulkAssignResult result) {
    final created = result.createdCount;
    final skipped = result.skippedCount;
    if (created == 0 && skipped > 0) {
      return skipped == 1
          ? 'This employee already has this template.'
          : 'All $skipped employees already had this template.';
    }
    if (skipped == 0) {
      return created == 1
          ? AppStrings.kraAssignSuccessOne
          : AppStrings.kraAssignSuccessMany
              .replaceAll('{count}', created.toString());
    }
    return 'Assigned to $created employee${created == 1 ? '' : 's'} '
        '($skipped already had it).';
  }
}

// ───── Step indicator at the top of the wizard ─────

class _StepIndicator extends StatelessWidget {
  final int activeStep;
  const _StepIndicator({required this.activeStep});

  static const _labels = [
    AppStrings.kraAssignStep1,
    AppStrings.kraAssignStep2,
    AppStrings.kraAssignStep3,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      color: AppColors.surface,
      child: Row(
        children: [
          for (int i = 0; i < _labels.length; i++) ...[
            _StepDot(
              index: i + 1,
              label: _labels[i],
              active: i == activeStep,
              completed: i < activeStep,
            ),
            if (i != _labels.length - 1)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: i < activeStep
                      ? AppColors.primaryPurple
                      : AppColors.divider,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final int index;
  final String label;
  final bool active;
  final bool completed;

  const _StepDot({
    required this.index,
    required this.label,
    required this.active,
    required this.completed,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        completed || active ? AppColors.primaryPurple : AppColors.textMuted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: completed || active
                ? AppColors.primaryPurple
                : AppColors.background,
            border: Border.all(color: color, width: 1.5),
          ),
          child: completed
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
              : Text(
                  '$index',
                  style: TextStyle(
                    color: active ? Colors.white : color,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ───── Step 1: pick employees ─────

class _Step1Employees extends ConsumerWidget {
  final String search;
  final ValueChanged<String> onSearchChanged;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;

  const _Step1Employees({
    super.key,
    required this.search,
    required this.onSearchChanged,
    required this.selectedIds,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employees = ref.watch(allEmployeesProvider);
    return Column(
      children: [
        const _StepHeader(text: AppStrings.kraAssignStep1Hint),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            decoration: InputDecoration(
              hintText: AppStrings.employeesSearchHint,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
            ),
            onChanged: onSearchChanged,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: employees.when(
            loading: () => ListView.builder(
              itemCount: 8,
              itemBuilder: (_, __) => const ListItemSkeleton(),
            ),
            error: (e, _) => Center(
              child: Text(
                e.toString(),
                style: const TextStyle(color: AppColors.error),
              ),
            ),
            data: (list) {
              final filtered = search.isEmpty
                  ? list
                  : list
                      .where((e) =>
                          e.fullName
                              .toLowerCase()
                              .contains(search.toLowerCase()) ||
                          e.employeeCode
                              .toLowerCase()
                              .contains(search.toLowerCase()) ||
                          e.email.toLowerCase().contains(search.toLowerCase()))
                      .toList();
              if (filtered.isEmpty) {
                return const EmptyState(
                  icon: Icons.search_off_rounded,
                  title: AppStrings.employeesNoSearchResults,
                  message: AppStrings.employeesNoSearchHint,
                );
              }
              return ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: filtered.length,
                itemBuilder: (_, i) => _EmployeeSelectTile(
                  employee: filtered[i],
                  selected: selectedIds.contains(filtered[i].id),
                  onTap: () => onToggle(filtered[i].id),
                ),
              );
            },
          ),
        ),
        if (selectedIds.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            color: AppColors.primaryPurple.withValues(alpha: 0.06),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.primaryPurple, size: 16),
                const SizedBox(width: 6),
                Text(
                  '${selectedIds.length} selected',
                  style: const TextStyle(
                    color: AppColors.primaryPurple,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EmployeeSelectTile extends StatelessWidget {
  final Employee employee;
  final bool selected;
  final VoidCallback onTap;
  const _EmployeeSelectTile({
    required this.employee,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primaryPurple.withValues(alpha: 0.08)
          : AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.divider),
            ),
          ),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: (_) => onTap(),
                activeColor: AppColors.primaryPurple,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.fullName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${employee.employeeCode} · ${employee.email}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───── Step 2: pick template ─────

class _Step2Template extends ConsumerWidget {
  final KraTemplate? selected;
  final bool isLoading;
  final ValueChanged<KraTemplate?> onSelect;
  const _Step2Template({
    super.key,
    required this.selected,
    required this.isLoading,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(kraTemplatesProvider);
    return Column(
      children: [
        const _StepHeader(text: AppStrings.kraAssignStep2Hint),
        Expanded(
          child: templates.when(
            loading: () => ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                KraTableSkeleton(),
                SizedBox(height: 14),
                KraTableSkeleton(),
              ],
            ),
            error: (e, _) => Center(
              child: Text(
                e.toString(),
                style: const TextStyle(color: AppColors.error),
              ),
            ),
            data: (list) {
              if (list.isEmpty) {
                return const EmptyState(
                  icon: Icons.description_outlined,
                  title: AppStrings.kraAssignNoTemplate,
                  message: AppStrings.kraTemplatesEmptyMessage,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final tpl = list[i];
                  final isSelected = selected?.id == tpl.id;
                  return _TemplateOptionTile(
                    template: tpl,
                    selected: isSelected,
                    isLoading: isSelected && isLoading,
                    onTap: () => onSelect(isSelected ? null : tpl),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TemplateOptionTile extends StatelessWidget {
  final KraTemplate template;
  final bool selected;
  final bool isLoading;
  final VoidCallback onTap;
  const _TemplateOptionTile({
    required this.template,
    required this.selected,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        KraTemplateCard(template: template, onTap: onTap),
        if (selected)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppColors.primaryPurple,
                shape: BoxShape.circle,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
            ),
          ),
      ],
    );
  }
}

// ───── Step 3: review & confirm ─────

class _Step3Review extends StatelessWidget {
  final int selectedEmployeeCount;
  final KraTemplate selectedTemplate;
  final String? serverError;

  const _Step3Review({
    super.key,
    required this.selectedEmployeeCount,
    required this.selectedTemplate,
    required this.serverError,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _StepHeader(text: AppStrings.kraAssignStep3Hint),
        if (serverError != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.error.withValues(alpha: 0.30),
              ),
            ),
            child: Text(
              serverError!,
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _SummaryCard(
          children: [
            _SummaryRow(
              icon: Icons.groups_rounded,
              label: 'Employees',
              value: '$selectedEmployeeCount selected',
            ),
            _SummaryRow(
              icon: Icons.description_rounded,
              label: 'Template',
              value: selectedTemplate.name,
            ),
            _SummaryRow(
              icon: Icons.format_list_numbered_rounded,
              label: 'KRAs',
              value: '${selectedTemplate.items.length} items',
            ),
          ],
        ),
        const SizedBox(height: 12),
        WeightageIndicator(total: selectedTemplate.totalWeightage),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final List<Widget> children;
  const _SummaryCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(children: children),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primaryPurple),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  final String text;
  const _StepHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
          height: 1.4,
        ),
      ),
    );
  }
}
