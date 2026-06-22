import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../data/models/performance_incentive.dart';
import '../providers/performance_incentive_providers.dart';
import '../widgets/_formatters.dart';
import '../widgets/empty_state.dart';

/// Per-cycle, per-grade performance incentive editor. Loads via the family
/// provider keyed on cycle id; new/edit happens in a bottom sheet so
/// the user keeps the surrounding context.
class PerformanceIncentivesScreen extends ConsumerWidget {
  final String cycleId;
  const PerformanceIncentivesScreen({super.key, required this.cycleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incentives =
        ref.watch(performanceIncentivesForCycleProvider(cycleId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.performanceIncentivesTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        onPressed: () => _openSheet(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text(AppStrings.commonAdd),
      ),
      body: RefreshIndicator(
        color: AppColors.primaryPurple,
        onRefresh: () async {
          ref.invalidate(performanceIncentivesForCycleProvider(cycleId));
          await ref.read(performanceIncentivesForCycleProvider(cycleId).future);
        },
        child: incentives.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(16),
            physics: const NeverScrollableScrollPhysics(),
            children: const [
              ShimmerBox(height: 80, borderRadius: 14),
              SizedBox(height: 12),
              ShimmerBox(height: 80, borderRadius: 14),
              SizedBox(height: 12),
              ShimmerBox(height: 80, borderRadius: 14),
            ],
          ),
          error: (e, _) => ListView(
            padding: const EdgeInsets.symmetric(vertical: 60),
            children: [
              EmptyState(
                icon: Icons.error_outline_rounded,
                title: AppStrings.errorGeneric,
                message: e.toString(),
                actionLabel: AppStrings.commonRetry,
                onAction: () => ref
                    .invalidate(performanceIncentivesForCycleProvider(cycleId)),
              ),
            ],
          ),
          data: (list) {
            if (list.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 60),
                  EmptyState(
                    icon: Icons.payments_outlined,
                    title: AppStrings.performanceIncentivesEmptyTitle,
                    message: AppStrings.performanceIncentivesEmptyMessage,
                    actionLabel: AppStrings.performanceIncentivesEmptyCta,
                    onAction: () => _openSheet(context, ref),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final s = list[i];
                return _IncentiveTile(
                  incentive: s,
                  onTap: () => _openSheet(context, ref, existing: s),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _openSheet(
    BuildContext context,
    WidgetRef ref, {
    PerformanceIncentive? existing,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PerformanceIncentiveSheet(
        cycleId: cycleId,
        existing: existing,
      ),
    );
  }
}

class _IncentiveTile extends StatelessWidget {
  final PerformanceIncentive incentive;
  final VoidCallback onTap;
  const _IncentiveTile({required this.incentive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accentYellow.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  incentive.grade.isEmpty ? '?' : incentive.grade,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Grade ${incentive.grade}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Monthly ${HrFormatters.currencyInr(incentive.monthlyEligibleAmount)}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Quarterly ${HrFormatters.currencyInr(incentive.quarterlyEligibleAmount)}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PerformanceIncentiveSheet extends ConsumerStatefulWidget {
  final String cycleId;
  final PerformanceIncentive? existing;
  const _PerformanceIncentiveSheet({required this.cycleId, this.existing});

  @override
  ConsumerState<_PerformanceIncentiveSheet> createState() =>
      _PerformanceIncentiveSheetState();
}

class _PerformanceIncentiveSheetState
    extends ConsumerState<_PerformanceIncentiveSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _gradeController;
  late final TextEditingController _monthlyController;
  late final TextEditingController _quarterlyController;
  bool _isSubmitting = false;
  String? _serverError;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _gradeController = TextEditingController(text: e?.grade ?? '');
    _monthlyController = TextEditingController(
      text: e == null ? '' : e.monthlyEligibleAmount.toStringAsFixed(0),
    );
    _quarterlyController = TextEditingController(
      text: e == null ? '' : e.quarterlyEligibleAmount.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _gradeController.dispose();
    _monthlyController.dispose();
    _quarterlyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _serverError = null);
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;
    setState(() => _isSubmitting = true);
    final monthly = double.tryParse(_monthlyController.text.trim()) ?? 0;
    final quarterly = double.tryParse(_quarterlyController.text.trim()) ?? 0;
    final actions = ref.read(performanceIncentiveActionsProvider);
    try {
      if (widget.existing == null) {
        await actions.create(
          cycleId: widget.cycleId,
          grade: _gradeController.text.trim(),
          monthlyEligibleAmount: monthly,
          quarterlyEligibleAmount: quarterly,
        );
      } else {
        await actions.update(widget.existing!.id, {
          'grade': _gradeController.text.trim(),
          'monthlyEligibleAmount': monthly,
          'quarterlyEligibleAmount': quarterly,
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.performanceIncentivesSaved)),
      );
      Navigator.of(context).pop();
    } on ApiError catch (e) {
      setState(() => _serverError = e.message);
    } catch (_) {
      setState(() => _serverError = AppStrings.errorGeneric);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isEdit
                    ? AppStrings.performanceIncentivesEditTitle
                    : AppStrings.performanceIncentivesAddTitle,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 18),
              if (_serverError != null) ...[
                Text(
                  _serverError!,
                  style: const TextStyle(color: AppColors.error),
                ),
                const SizedBox(height: 12),
              ],
              _LabeledInput(
                label: AppStrings.performanceIncentivesGrade,
                controller: _gradeController,
                validator: (v) => v == null || v.trim().isEmpty
                    ? AppStrings.validationRequired
                    : null,
              ),
              const SizedBox(height: 14),
              _LabeledInput(
                label: AppStrings.performanceIncentivesMonthly,
                controller: _monthlyController,
                isCurrency: true,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return AppStrings.validationNumberRequired;
                  }
                  return double.tryParse(v.trim()) == null
                      ? AppStrings.validationNumberRequired
                      : null;
                },
              ),
              const SizedBox(height: 14),
              _LabeledInput(
                label: AppStrings.performanceIncentivesQuarterly,
                controller: _quarterlyController,
                isCurrency: true,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return AppStrings.validationNumberRequired;
                  }
                  return double.tryParse(v.trim()) == null
                      ? AppStrings.validationNumberRequired
                      : null;
                },
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: const Text(
                    AppStrings.commonSave,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabeledInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final bool isCurrency;
  const _LabeledInput({
    required this.label,
    required this.controller,
    this.validator,
    this.isCurrency = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: isCurrency
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          inputFormatters: isCurrency
              ? [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d{0,9}(\.\d{0,2})?'),
                  ),
                ]
              : null,
          decoration: InputDecoration(
            prefixIcon: Icon(
              isCurrency ? Icons.currency_rupee_rounded : Icons.label_outline,
              size: 18,
            ),
          ),
        ),
      ],
    );
  }
}
