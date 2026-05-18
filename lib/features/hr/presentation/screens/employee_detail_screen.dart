import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
import '../../data/models/employee.dart';
import '../providers/employee_providers.dart';
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
          data: (employee) =>
              _DetailContent(employee: employee, ref: ref),
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
              valueColor: employee.isActive
                  ? AppColors.success
                  : AppColors.textMuted,
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (employee.isActive)
          OutlinedButton.icon(
            onPressed: () => _confirmDeactivate(context),
            icon: const Icon(Icons.person_off_outlined,
                color: AppColors.error),
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
  const _DetailCard({required this.title, required this.rows});

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
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 0.6,
            ),
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
