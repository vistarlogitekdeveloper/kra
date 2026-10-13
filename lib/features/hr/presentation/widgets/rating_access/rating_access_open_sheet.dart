import 'package:flutter/material.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_strings.dart';
import 'rating_access_copy.dart';

/// What the open sheet hands back: the last day open as a local calendar day,
/// or null for no end; and the reason, trimmed, or null when blank.
typedef RatingAccessOpenRequest = ({DateTime? lastDay, String? reason});

/// "Open until…": an end day or no end, and an optional reason.
class RatingAccessOpenSheet extends StatefulWidget {
  final String title;
  final String subtitle;

  /// The first selectable day, as a local date with no time.
  final DateTime today;
  final DateTime initialDay;

  const RatingAccessOpenSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.today,
    required this.initialDay,
  });

  /// Null when dismissed.
  static Future<RatingAccessOpenRequest?> show(
    BuildContext context, {
    required String title,
    required String subtitle,
    required DateTime today,
    required DateTime initialDay,
  }) {
    return showModalBottomSheet<RatingAccessOpenRequest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => RatingAccessOpenSheet(
        title: title,
        subtitle: subtitle,
        today: today,
        initialDay: initialDay,
      ),
    );
  }

  @override
  State<RatingAccessOpenSheet> createState() => _RatingAccessOpenSheetState();
}

class _RatingAccessOpenSheetState extends State<RatingAccessOpenSheet> {
  final _reason = TextEditingController();
  late DateTime _lastDay = widget.initialDay;
  bool _noEnd = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _lastDay,
      firstDate: widget.today,
      lastDate: ratingAccessLastOpenDay(widget.today),
      helpText: AppStrings.ratingAccessPickDate,
    );
    if (picked == null || !mounted) return;
    setState(() => _lastDay = picked);
  }

  void _submit() {
    final reason = _reason.text.trim();
    Navigator.of(context).pop<RatingAccessOpenRequest>((
      lastDay: _noEnd ? null : _lastDay,
      reason: reason.isEmpty ? null : reason,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.subtitle,
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _noEnd,
              onChanged: (value) => setState(() => _noEnd = value),
              contentPadding: EdgeInsets.zero,
              title: const Text(AppStrings.ratingAccessNoEndDate),
              subtitle: const Text(AppStrings.ratingAccessNoEndDateHelp),
            ),
            if (!_noEnd) ...[
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: _pickDay,
                icon: const Icon(Icons.calendar_month_rounded, size: 18),
                label: Text(
                  '${AppStrings.ratingAccessEndDateLabel} '
                  '${ratingAccessDate(_lastDay)}',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  iconColor: AppColors.primaryPurple,
                  alignment: Alignment.centerLeft,
                  minimumSize: const Size(48, 48),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _reason,
              maxLength: 500,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: AppStrings.ratingAccessReasonLabel,
                hintText: AppStrings.ratingAccessReasonHint,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              AppStrings.ratingAccessOpenHelp,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      minimumSize: const Size(48, 48),
                    ),
                    child: const Text(AppStrings.commonCancel),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      minimumSize: const Size(48, 48),
                    ),
                    child: const Text(AppStrings.ratingAccessOpenConfirm),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
