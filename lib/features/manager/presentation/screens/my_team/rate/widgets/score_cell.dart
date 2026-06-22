import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../../../core/constants/app_colors.dart';
import '../../../../../../../core/constants/app_strings.dart';
import '../../../../../../employee/presentation/widgets/_formatters.dart';
import '../../../../../data/models/monthly_score.dart';
import 'self_rating_chip.dart';

/// Editable score cell for the manager-rate matrix.
///
/// Two interaction patterns:
///   - Type-into-text-field for precise input
///   - Tap a value chip ("0", "5", "10") to fast-set common values
///
/// Validation:
///   - Decimal accepted up to one fractional digit (typical 0.5 step)
///   - Out-of-range nudge via inline error text; the parent notifier
///     reads the typed value through `onChanged` callback per keystroke.
class ScoreCell extends StatefulWidget {
  final MonthlyScore cell;
  final double maxScore;
  final ValueChanged<double?> onScoreChanged;
  final ValueChanged<String?> onRemarkChanged;
  const ScoreCell({
    super.key,
    required this.cell,
    required this.maxScore,
    required this.onScoreChanged,
    required this.onRemarkChanged,
  });

  @override
  State<ScoreCell> createState() => _ScoreCellState();
}

class _ScoreCellState extends State<ScoreCell> {
  late final TextEditingController _scoreController;
  late final TextEditingController _remarkController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scoreController = TextEditingController(
      text: widget.cell.managerRating == null
          ? ''
          : EmployeeFormatters.score(widget.cell.managerRating!),
    );
    _remarkController = TextEditingController(
      text: widget.cell.managerRemark ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant ScoreCell old) {
    super.didUpdateWidget(old);
    // Keep the controller in sync when the parent rebuilds with new
    // model data (e.g. auto-save refresh), but only if the user isn't
    // mid-edit — preserves cursor position during typing.
    final incoming = widget.cell.managerRating == null
        ? ''
        : EmployeeFormatters.score(widget.cell.managerRating!);
    if (_scoreController.text != incoming &&
        !_scoreController.value.composing.isValid) {
      _scoreController.text = incoming;
      _scoreController.selection = TextSelection.collapsed(
        offset: incoming.length,
      );
    }
    final incomingRemark = widget.cell.managerRemark ?? '';
    if (_remarkController.text != incomingRemark &&
        !_remarkController.value.composing.isValid) {
      _remarkController.text = incomingRemark;
      _remarkController.selection = TextSelection.collapsed(
        offset: incomingRemark.length,
      );
    }
  }

  @override
  void dispose() {
    _scoreController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  void _onScoreInput(String raw) {
    if (raw.trim().isEmpty) {
      setState(() => _error = null);
      widget.onScoreChanged(null);
      return;
    }
    final parsed = double.tryParse(raw.trim());
    if (parsed == null) {
      setState(() => _error = AppStrings.managerRateOutOfRange);
      // Clear the parent's stored value too — otherwise a previously
      // valid score stays in notifier state and gets auto-saved/submitted
      // while the cell visibly shows an error (e.g. after typing "8.."),
      // matching the empty/out-of-range branches which also clear it.
      widget.onScoreChanged(null);
      return;
    }
    if (parsed < 0 || parsed > widget.maxScore) {
      setState(() => _error = AppStrings.managerRateOutOfRange);
      widget.onScoreChanged(null);
      return;
    }
    setState(() => _error = null);
    widget.onScoreChanged(parsed);
  }

  void _fastSet(double value) {
    final text = EmployeeFormatters.score(value);
    _scoreController.text = text;
    _scoreController.selection = TextSelection.collapsed(
      offset: text.length,
    );
    setState(() => _error = null);
    widget.onScoreChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final disabled = !widget.cell.isEditable;
    final hasManagerRating = widget.cell.managerRating != null;
    final borderColor = _error != null
        ? AppColors.accentRed
        : hasManagerRating
            ? AppColors.success.withValues(alpha: 0.6)
            : AppColors.divider;

    final field = TextField(
      controller: _scoreController,
      enabled: !disabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9\.]')),
        LengthLimitingTextInputFormatter(5),
      ],
      onChanged: _onScoreInput,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        color: disabled
            ? AppColors.textMuted
            : hasManagerRating
                ? AppColors.primaryPurple
                : AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: '0',
        hintStyle: const TextStyle(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w700,
        ),
        suffixText: '/ ${widget.maxScore.toStringAsFixed(0)}',
        suffixStyle: const TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        filled: true,
        fillColor: disabled
            ? AppColors.divider.withValues(alpha: 0.35)
            : AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: borderColor, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: borderColor, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppColors.primaryPurple,
            width: 1.6,
          ),
        ),
        errorText: _error,
        errorStyle: const TextStyle(
          fontSize: 10,
          height: 1.2,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        field,
        if (!disabled) ...[
          const SizedBox(height: 6),
          _FastValuesRow(maxScore: widget.maxScore, onPick: _fastSet),
        ],
        const SizedBox(height: 6),
        SelfRatingChip(
          selfRating: widget.cell.selfRating,
          maxScore: widget.maxScore,
          selfRemark: widget.cell.selfRemark,
        ),
        const SizedBox(height: 6),
        _RemarkField(
          controller: _remarkController,
          disabled: disabled,
          onChanged: (v) => widget.onRemarkChanged(v.isEmpty ? null : v),
        ),
      ],
    );
  }
}

/// 3-button row of common values — same set as the spec ("0", "5",
/// "10" for the standard 10-point scale; scales with maxScore).
class _FastValuesRow extends StatelessWidget {
  final double maxScore;
  final ValueChanged<double> onPick;
  const _FastValuesRow({required this.maxScore, required this.onPick});

  @override
  Widget build(BuildContext context) {
    // Use 0, mid, max so the UX scales to non-10-point rubrics.
    final values = [
      0.0,
      (maxScore / 2).roundToDouble(),
      maxScore,
    ];
    return Row(
      children: [
        for (int i = 0; i < values.length; i++) ...[
          Expanded(
            child: _FastChip(
              label: EmployeeFormatters.score(values[i]),
              onTap: () => onPick(values[i]),
            ),
          ),
          if (i != values.length - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _FastChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _FastChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryPurpleSurface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryPurple,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _RemarkField extends StatelessWidget {
  final TextEditingController controller;
  final bool disabled;
  final ValueChanged<String> onChanged;
  const _RemarkField({
    required this.controller,
    required this.disabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: !disabled,
      maxLength: 200,
      maxLines: 2,
      minLines: 1,
      onChanged: onChanged,
      style: const TextStyle(
        fontSize: 11.5,
        color: AppColors.textPrimary,
        height: 1.4,
      ),
      decoration: InputDecoration(
        hintText: AppStrings.managerRateRemarkHint,
        hintStyle: const TextStyle(
          fontSize: 11,
          color: AppColors.textMuted,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        filled: true,
        fillColor: AppColors.background,
        counterText: '',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: AppColors.divider, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: AppColors.divider, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: AppColors.primaryPurple,
            width: 1.4,
          ),
        ),
      ),
    );
  }
}
