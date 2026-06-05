import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../data/models/kra_template.dart';
import '_formatters.dart';

/// List/grid card for the KRA Templates screen.
/// Shows the template name, role chip, item count and total weightage,
/// and exposes Clone / Delete via an overflow menu.
class KraTemplateCard extends StatelessWidget {
  final KraTemplate template;
  final VoidCallback? onTap;
  final VoidCallback? onClone;
  final VoidCallback? onDelete;

  const KraTemplateCard({
    super.key,
    required this.template,
    this.onTap,
    this.onClone,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final balanced = template.hasValidWeightage;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primaryPurple.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.description_outlined,
                      color: AppColors.primaryPurple,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          template.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _RoleChip(role: template.role),
                      ],
                    ),
                  ),
                  if (onClone != null || onDelete != null)
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                      onSelected: (v) {
                        if (v == 'clone' && onClone != null) onClone!();
                        if (v == 'delete' && onDelete != null) onDelete!();
                      },
                      itemBuilder: (_) => [
                        if (onClone != null)
                          const PopupMenuItem(
                            value: 'clone',
                            child: Row(
                              children: [
                                Icon(Icons.copy_outlined, size: 18),
                                SizedBox(width: 10),
                                Text(AppStrings.commonClone),
                              ],
                            ),
                          ),
                        if (onDelete != null)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline_rounded,
                                    size: 18, color: AppColors.error),
                                SizedBox(width: 10),
                                Text(
                                  AppStrings.commonDelete,
                                  style: TextStyle(color: AppColors.error),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                ],
              ),
              if (template.description != null &&
                  template.description!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  template.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  _MetaPill(
                    icon: Icons.format_list_numbered_rounded,
                    label:
                        '${template.displayItemCount} ${AppStrings.kraTemplatesItems}',
                  ),
                  // Weightage is only known once items are loaded — the
                  // list payload omits them, so the card hydrates lazily.
                  if (template.hasWeightageData) ...[
                    const SizedBox(width: 8),
                    _MetaPill(
                      icon: balanced
                          ? Icons.check_circle_rounded
                          : Icons.warning_amber_rounded,
                      label: HrFormatters.weightagePercent(
                        template.totalWeightage,
                      ),
                      color: balanced ? AppColors.success : AppColors.error,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String role;
  const _RoleChip({required this.role});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accentOrange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        role.isEmpty ? '—' : role,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: AppColors.accentOrange,
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _MetaPill({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: c,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
