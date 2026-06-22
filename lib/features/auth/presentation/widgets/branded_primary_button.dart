import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_gradients.dart';

/// Hero "Vistar Premium" CTA — wears the rainbow ribbon gradient with a
/// pink-glow drop shadow. Disabled state collapses to a flat muted surface
/// so it can't be confused with an idle ribbon button.
///
/// Handles loading state internally — pass `isLoading: true` and the
/// button disables itself and shows a spinner.
class BrandedPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  const BrandedPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bool disabled = onPressed == null || isLoading;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        gradient: disabled ? null : AppGradients.ribbon,
        color: disabled ? AppColors.surfaceElevated : null,
        border: disabled
            ? Border.all(color: AppColors.divider)
            : null,
        boxShadow: disabled
            ? null
            : [
                BoxShadow(
                  color: AppColors.pink.withValues(alpha: 0.45),
                  blurRadius: 34,
                  spreadRadius: -10,
                  offset: const Offset(0, 14),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onPressed,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            height: 56,
            alignment: Alignment.center,
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: disabled
                              ? AppColors.textMuted
                              : Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                      if (icon != null) ...[
                        const SizedBox(width: 10),
                        Icon(icon,
                            color: disabled
                                ? AppColors.textMuted
                                : Colors.white,
                            size: 18),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
