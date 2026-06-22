import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../auth/presentation/widgets/branded_primary_button.dart';
import '../../../auth/presentation/widgets/branded_text_field.dart';
import '../providers/review_cycle_providers.dart';
import '../widgets/_formatters.dart';

class ReviewCycleFormScreen extends ConsumerStatefulWidget {
  const ReviewCycleFormScreen({super.key});

  @override
  ConsumerState<ReviewCycleFormScreen> createState() =>
      _ReviewCycleFormScreenState();
}

class _ReviewCycleFormScreenState
    extends ConsumerState<ReviewCycleFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  DateTime? _selfRating;
  DateTime? _managerReview;
  DateTime? _opsScoring;
  DateTime? _financeScoring;

  bool _isSubmitting = false;
  String? _serverError;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({
    required DateTime? current,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) onPicked(picked);
  }

  bool _datesValid() {
    if (_startDate == null || _endDate == null) return false;
    return !_endDate!.isBefore(_startDate!);
  }

  /// Backend rejects any deadline that doesn't satisfy
  ///   endDate ≤ selfRating ≤ managerReview ≤ opsScoring ≤ financeScoring.
  /// Catching it here keeps the user from round-tripping to a 400.
  String? _validateDeadlineOrdering() {
    if (_endDate == null) return null;
    DateTime? prev = _endDate;
    String prevLabel = AppStrings.reviewCycleFormEndDate;
    final stages = <(DateTime?, String)>[
      (_selfRating, AppStrings.reviewCycleFormSelfRating),
      (_managerReview, AppStrings.reviewCycleFormManagerReview),
      (_opsScoring, AppStrings.reviewCycleFormOpsScoring),
      (_financeScoring, AppStrings.reviewCycleFormFinanceScoring),
    ];
    for (final (value, label) in stages) {
      if (value == null) continue;
      if (value.isBefore(prev!)) {
        return '$label must be on or after $prevLabel';
      }
      prev = value;
      prevLabel = label;
    }
    return null;
  }

  Future<void> _submit() async {
    setState(() => _serverError = null);
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;
    if (!_datesValid()) {
      setState(() => _serverError = AppStrings.reviewCycleFormDateOrder);
      return;
    }
    final orderingError = _validateDeadlineOrdering();
    if (orderingError != null) {
      setState(() => _serverError = orderingError);
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await ref.read(reviewCyclesProvider.notifier).create(
            name: _nameController.text.trim(),
            startDate: _startDate!,
            endDate: _endDate!,
            selfRatingDeadline: _selfRating,
            managerReviewDeadline: _managerReview,
            opsScoringDeadline: _opsScoring,
            financeScoringDeadline: _financeScoring,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.reviewCycleFormSaved)),
      );
      context.pop();
    } on ApiError catch (e) {
      setState(() => _serverError = e.combinedMessage);
    } catch (_) {
      setState(() => _serverError = AppStrings.errorGeneric);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.reviewCycleFormCreateTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            if (_serverError != null) _ErrorBanner(message: _serverError!),
            BrandedTextField(
              controller: _nameController,
              label: AppStrings.reviewCycleFormName,
              hint: AppStrings.reviewCycleFormNameHint,
              prefixIcon: Icons.title_rounded,
              validator: (v) => v == null || v.trim().isEmpty
                  ? AppStrings.validationRequired
                  : null,
            ),
            const SizedBox(height: 20),
            const _SectionTitle(title: 'Cycle window'),
            const SizedBox(height: 8),
            _DateField(
              label: AppStrings.reviewCycleFormStartDate,
              value: _startDate,
              onTap: () => _pickDate(
                current: _startDate,
                onPicked: (d) => setState(() => _startDate = d),
              ),
            ),
            const SizedBox(height: 12),
            _DateField(
              label: AppStrings.reviewCycleFormEndDate,
              value: _endDate,
              onTap: () => _pickDate(
                current: _endDate,
                onPicked: (d) => setState(() => _endDate = d),
              ),
            ),
            const SizedBox(height: 20),
            const _SectionTitle(title: 'Stage deadlines'),
            const SizedBox(height: 8),
            _DateField(
              label: AppStrings.reviewCycleFormSelfRating,
              value: _selfRating,
              optional: true,
              onTap: () => _pickDate(
                current: _selfRating,
                onPicked: (d) => setState(() => _selfRating = d),
              ),
              onClear: () => setState(() => _selfRating = null),
            ),
            const SizedBox(height: 12),
            _DateField(
              label: AppStrings.reviewCycleFormManagerReview,
              value: _managerReview,
              optional: true,
              onTap: () => _pickDate(
                current: _managerReview,
                onPicked: (d) => setState(() => _managerReview = d),
              ),
              onClear: () => setState(() => _managerReview = null),
            ),
            const SizedBox(height: 12),
            _DateField(
              label: AppStrings.reviewCycleFormOpsScoring,
              value: _opsScoring,
              optional: true,
              onTap: () => _pickDate(
                current: _opsScoring,
                onPicked: (d) => setState(() => _opsScoring = d),
              ),
              onClear: () => setState(() => _opsScoring = null),
            ),
            const SizedBox(height: 12),
            _DateField(
              label: AppStrings.reviewCycleFormFinanceScoring,
              value: _financeScoring,
              optional: true,
              onTap: () => _pickDate(
                current: _financeScoring,
                onPicked: (d) => setState(() => _financeScoring = d),
              ),
              onClear: () => setState(() => _financeScoring = null),
            ),
            const SizedBox(height: 28),
            BrandedPrimaryButton(
              label: AppStrings.commonSave,
              onPressed: _isSubmitting ? null : _submit,
              isLoading: _isSubmitting,
              icon: Icons.check_rounded,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
        color: AppColors.textSecondary,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final bool optional;
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            if (optional) ...[
              const SizedBox(width: 6),
              const Text(
                AppStrings.commonOptional,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider, width: 1.2),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 20, color: AppColors.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value == null ? 'Select date' : HrFormatters.date(value!),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: value == null
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                if (value != null && onClear != null)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16),
                    onPressed: onClear,
                    color: AppColors.textMuted,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Clear',
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
