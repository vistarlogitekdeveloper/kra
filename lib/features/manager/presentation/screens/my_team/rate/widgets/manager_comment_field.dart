import 'package:flutter/material.dart';

import '../../../../../../../core/constants/app_colors.dart';
import '../../../../../../../core/constants/app_strings.dart';

/// Multi-line text field for the manager's overall comment on the
/// review. Rendered at the bottom of the matrix view (above the
/// sticky footer). 500-char cap with a live counter — the spec gives
/// the manager more room than the per-cell remark fields because the
/// overall comment is the place to talk about themes / patterns.
class ManagerCommentField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final bool readOnly;

  const ManagerCommentField({
    super.key,
    required this.value,
    required this.onChanged,
    this.readOnly = false,
  });

  @override
  State<ManagerCommentField> createState() => _ManagerCommentFieldState();
}

class _ManagerCommentFieldState extends State<ManagerCommentField> {
  late final TextEditingController _controller;
  static const int _charLimit = 500;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant ManagerCommentField old) {
    super.didUpdateWidget(old);
    // Keep the controller in sync when the parent rebuilds with a
    // server-fetched value, but don't clobber an active edit.
    if (widget.value != _controller.text &&
        !_controller.value.composing.isValid) {
      _controller.text = widget.value;
      _controller.selection =
          TextSelection.collapsed(offset: widget.value.length);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            AppStrings.managerRateCommentLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            readOnly: widget.readOnly,
            onChanged: widget.onChanged,
            maxLength: _charLimit,
            minLines: 3,
            maxLines: 6,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.textPrimary,
              height: 1.45,
            ),
            decoration: InputDecoration(
              hintText: AppStrings.managerRateCommentHint,
              hintStyle: const TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
              filled: true,
              fillColor: AppColors.background,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.divider, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.divider, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.primaryPurple,
                  width: 1.4,
                ),
              ),
              counterStyle: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
