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

  const KraScoreInputCard({
    super.key,
    required this.entry,
    required this.onScoreChanged,
    required this.onRemarkChanged,
    required this.onToggleNotApplicable,
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
              onTap: () => setState(
                  () => _descriptionExpanded = !_descriptionExpanded),
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

          // ── Optional remark ──
          const SizedBox(height: 12),
          TextField(
            controller: _remarkController,
            enabled: !e.isNotApplicable,
            maxLength: _remarkCharLimit,
            minLines: 1,
            maxLines: 3,
            onChanged: widget.onRemarkChanged,
            decoration: InputDecoration(
              labelText: AppStrings.selfRateOptionalComment,
              labelStyle: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
              hintText: AppStrings.selfRateOptionalCommentHint,
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
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
            ),
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.textPrimary,
              height: 1.4,
            ),
          ),
        ],
      ),
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
