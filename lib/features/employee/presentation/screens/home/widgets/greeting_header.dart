import 'package:flutter/material.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../widgets/_formatters.dart';

/// Top-of-home greeting strip. No card / no background — sits flat on
/// the scaffold and acts as the visual anchor for the rest of the home
/// stack.
///
/// Time-aware salutation:
///   - before 12:00 → "Good morning"
///   - before 17:00 → "Good afternoon"
///   - before 21:00 → "Good evening"
///   - otherwise    → "Good night"
class GreetingHeader extends StatelessWidget {
  /// Display name (first name preferred, full name acceptable). The
  /// caller is responsible for whatever fallback ("there", initials,
  /// etc.) makes sense if the user record is partial.
  final String name;

  /// Six-character employee code (e.g. VLPL0003) shown small below
  /// the greeting line.
  final String employeeCode;

  /// Human-readable role label (e.g. "Warehouse Manager"). Renders as
  /// a small pill — kept short so it doesn't wrap on small screens.
  final String roleLabel;

  /// Allows tests to inject a deterministic clock; production passes
  /// nothing and the widget reads `DateTime.now()`.
  final DateTime? now;

  /// Optional top-left action — the "☰" workspace menu button for
  /// manager/HR roles. Null for plain employees (nothing to switch to).
  final Widget? leading;

  /// Optional top-right action. Kept for flexibility; currently unused.
  final Widget? trailing;

  const GreetingHeader({
    super.key,
    required this.name,
    required this.employeeCode,
    required this.roleLabel,
    this.now,
    this.leading,
    this.trailing,
  });

  String _greeting(int hour) {
    if (hour < 12) return AppStrings.greetingMorning;
    if (hour < 17) return AppStrings.greetingAfternoon;
    if (hour < 21) return AppStrings.greetingEvening;
    return AppStrings.greetingNight;
  }

  @override
  Widget build(BuildContext context) {
    final clock = now ?? DateTime.now();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  '${_greeting(clock.hour)}, $name',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Flexible(
                child: Text(
                  EmployeeFormatters.today(clock),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (employeeCode.isNotEmpty) ...[
                const SizedBox(width: 8),
                _DotSeparator(),
                const SizedBox(width: 8),
                Text(
                  employeeCode,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          _RolePill(label: roleLabel),
        ],
      ),
    );
  }
}

class _DotSeparator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: 3,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.textMuted,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primaryPurple.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryPurple,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
