import 'package:flutter/material.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../widgets/_formatters.dart';

/// Top-of-home greeting hero. A rounded purple gradient card that anchors
/// the home stack — initials avatar, time-aware salutation, the date +
/// employee code, and a role pill.
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

  String _initial() {
    final n = name.trim();
    return n.isEmpty ? '?' : n.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final clock = now ?? DateTime.now();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryPurpleDark,
            AppColors.primaryPurple,
            AppColors.primaryPurpleLight,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryPurple.withValues(alpha: 0.35),
            blurRadius: 30,
            spreadRadius: -14,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Soft depth: a faint glow disc bleeding off the top-right corner,
          // clipped to the card's rounded rect. Kept subtle and pushed further
          // out — at higher opacity it read as a shape behind the logout icon
          // rather than as lighting.
          Positioned(
            right: -46,
            top: -52,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Control bar — actions live on their own row so they never
                // collide with the avatar / name below.
                if (leading != null || trailing != null)
                  Row(
                    children: [
                      if (leading != null) leading!,
                      const Spacer(),
                      if (trailing != null) trailing!,
                    ],
                  ),
                if (leading != null || trailing != null)
                  const SizedBox(height: 2),
                // Avatar sits LEFT of the greeting: the top-right corner belongs
                // to the logout action alone. Stacking the two in the same
                // corner made them read as one overlapping blob.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _Avatar(initial: _initial()),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _greeting(clock.hour),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.85),
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Icon(Icons.calendar_today_rounded,
                        size: 12, color: Colors.white.withValues(alpha: 0.75)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        EmployeeFormatters.today(clock),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.80),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (employeeCode.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      const _DotSeparator(),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          employeeCode,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.65),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (roleLabel.isNotEmpty) ...[
                  const SizedBox(height: 13),
                  _RolePill(label: roleLabel),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Initials disc — translucent white on the purple hero.
class _Avatar extends StatelessWidget {
  final String initial;
  const _Avatar({required this.initial});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _DotSeparator extends StatelessWidget {
  const _DotSeparator();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: 3,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.5),
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
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
