import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
import '../providers/employee_providers.dart';
import '../widgets/confirm_action_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/employee_list_tile.dart';
import '../widgets/search_bar_filter.dart';

/// Paginated, searchable, filterable employees list.
///
/// Wires up:
///   • search debounce (handled by [employeeFilterProvider])
///   • role filter chip
///   • infinite scroll (loads next page when within 200px of the end)
///   • pull-to-refresh
///   • shimmer skeletons on first load
///   • empty state + CTA
///   • optimistic deactivate via the controller
class EmployeesScreen extends ConsumerStatefulWidget {
  const EmployeesScreen({super.key});

  @override
  ConsumerState<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends ConsumerState<EmployeesScreen> {
  late final ScrollController _scrollController;

  static const _availableRoles = [
    'EMPLOYEE',
    'MANAGER',
    'OPS',
    'HR',
    'HR_ADMIN',
    'FINANCE',
    'BD_MANAGER',
    'WAREHOUSE_MGR',
  ];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _maybeLoadMore();
    }
  }

  Future<void> _maybeLoadMore() async {
    try {
      await ref.read(employeeListProvider.notifier).loadMore();
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(AppStrings.employeesLoadMoreFailed),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(employeeListProvider);
    final filter = ref.watch(employeeFilterProvider);
    final filterCtrl = ref.read(employeeFilterProvider.notifier);

    final isSearching = filter.search.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.employeesTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        onPressed: () => context.push(AppRoutes.hrEmployeeNew),
        icon: const Icon(Icons.add_rounded),
        label: const Text(AppStrings.commonAdd),
      ),
      body: Column(
        children: [
          SearchBarFilter(
            hint: AppStrings.employeesSearchHint,
            initialValue: filter.search,
            onChanged: filterCtrl.setSearch,
            trailing: [
              _RoleFilterChip(
                value: filter.role,
                roles: _availableRoles,
                onChanged: filterCtrl.setRole,
              ),
              _ActiveFilterChip(
                value: filter.isActive,
                onChanged: filterCtrl.setActive,
              ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primaryPurple,
              onRefresh: () async {
                await ref.read(employeeListProvider.notifier).refresh();
              },
              child: _buildBody(state, isSearching),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(EmployeeListState state, bool isSearching) {
    if (state.isInitialLoading) return const _LoadingList();

    if (state.error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          EmptyState(
            icon: Icons.error_outline_rounded,
            title: AppStrings.errorGeneric,
            message: state.error!,
            actionLabel: AppStrings.commonRetry,
            onAction: () =>
                ref.read(employeeListProvider.notifier).refresh(),
          ),
        ],
      );
    }

    if (state.employees.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 60),
          EmptyState(
            icon: isSearching
                ? Icons.search_off_rounded
                : Icons.groups_outlined,
            title: isSearching
                ? AppStrings.employeesNoSearchResults
                : AppStrings.employeesEmptyTitle,
            message: isSearching
                ? AppStrings.employeesNoSearchHint
                : AppStrings.employeesEmptyMessage,
            actionLabel:
                isSearching ? null : AppStrings.employeesEmptyCta,
            onAction: isSearching
                ? null
                : () => context.push(AppRoutes.hrEmployeeNew),
          ),
        ],
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: state.employees.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= state.employees.length) {
          return const _LoadMoreTile();
        }
        final employee = state.employees[index];
        return EmployeeListTile(
          employee: employee,
          onTap: () =>
              context.push(AppRoutes.hrEmployeeDetail(employee.id)),
          onEdit: () => context.push(AppRoutes.hrEmployeeEdit(employee.id)),
          onDeactivate: () => _confirmDeactivate(employee.id),
        );
      },
    );
  }

  Future<void> _confirmDeactivate(String employeeId) async {
    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.employeesDeactivateConfirmTitle,
      message: AppStrings.employeesDeactivateConfirmMessage,
      confirmLabel: AppStrings.employeesActionDeactivate,
    );
    if (ok != true || !mounted) return;
    final success = await ref
        .read(employeeListProvider.notifier)
        .deactivateOptimistic(employeeId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? AppStrings.employeesDeactivateSuccess
              : AppStrings.employeesDeactivateFailed,
        ),
        backgroundColor:
            success ? AppColors.textPrimary : AppColors.error,
      ),
    );
  }
}

class _RoleFilterChip extends StatelessWidget {
  final String? value;
  final List<String> roles;
  final ValueChanged<String?> onChanged;

  const _RoleFilterChip({
    required this.value,
    required this.roles,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String?>(
      tooltip: 'Filter by role',
      onSelected: onChanged,
      itemBuilder: (_) => [
        const PopupMenuItem(value: null, child: Text(AppStrings.commonAll)),
        ...roles.map(
          (r) => PopupMenuItem(value: r, child: Text(_humanRole(r))),
        ),
      ],
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tune_rounded,
                color: AppColors.textSecondary, size: 18),
            const SizedBox(width: 6),
            Text(
              value == null
                  ? AppStrings.employeesFilterAll
                  : _humanRole(value!),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _humanRole(String r) {
    final lower = r.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }
}

class _ActiveFilterChip extends StatelessWidget {
  final bool? value;
  final ValueChanged<bool?> onChanged;

  const _ActiveFilterChip({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<bool?>(
      tooltip: 'Filter by status',
      onSelected: onChanged,
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: null,
          child: Text(AppStrings.employeesFilterStatusAll),
        ),
        PopupMenuItem(
          value: true,
          child: Text(AppStrings.employeesFilterStatusActive),
        ),
        PopupMenuItem(
          value: false,
          child: Text(AppStrings.employeesFilterStatusInactive),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value == false
                  ? Icons.toggle_off_outlined
                  : Icons.toggle_on_outlined,
              color: AppColors.textSecondary,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              _label(value),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _label(bool? v) {
    if (v == null) return AppStrings.employeesFilterStatusAll;
    return v
        ? AppStrings.employeesFilterStatusActive
        : AppStrings.employeesFilterStatusInactive;
  }
}

class _LoadMoreTile extends StatelessWidget {
  const _LoadMoreTile();

  @override
  Widget build(BuildContext context) {
    // Lightweight inline shimmer matches the row above so the list does
    // not visually jump as the next page resolves.
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: ListItemSkeleton(),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 8,
      itemBuilder: (_, __) => const ListItemSkeleton(),
    );
  }
}
