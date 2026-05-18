import 'package:flutter/material.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../data/models/employee_profile.dart';

/// Header card on the profile screen — avatar (initials in a coloured
/// circle), name, role pill, employee code. Colour is derived from the
/// employee code hash so each person gets a stable, distinct hue.
class ProfileHeader extends StatelessWidget {
  final EmployeeProfile profile;
  const ProfileHeader({super.key, required this.profile});

  /// Stable colour derived from [code] — same code always yields the
  /// same hue, so the user's avatar tile is recognisable on repeat
  /// visits. Falls back to brand purple for an empty code.
  static Color colourFor(String code) {
    if (code.isEmpty) return AppColors.primaryPurple;
    int hash = 0;
    for (final c in code.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    const palette = [
      AppColors.primaryPurple,
      AppColors.accentOrange,
      AppColors.accentRed,
      AppColors.accentYellow,
      AppColors.primaryPurpleLight,
      AppColors.success,
    ];
    return palette[hash % palette.length];
  }

  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '·';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final swatch = colourFor(profile.employeeCode);
    final initials = initialsOf(profile.name);
    final roleLabel = profile.role.replaceAll('_', ' ');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: swatch.withValues(alpha: 0.15),
              border: Border.all(
                color: swatch.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: swatch,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  profile.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _RolePill(label: roleLabel),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        profile.employeeCode,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RolePill extends StatelessWidget {
  final String label;
  const _RolePill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primaryPurple.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: AppColors.primaryPurple,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
