import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../../../core/constants/app_colors.dart';
import '../../../../../../core/constants/app_strings.dart';
import '../../../../data/models/kra_score_entry.dart';
import '../../../widgets/_formatters.dart';
import 'score_slider.dart';

/// One card in the self-rate form — bundles the row's metadata (name,
/// category, weightage, target) with the score slider and the optional
/// per-cell comment field.
///
/// Border colour reflects fill state:
///   - default grey   → no score yet, no error
///   - orange         → highlighted as missing (after a submit attempt)
///   - success green  → score recorded
///
/// The description is collapsed by default and expands on tap; long
/// descriptions otherwise dominate the form's vertical space.
class KraScoreInputCard extends StatefulWidget {
  final KraScoreEntry entry;
  final bool isHighlightedAsMissing;
  final ValueChanged<double?> onScoreChanged;
  final ValueChanged<String> onRemarkChanged;
  final ValueChanged<bool> onToggleNotApplicable;

  /// Called when the user picks a proof file — carries the display
  /// [name] and the on-device [path].
  /// [path] is null on web (browsers expose no filesystem path); the name is
  /// what marks the entry as attached.
  final void Function(String name, String? path) onAttach;
  final VoidCallback onRemoveAttachment;

  const KraScoreInputCard({
    super.key,
    required this.entry,
    required this.onScoreChanged,
    required this.onRemarkChanged,
    required this.onToggleNotApplicable,
    required this.onAttach,
    required this.onRemoveAttachment,
    this.isHighlightedAsMissing = false,
  });

  @override
  State<KraScoreInputCard> createState() => _KraScoreInputCardState();
}

class _KraScoreInputCardState extends State<KraScoreInputCard> {
  late final TextEditingController _remarkController;
  bool _descriptionExpanded = false;
  static const int _remarkCharLimit = 200;

  @override
  void initState() {
    super.initState();
    _remarkController = TextEditingController(text: widget.entry.selfRemark);
  }

  @override
  void didUpdateWidget(covariant KraScoreInputCard old) {
    super.didUpdateWidget(old);
    // Keep the text field in sync if the entry's selfRemark was rewound
    // by a draft-resume — but don't clobber an in-progress edit.
    if (widget.entry.selfRemark != _remarkController.text &&
        !_remarkController.value.composing.isValid) {
      _remarkController.text = widget.entry.selfRemark;
      _remarkController.selection = TextSelection.collapsed(
        offset: widget.entry.selfRemark.length,
      );
    }
  }

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  Color get _borderColor {
    if (widget.isHighlightedAsMissing && !widget.entry.isFilled) {
      return AppColors.accentOrange;
    }
    if (widget.entry.isFilled) return AppColors.success.withValues(alpha: 0.6);
    return AppColors.divider;
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row: name + weightage badge ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  e.itemName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              _WeightagePill(percent: e.weightagePercent),
            ],
          ),

          // ── Category chip ──
          if (e.category != null && e.category!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _CategoryChip(label: e.category!),
          ],

          // ── Description (expandable) ──
          if (e.description != null && e.description!.isNotEmpty) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () =>
                  setState(() => _descriptionExpanded = !_descriptionExpanded),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _descriptionExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _descriptionExpanded
                            ? e.description!
                            : (e.description!.length > 80
                                ? '${e.description!.substring(0, 80)}…'
                                : e.description!),
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // ── Target / tracking metadata ──
          if (e.target != null && e.target!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _MetaRow(label: AppStrings.selfRateTargetLabel, value: e.target!),
          ],
          if (e.trackingMethod != null && e.trackingMethod!.isNotEmpty) ...[
            const SizedBox(height: 4),
            _MetaRow(
              label: AppStrings.selfRateTrackingLabel,
              value: e.trackingMethod!,
            ),
          ],

          const SizedBox(height: 14),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 14),

          // ── Score slider ──
          ScoreSlider(
            value: e.selfRating,
            maxScore: e.maxScore,
            isNotApplicable: e.isNotApplicable,
            hasError: widget.isHighlightedAsMissing && !e.isFilled,
            onChanged: widget.onScoreChanged,
            onChangeEnd: widget.onScoreChanged,
            onToggleNotApplicable: widget.onToggleNotApplicable,
          ),

          // ── Reason for the rating ──
          const SizedBox(height: 12),
          TextField(
            controller: _remarkController,
            enabled: !e.isNotApplicable,
            maxLength: _remarkCharLimit,
            minLines: 1,
            maxLines: 3,
            onChanged: widget.onRemarkChanged,
            decoration: InputDecoration(
              labelText: AppStrings.selfRateReasonLabel,
              labelStyle: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
              hintText: AppStrings.selfRateReasonHint,
              hintStyle: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textMuted,
              ),
              filled: true,
              fillColor: AppColors.background,
              counterStyle: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textMuted,
              ),
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
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.textPrimary,
              height: 1.4,
            ),
          ),

          // ── Proof / attachment ──
          const SizedBox(height: 12),
          _AttachmentField(
            entry: e,
            onPick: e.isNotApplicable ? null : _pickAttachment,
            onRemove: widget.onRemoveAttachment,
          ),
        ],
      ),
    );
  }

  Future<void> _pickAttachment() async {
    // A browser never exposes a filesystem path, so `PlatformFile.path` is
    // ALWAYS null on the web build — the old `if (path == null) return;` made
    // this button silently do nothing there. The NAME is what marks the entry as
    // attached (see KraScoreEntry.hasAttachment) and `attachmentPath` is already
    // nullable, so pass the path through as-is and let web supply null.
    // Failures used to be indistinguishable from a dead button; say so instead.
    try {
      // Any file type — Excel, Word, PowerPoint, images, PDF, whatever the
      // evidence happens to be. Restricting extensions only blocked valid proof.
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return; // cancelled — normal
      final file = result.files.single;
      widget.onAttach(file.name, file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the file picker: $e')),
      );
    }
  }
}

/// Shows either an "Attach proof" button or the attached-file chip with
/// a remove control and a "not uploaded yet" note. [onPick] is null when
/// the cell is N/A (attachment disabled).
class _AttachmentField extends StatelessWidget {
  final KraScoreEntry entry;
  final VoidCallback? onPick;
  final VoidCallback onRemove;

  const _AttachmentField({
    required this.entry,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (!entry.hasAttachment) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.attach_file_rounded, size: 18),
          label: const Text(AppStrings.selfRateAttachmentAdd),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryPurple,
            side: const BorderSide(color: AppColors.divider),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          decoration: BoxDecoration(
            color: AppColors.primaryPurple.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.primaryPurple.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.insert_drive_file_outlined,
                size: 18,
                color: AppColors.primaryPurple,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.attachmentName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (onPick != null)
                TextButton(
                  onPressed: onPick,
                  child: const Text(AppStrings.selfRateAttachmentReplace),
                ),
              IconButton(
                onPressed: onRemove,
                tooltip: AppStrings.selfRateAttachmentRemoveTooltip,
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 13,
              color: AppColors.textMuted,
            ),
            SizedBox(width: 5),
            Expanded(
              child: Text(
                AppStrings.selfRateAttachmentPendingNote,
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textMuted,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WeightagePill extends StatelessWidget {
  final double percent;
  const _WeightagePill({required this.percent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryPurple.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        EmployeeFormatters.weightagePercent(percent),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: AppColors.primaryPurple,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  const _CategoryChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accentOrange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: AppColors.accentOrange,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  const _MetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 0.2,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textPrimary,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
