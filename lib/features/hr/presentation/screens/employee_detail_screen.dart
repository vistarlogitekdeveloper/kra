import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
import '../../data/models/employee.dart';
import '../../data/models/kra_assignment.dart';
import '../providers/employee_providers.dart';
import '../providers/kra_assignment_providers.dart';
import '../widgets/_formatters.dart';
import '../widgets/confirm_action_dialog.dart';
import '../widgets/empty_state.dart';

/// Read-only profile screen for an employee. Pulls from
/// [employeeDetailProvider] keyed on the path id, with a shimmer
/// skeleton while loading.
class EmployeeDetailScreen extends ConsumerWidget {
  final String employeeId;
  const EmployeeDetailScreen({super.key, required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(employeeDetailProvider(employeeId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.employeeDetailTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          if (detail.value != null)
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              tooltip: AppStrings.commonEdit,
              onPressed: () =>
                  context.push(AppRoutes.hrEmployeeEdit(employeeId)),
            ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primaryPurple,
        onRefresh: () async {
          ref.invalidate(employeeDetailProvider(employeeId));
          await ref.read(employeeDetailProvider(employeeId).future);
        },
        child: detail.when(
          loading: () => const _DetailSkeleton(),
          error: (e, _) => ListView(
            padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
            children: [
              EmptyState(
                icon: Icons.error_outline_rounded,
                title: AppStrings.errorGeneric,
                message: e.toString(),
                actionLabel: AppStrings.commonRetry,
                onAction: () =>
                    ref.invalidate(employeeDetailProvider(employeeId)),
              ),
            ],
          ),
          data: (employee) => _DetailContent(employee: employee, ref: ref),
        ),
      ),
    );
  }
}

class _DetailContent extends StatelessWidget {
  final Employee employee;
  final WidgetRef ref;
  const _DetailContent({required this.employee, required this.ref});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        _ProfileHeader(employee: employee),
        const SizedBox(height: 20),
        _DetailCard(
          title: 'Contact',
          rows: [
            _DetailRow(label: 'Email', value: employee.email),
            _DetailRow(
              label: 'Employee Code',
              value: employee.employeeCode,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _KraAssignmentsSection(employeeId: employee.id),
        const SizedBox(height: 14),
        _DetailCard(
          title: 'Employment',
          rows: [
            _DetailRow(
              label: 'Role',
              value: _humanRole(employee.role),
            ),
            _DetailRow(
              label: 'Department',
              value: employee.department ?? '—',
            ),
            _DetailRow(
              label: 'Location',
              value: employee.projectLocation ?? '—',
            ),
            _DetailRow(label: 'Grade', value: employee.grade ?? '—'),
            _DetailRow(
              label: 'Manager',
              value: employee.managerName ?? '—',
            ),
            _DetailRow(
              label: 'Joined',
              value: HrFormatters.dateOrDash(employee.joinedDate),
            ),
            _DetailRow(
              label: 'Status',
              value: employee.isActive
                  ? AppStrings.employeesActive
                  : AppStrings.employeesInactive,
              valueColor:
                  employee.isActive ? AppColors.success : AppColors.textMuted,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _DetailCard(
          title: AppStrings.employeeDetailIncentiveTitle,
          actionLabel: employee.monthlyIncentiveAmount == null
              ? AppStrings.employeeIncentiveSetCta
              : AppStrings.employeeIncentiveEditCta,
          onAction: () => _AssignIncentiveSheet.show(context, ref, employee),
          rows: [
            _DetailRow(
              label: AppStrings.employeeDetailMonthlyIncentive,
              value: employee.monthlyIncentiveAmount == null
                  ? AppStrings.employeeDetailIncentiveNotSet
                  : HrFormatters.currencyInr(employee.monthlyIncentiveAmount!),
              valueColor: employee.monthlyIncentiveAmount == null
                  ? AppColors.textMuted
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => context.push(
                  '${AppRoutes.hrAssign}?employeeId=${employee.id}',
                ),
                icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
                label: const Text(
                  AppStrings.employeeDetailAssignKra,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    context.push(AppRoutes.hrEmployeeEdit(employee.id)),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text(
                  AppStrings.employeeDetailEditProfile,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.divider),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (employee.isActive)
          OutlinedButton.icon(
            onPressed: () => _confirmDeactivate(context),
            icon: const Icon(Icons.person_off_outlined, color: AppColors.error),
            label: const Text(
              AppStrings.employeesActionDeactivate,
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: AppColors.error.withValues(alpha: 0.5),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
      ],
    );
  }

  String _humanRole(String r) {
    if (r.isEmpty) return r;
    final lower = r.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }

  Future<void> _confirmDeactivate(BuildContext context) async {
    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.employeesDeactivateConfirmTitle,
      message: AppStrings.employeesDeactivateConfirmMessage,
      confirmLabel: AppStrings.employeesActionDeactivate,
    );
    if (ok != true || !context.mounted) return;
    final success = await ref
        .read(employeeListProvider.notifier)
        .deactivateOptimistic(employee.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? AppStrings.employeesDeactivateSuccess
              : AppStrings.employeesDeactivateFailed,
        ),
      ),
    );
    if (success) {
      ref.invalidate(employeeDetailProvider(employee.id));
      if (context.mounted) context.pop();
    }
  }
}

/// Lists every KRA assignment for the given employee — one card per
/// (cycle, template) pair. Refreshes automatically after the Assign-KRA
/// wizard's bulkAssign call invalidates `kraAssignmentsProvider`.
class _KraAssignmentsSection extends ConsumerWidget {
  final String employeeId;
  const _KraAssignmentsSection({required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignmentsAsync = ref.watch(
      kraAssignmentsProvider(KraAssignmentFilter(employeeId: employeeId)),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
              const Text(
                'KRA Assignments',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              assignmentsAsync.when(
                data: (list) => Text(
                  list.isEmpty ? '—' : '${list.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryPurple,
                  ),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          assignmentsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: ShimmerBox(height: 60, borderRadius: 12),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                e.toString(),
                style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 12.5,
                ),
              ),
            ),
            data: (list) {
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.assignment_outlined,
                        size: 18,
                        color: AppColors.textMuted.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'No KRAs assigned yet. Use the Assign KRA action below.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
              // Newest first — the live API doesn't guarantee order.
              final sorted = [...list]..sort((a, b) {
                  final aDate = a.createdAt ?? DateTime(1970);
                  final bDate = b.createdAt ?? DateTime(1970);
                  return bDate.compareTo(aDate);
                });
              return Column(
                children: [
                  for (final a in sorted) _AssignmentRow(assignment: a),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AssignmentRow extends StatelessWidget {
  final KraAssignment assignment;
  const _AssignmentRow({required this.assignment});

  @override
  Widget build(BuildContext context) {
    final cycleLabel = assignment.cycleName ?? assignment.cycleId;
    final templateLabel = assignment.templateName ?? 'Custom KRAs';
    final itemCount = assignment.items.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryPurple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.assignment_turned_in_outlined,
              size: 18,
              color: AppColors.primaryPurple,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cycleLabel,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$templateLabel · $itemCount KRA${itemCount == 1 ? '' : 's'}',
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
          if (assignment.isLocked)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.textMuted.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_rounded,
                      size: 11, color: AppColors.textMuted),
                  SizedBox(width: 4),
                  Text(
                    'Locked',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final Employee employee;
  const _ProfileHeader({required this.employee});

  @override
  Widget build(BuildContext context) {
    final initials = _initials(employee.fullName);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryPurple.withValues(alpha: 0.06),
            AppColors.accentOrange.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primaryPurple,
                  AppColors.primaryPurpleLight,
                ],
              ),
            ),
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employee.fullName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  employee.email,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String full) {
    final parts = full.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}

class _DetailCard extends StatelessWidget {
  final String title;
  final List<_DetailRow> rows;

  /// Optional header action (e.g. "Set" / "Edit"). Renders a text button
  /// on the right of the card title when both are provided.
  final String? actionLabel;
  final VoidCallback? onAction;

  const _DetailCard({
    required this.title,
    required this.rows,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
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
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              if (actionLabel != null && onAction != null)
                GestureDetector(
                  onTap: onAction,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.edit_rounded,
                        size: 14,
                        color: AppColors.primaryPurple,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        actionLabel!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryPurple,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (final row in rows) row,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: const [
        ProfileHeaderSkeleton(),
        SizedBox(height: 8),
        ShimmerBox(height: 200, borderRadius: 16),
        SizedBox(height: 14),
        ShimmerBox(height: 280, borderRadius: 16),
      ],
    );
  }
}

/// Quick "assign performance incentive" bottom sheet, opened from the
/// employee detail screen. PATCHes the employee's monthly incentive
/// without going through the full edit form. An empty field clears the
/// override (the employee falls back to the org default).
class _AssignIncentiveSheet extends ConsumerStatefulWidget {
  final Employee employee;
  const _AssignIncentiveSheet({required this.employee});

  static Future<void> show(
    BuildContext context,
    WidgetRef ref,
    Employee employee,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AssignIncentiveSheet(employee: employee),
    );
  }

  @override
  ConsumerState<_AssignIncentiveSheet> createState() =>
      _AssignIncentiveSheetState();
}

class _AssignIncentiveSheetState extends ConsumerState<_AssignIncentiveSheet> {
  late final TextEditingController _controller;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = widget.employee.monthlyIncentiveAmount;
    _controller = TextEditingController(
      text: current == null ? '' : current.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    final amount = text.isEmpty ? null : double.tryParse(text);
    if (text.isNotEmpty && (amount == null || amount < 0)) {
      setState(() => _error = AppStrings.validationNumberRequired);
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final updated = await ref.read(employeeRepositoryProvider).update(
        widget.employee.id,
        {'monthlyIncentiveAmount': amount},
      );
      ref.read(employeeListProvider.notifier).replaceUpdated(updated);
      ref.invalidate(employeeDetailProvider(updated.id));
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.employeeIncentiveSaved)),
      );
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = AppStrings.errorGeneric);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
            const Text(
              AppStrings.employeeIncentiveSheetTitle,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.employee.fullName,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
              const SizedBox(height: 12),
            ],
            const Text(
              AppStrings.employeeFormMonthlyIncentive,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^\d{0,9}(\.\d{0,2})?'),
                ),
              ],
              onSubmitted: (_) => _isSubmitting ? null : _save(),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.currency_rupee_rounded, size: 18),
                hintText: AppStrings.employeeFormMonthlyIncentiveHint,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                if (widget.employee.monthlyIncentiveAmount != null)
                  TextButton(
                    onPressed: _isSubmitting
                        ? null
                        : () {
                            _controller.clear();
                            _save();
                          },
                    child: const Text(
                      AppStrings.employeeIncentiveClear,
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _isSubmitting ? null : _save,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: const Text(
                    AppStrings.commonSave,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
