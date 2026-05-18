import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

/// Notification dot rendered on the inactive mode pill when there's
/// pending work in that mode. Plain red 8×8 by default; numeric
/// variant for counts > 0.
class ModeBadge extends StatelessWidget {
  /// Optional count to render. Falsy values (null / 0) render the
  /// dot-only variant.
  final int? count;

  /// Override colour. Defaults to [AppColors.accentRed].
  final Color color;

  const ModeBadge({super.key, this.count, this.color = AppColors.accentRed});

  @override
  Widget build(BuildContext context) {
    final hasCount = count != null && count! > 0;
    if (!hasCount) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Text(
        count! > 9 ? '9+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 10,
          color: Colors.white,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
}
