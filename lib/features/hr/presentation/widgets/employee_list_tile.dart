import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../data/models/employee.dart';

/// Row in the Employees screen list. Avatar = initials in a brand-tinted
/// circle, plus a status pill on the right that reflects [Employee.isActive].
class EmployeeListTile extends StatelessWidget {
  final Employee employee;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDeactivate;

  const EmployeeListTile({
    super.key,
    required this.employee,
    this.onTap,
    this.onEdit,
    this.onDeactivate,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.divider, width: 1),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Avatar(name: employee.fullName, isActive: employee.isActive),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _subtitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _ActivePill(isActive: employee.isActive),
              if (onEdit != null || onDeactivate != null) ...[
                const SizedBox(width: 4),
                _OverflowMenu(
                  onEdit: onEdit,
                  onDeactivate: employee.isActive ? onDeactivate : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    final code = employee.employeeCode.trim();
    final role = employee.role.trim();
    final dept = employee.department?.trim();
    return [
      if (code.isNotEmpty) code,
      if (role.isNotEmpty) _humanRole(role),
      if (dept != null && dept.isNotEmpty) dept,
    ].join(' · ');
  }

  // The role on the wire is uppercase ("EMPLOYEE", "MANAGER"); render
  // capitalised for the list subtitle.
  String _humanRole(String raw) {
    if (raw.isEmpty) return raw;
    final lower = raw.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final bool isActive;
  const _Avatar({required this.name, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final initials = _initialsFor(name);
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isActive
              ? [
                  AppColors.primaryPurple.withValues(alpha: 0.15),
                  AppColors.accentOrange.withValues(alpha: 0.15),
                ]
              : [
                  AppColors.divider,
                  AppColors.divider,
                ],
        ),
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: isActive ? AppColors.primaryPurple : AppColors.textMuted,
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    );
  }

  String _initialsFor(String full) {
    final parts = full.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}

class _ActivePill extends StatelessWidget {
  final bool isActive;
  const _ActivePill({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.success : AppColors.textMuted;
    final bg = isActive
        ? AppColors.success.withValues(alpha: 0.10)
        : AppColors.divider;
    final label = isActive
        ? AppStrings.employeesActive
        : AppStrings.employeesInactive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  final VoidCallback? onEdit;
  final VoidCallback? onDeactivate;
  const _OverflowMenu({this.onEdit, this.onDeactivate});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(
        Icons.more_vert_rounded,
        color: AppColors.textSecondary,
        size: 20,
      ),
      onSelected: (value) {
        if (value == 'edit' && onEdit != null) onEdit!();
        if (value == 'deactivate' && onDeactivate != null) onDeactivate!();
      },
      itemBuilder: (context) => [
        if (onEdit != null)
          const PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 18),
                SizedBox(width: 10),
                Text(AppStrings.employeesActionEdit),
              ],
            ),
          ),
        if (onDeactivate != null)
          const PopupMenuItem(
            value: 'deactivate',
            child: Row(
              children: [
                Icon(Icons.delete_outline_rounded,
                    size: 18, color: AppColors.error),
                SizedBox(width: 10),
                Text(
                  AppStrings.employeesActionDeactivate,
                  style: TextStyle(color: AppColors.error),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
