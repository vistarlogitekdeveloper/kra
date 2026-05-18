import 'package:flutter/material.dart';

import '../../../../../../core/constants/app_colors.dart';

/// Read-only "label / value" row used in the profile field sections.
/// Optional trailing widget on the right (e.g. a copy button or status
/// badge — currently unused but reserved for Stage 5).
class ProfileFieldRow extends StatelessWidget {
  final String label;
  final String? value;
  final IconData? icon;
  final Widget? trailing;
  final bool isLast;

  const ProfileFieldRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.trailing,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom:
                    BorderSide(color: AppColors.divider, width: 0.6),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value == null || value!.isEmpty ? '—' : value!,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: value == null || value!.isEmpty
                        ? AppColors.textMuted
                        : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
