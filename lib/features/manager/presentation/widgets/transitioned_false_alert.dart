import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/models/transition_error.dart';
import 'transition_error_message_mapper.dart';

/// Reusable orange alert shown wherever a manager-rate response came
/// back with `transitioned: false`. Two variants — full-card on the
/// partial-success screen, compact banner on the rate screen above
/// the submit bar.
class TransitionedFalseAlert extends StatelessWidget {
  final TransitionError? error;

  /// Compact = no padding around message, smaller icon. Used inline
  /// over the submit bar. Default `false` is the full-card variant.
  final bool compact;

  const TransitionedFalseAlert({
    super.key,
    required this.error,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final message = TransitionErrorMessageMapper.managerRate(error);
    return Container(
      padding: compact
          ? const EdgeInsets.fromLTRB(12, 10, 12, 10)
          : const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.accentOrange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.accentOrange.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: AppColors.accentOrange,
            size: compact ? 18 : 22,
          ),
          SizedBox(width: compact ? 8 : 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: compact ? 12 : 13.5,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
