import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
import '../../data/models/employee.dart';
import '../../data/models/kra_template.dart';
import '../../data/models/review_cycle.dart';
import '../providers/employee_providers.dart';
import '../providers/kra_assignment_providers.dart';
import '../providers/kra_template_providers.dart';
import '../providers/review_cycle_providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/kra_template_card.dart';
import '../widgets/weightage_indicator.dart';

/// 3-step KRA assignment wizard:
///   1. Pick employees (multi-select with search)
///   2. Pick template (filtered list)
///   3. Review & confirm (cycle picker + summary)
///
/// State is held in [_AssignWizardState] so step transitions don't
/// re-fetch data. Bulk-assign happens on the final step's confirm tap.
class KraAssignScreen extends ConsumerStatefulWidget {
  const KraAssignScreen({super.key});

  @override
  ConsumerState<KraAssignScreen> createState() => _KraAssignScreenState();
}

class _KraAssignScreenState extends ConsumerState<KraAssignScreen> {
  int _step = 0;

  final Set<String> _selectedEmployeeIds = {};
  String _employeeSearch = '';
  KraTemplate? _selectedTemplate;
  ReviewCycle? _selectedCycle;
  bool _isSubmitting = false;
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
          onSelect: (t) => setState(() => _selectedTemplate = t),
        );
      case 2:
        return _Step3Review(
          key: const ValueKey('step3'),
          selectedEmployeeCount: _selectedEmployeeIds.length,
          selectedTemplate: _selectedTemplate!,
          selectedCycle: _selectedCycle,
          onCycleSelected: (c) => setState(() => _selectedCycle = c),
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
        return _selectedTemplate != null &&
            _selectedTemplate!.hasValidWeightage;
      case 2:
        return _selectedCycle != null && !_isSubmitting;
      default:
        return false;
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
                          valueColor:
                              AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : Icon(
                        isLast
                            ? Icons.check_rounded
                            : Icons.arrow_forward_rounded,
                      ),
                label: Text(
                  isLast
                      ? AppStrings.commonConfirm
                      : AppStrings.commonNext,
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
      await ref.read(kraAssignmentActionsProvider).bulkAssign(
            employeeIds: _selectedEmployeeIds.toList(),
            cycleId: _selectedCycle!.id,
            templateId: _selectedTemplate!.id,
          );
      if (!mounted) return;
      final count = _selectedEmployeeIds.length;
      final msg = count == 1
          ? AppStrings.kraAssignSuccessOne
          : AppStrings.kraAssignSuccessMany.replaceAll(
              '{count}', count.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
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
    final color = completed || active
        ? AppColors.primaryPurple
        : AppColors.textMuted;
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
              ? const Icon(Icons.check_rounded,
                  color: Colors.white, size: 16)
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
                          e.email
                              .toLowerCase()
                              .contains(search.toLowerCase()))
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
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
  final ValueChanged<KraTemplate?> onSelect;
  const _Step2Template({
    super.key,
    required this.selected,
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
                  return _TemplateOptionTile(
                    template: tpl,
                    selected: selected?.id == tpl.id,
                    onTap: () =>
                        onSelect(selected?.id == tpl.id ? null : tpl),
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
  final VoidCallback onTap;
  const _TemplateOptionTile({
    required this.template,
    required this.selected,
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
              child: const Icon(
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

class _Step3Review extends ConsumerWidget {
  final int selectedEmployeeCount;
  final KraTemplate selectedTemplate;
  final ReviewCycle? selectedCycle;
  final ValueChanged<ReviewCycle?> onCycleSelected;
  final String? serverError;

  const _Step3Review({
    super.key,
    required this.selectedEmployeeCount,
    required this.selectedTemplate,
    required this.selectedCycle,
    required this.onCycleSelected,
    required this.serverError,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cycles = ref.watch(reviewCyclesProvider);
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
        const SizedBox(height: 16),
        const Text(
          AppStrings.kraAssignSelectCycle,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 8),
        cycles.when(
          loading: () => const SizedBox(
            height: 56,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: ShimmerBox(height: 24, borderRadius: 8),
            ),
          ),
          error: (e, _) => Text(
            e.toString(),
            style: const TextStyle(color: AppColors.error),
          ),
          data: (list) {
            final eligible = list
                .where(
                  (c) =>
                      c.status == ReviewCycleStatus.active ||
                      c.status == ReviewCycleStatus.draft,
                )
                .toList();
            if (eligible.isEmpty) {
              return const EmptyState(
                icon: Icons.event_busy_rounded,
                title: AppStrings.kraAssignNoCycle,
                message: AppStrings.reviewCyclesEmptyMessage,
                compact: true,
              );
            }
            return Column(
              children: eligible
                  .map((c) => _CycleOptionTile(
                        cycle: c,
                        selected: selectedCycle?.id == c.id,
                        onTap: () => onCycleSelected(
                          selectedCycle?.id == c.id ? null : c,
                        ),
                      ))
                  .toList(),
            );
          },
        ),
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

class _CycleOptionTile extends StatelessWidget {
  final ReviewCycle cycle;
  final bool selected;
  final VoidCallback onTap;
  const _CycleOptionTile({
    required this.cycle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryPurple.withValues(alpha: 0.06)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppColors.primaryPurple
                  : AppColors.divider,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              // Custom radio indicator — Material's Radio<T> requires a
              // RadioGroup ancestor on Flutter 3.32+, but a hand-rolled
              // dot is simpler and works on every supported SDK.
              _RadioDot(selected: selected),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cycle.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cycle.status.displayName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
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

class _RadioDot extends StatelessWidget {
  final bool selected;
  const _RadioDot({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.primaryPurple : AppColors.textMuted,
          width: 2,
        ),
      ),
      child: selected
          ? Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryPurple,
              ),
            )
          : null,
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
