import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../data/models/kra_template_item.dart';

/// One editable KRA item inside the template form.
///
/// Renders a card with: drag handle, name, expandable description,
/// target, tracking method, weightage % field, delete button. Reports
/// edits via [onChanged] so the parent can recompute totals live.
///
/// `controllers` are owned by the parent so reordering doesn't reset
/// caret position or input state. Each row only mounts its TextFields
/// against the controllers it was given.
class KraItemInputRow extends StatefulWidget {
  final int index;
  final KraTemplateItem item;
  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final TextEditingController targetController;
  final TextEditingController trackingController;
  final TextEditingController weightageController;
  final ValueChanged<KraTemplateItem> onChanged;
  final VoidCallback onDelete;

  const KraItemInputRow({
    super.key,
    required this.index,
    required this.item,
    required this.nameController,
    required this.descriptionController,
    required this.targetController,
    required this.trackingController,
    required this.weightageController,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<KraItemInputRow> createState() => _KraItemInputRowState();
}

class _KraItemInputRowState extends State<KraItemInputRow> {
  bool _expanded = false;

  void _emitChange() {
    final weightage =
        double.tryParse(widget.weightageController.text.trim()) ?? 0;
    widget.onChanged(
      widget.item.copyWith(
        name: widget.nameController.text,
        description: widget.descriptionController.text.isEmpty
            ? null
            : widget.descriptionController.text,
        target: widget.targetController.text.isEmpty
            ? null
            : widget.targetController.text,
        trackingMethod: widget.trackingController.text.isEmpty
            ? null
            : widget.trackingController.text,
        weightage: weightage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ReorderableDragStartListener(
                index: widget.index,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    color: AppColors.textMuted,
                    size: 22,
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: widget.nameController,
                  onChanged: (_) => _emitChange(),
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    hintText: AppStrings.kraTemplateFormItemName,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    isDense: true,
                    filled: false,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: TextField(
                  controller: widget.weightageController,
                  onChanged: (_) => _emitChange(),
                  textAlign: TextAlign.right,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d{0,3}(\.\d{0,2})?'),
                    ),
                  ],
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                  decoration: InputDecoration(
                    hintText: '0',
                    suffixText: '%',
                    suffixStyle: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor:
                        AppColors.primaryPurple.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: AppColors.primaryPurple,
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: AppColors.error,
                ),
                tooltip: AppStrings.commonDelete,
                onPressed: widget.onDelete,
              ),
            ],
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 6,
              ),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: AppColors.primaryPurple,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _expanded ? 'Hide details' : 'Add details',
                    style: const TextStyle(
                      color: AppColors.primaryPurple,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 6),
            _LabeledField(
              label: AppStrings.kraTemplateFormItemDescription,
              child: TextField(
                controller: widget.descriptionController,
                onChanged: (_) => _emitChange(),
                maxLines: 3,
                minLines: 2,
                style: const TextStyle(fontSize: 13.5),
                decoration: _denseDecoration(hint: 'Optional notes'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _LabeledField(
                    label: AppStrings.kraTemplateFormItemTarget,
                    child: TextField(
                      controller: widget.targetController,
                      onChanged: (_) => _emitChange(),
                      style: const TextStyle(fontSize: 13.5),
                      decoration:
                          _denseDecoration(hint: 'e.g. ₹ 5L revenue'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _LabeledField(
                    label: AppStrings.kraTemplateFormItemTracking,
                    child: TextField(
                      controller: widget.trackingController,
                      onChanged: (_) => _emitChange(),
                      style: const TextStyle(fontSize: 13.5),
                      decoration: _denseDecoration(hint: 'e.g. CRM'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _denseDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 13,
      ),
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: AppColors.divider.withValues(alpha: 0.6),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: AppColors.divider.withValues(alpha: 0.6),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide:
            const BorderSide(color: AppColors.primaryPurple, width: 1.4),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}
