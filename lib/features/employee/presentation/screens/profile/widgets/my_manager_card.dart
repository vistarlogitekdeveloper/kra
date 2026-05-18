import 'package:flutter/material.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../../data/models/employee_profile.dart';
import 'profile_header.dart';

/// Manager card on the profile screen — tappable, routes to the
/// reporting-tree screen for the full chain of reporting. Renders the
/// manager's initials inside a coloured circle (same colour algorithm
/// as the user's own avatar — different code, different hue).
class MyManagerCard extends StatelessWidget {
  final ProfileManagerRef manager;
  final VoidCallback onTap;
  const MyManagerCard({
    super.key,
    required this.manager,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final swatch =
        ProfileHeader.colourFor(manager.employeeCode ?? manager.id);
    final initials = ProfileHeader.initialsOf(manager.name);
    final role = manager.role?.replaceAll('_', ' ');

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: swatch.withValues(alpha: 0.15),
                  border: Border.all(
                    color: swatch.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: swatch,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      manager.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      role ?? AppStrings.profileFieldManager,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
