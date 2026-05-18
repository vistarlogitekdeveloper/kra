import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
import '../../../auth/presentation/widgets/branded_primary_button.dart';
import '../../../auth/presentation/widgets/branded_text_field.dart';
import '../../data/models/employee.dart';
import '../providers/employee_providers.dart';
import '../providers/project_location_providers.dart';
import '../widgets/_formatters.dart';
import '../widgets/confirm_action_dialog.dart';

/// Add/edit employee form. Pass [employeeId] for edit mode; omit for
/// create. The form preloads from [employeeDetailProvider] in edit mode
/// and warns the user before navigating away with unsaved changes.
class EmployeeFormScreen extends ConsumerStatefulWidget {
  final String? employeeId;
  const EmployeeFormScreen({super.key, this.employeeId});

  bool get isEdit => employeeId != null;

  @override
  ConsumerState<EmployeeFormScreen> createState() =>
      _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends ConsumerState<EmployeeFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _departmentController = TextEditingController();
  final _gradeController = TextEditingController();

  String _role = 'EMPLOYEE';
  String? _projectLocationId;
  DateTime? _joinedDate;
  String? _serverError;
  bool _isSubmitting = false;
  bool _isDirty = false;
  bool _hydrated = false;

  /// Field-level server errors keyed by field name. Surface from the
  /// API on a 400 (validation) and clear on the next keystroke.
  final Map<String, String> _fieldErrors = {};

  static const _roles = [
    'EMPLOYEE',
    'MANAGER',
    'OPS',
    'HR',
    'HR_ADMIN',
    'FINANCE',
    'BD_MANAGER',
    'WAREHOUSE_MGR',
  ];

  @override
  void initState() {
    super.initState();
    for (final c in [
      _codeController,
      _nameController,
      _emailController,
      _departmentController,
      _gradeController,
    ]) {
      c.addListener(() => setState(() => _isDirty = true));
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _departmentController.dispose();
    _gradeController.dispose();
    super.dispose();
  }

  void _hydrateFrom(Employee e) {
    if (_hydrated) return;
    _codeController.text = e.employeeCode;
    _nameController.text = e.fullName;
    _emailController.text = e.email;
    _departmentController.text = e.department ?? '';
    _gradeController.text = e.grade ?? '';
    setState(() {
      _role = e.role;
      _projectLocationId = e.projectLocationId;
      _joinedDate = e.joinedDate;
      _hydrated = true;
      _isDirty = false;
    });
  }

  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.employeeFormUnsavedTitle,
      message: AppStrings.employeeFormUnsavedMessage,
      confirmLabel: AppStrings.commonDiscard,
      icon: Icons.help_outline_rounded,
      accentColor: AppColors.accentOrange,
    );
    return ok == true;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _joinedDate ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() {
        _joinedDate = picked;
        _isDirty = true;
      });
    }
  }

  Future<void> _submit() async {
    setState(() {
      _serverError = null;
      _fieldErrors.clear();
    });
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    setState(() => _isSubmitting = true);
    final repo = ref.read(employeeRepositoryProvider);
    try {
      if (widget.isEdit) {
        final updated = await repo.update(widget.employeeId!, {
          'employeeCode': _codeController.text.trim(),
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'role': _role,
          'department': _departmentController.text.trim().isEmpty
              ? null
              : _departmentController.text.trim(),
          'projectLocationId': _projectLocationId,
          'grade': _gradeController.text.trim().isEmpty
              ? null
              : _gradeController.text.trim(),
          if (_joinedDate != null)
            'joinedDate': _joinedDate!.toIso8601String(),
        });
        ref.read(employeeListProvider.notifier).replaceUpdated(updated);
        ref.invalidate(employeeDetailProvider(updated.id));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.employeeFormSaved)),
        );
        context.pop();
      } else {
        final created = await repo.create(
          employeeCode: _codeController.text.trim(),
          fullName: _nameController.text.trim(),
          email: _emailController.text.trim(),
          role: _role,
          department: _departmentController.text.trim().isEmpty
              ? null
              : _departmentController.text.trim(),
          projectLocationId: _projectLocationId,
          grade: _gradeController.text.trim().isEmpty
              ? null
              : _gradeController.text.trim(),
          joinedDate: _joinedDate,
        );
        ref.read(employeeListProvider.notifier).prependCreated(created);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.employeeFormCreated)),
        );
        context.pop();
      }
    } on ApiError catch (e) {
      setState(() {
        _serverError = e.message;
        // Best-effort field mapping: the API echoes the offending field
        // in technicalMessage when available. Surface it under the
        // correct text field; if not, the top-of-form banner shows.
        if (e.code == 'VALIDATION_ERROR' && e.technicalMessage != null) {
          for (final f in const [
            'employeeCode',
            'fullName',
            'email',
            'role',
            'department',
            'projectLocationId',
            'grade',
            'joinedDate',
          ]) {
            if (e.technicalMessage!.contains(f)) {
              _fieldErrors[f] = e.message;
            }
          }
        }
      });
    } catch (_) {
      setState(() => _serverError = AppStrings.errorGeneric);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = GoRouter.of(context);
        final confirmed = await _confirmDiscard();
        if (!mounted) return;
        if (confirmed) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            widget.isEdit
                ? AppStrings.employeeFormEditTitle
                : AppStrings.employeeFormCreateTitle,
          ),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        body: widget.isEdit
            ? _buildEditBody()
            : _buildForm(),
      ),
    );
  }

  Widget _buildEditBody() {
    final detail =
        ref.watch(employeeDetailProvider(widget.employeeId!));
    return detail.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            ProfileHeaderSkeleton(),
            SizedBox(height: 14),
            DashboardCardSkeleton(),
          ],
        ),
      ),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            e.toString(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.error),
          ),
        ),
      ),
      data: (employee) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _hydrateFrom(employee);
        });
        return _buildForm();
      },
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          if (_serverError != null) _ErrorBanner(message: _serverError!),
          const _SectionHeader(title: AppStrings.employeeFormSectionBasics),
          const SizedBox(height: 12),
          BrandedTextField(
            controller: _codeController,
            label: AppStrings.employeeFormCode,
            hint: AppStrings.employeeFormCodeHint,
            prefixIcon: Icons.badge_outlined,
            validator: (v) => v == null || v.trim().isEmpty
                ? AppStrings.validationRequired
                : _fieldErrors['employeeCode'],
          ),
          const SizedBox(height: 14),
          BrandedTextField(
            controller: _nameController,
            label: AppStrings.employeeFormFullName,
            prefixIcon: Icons.person_outline_rounded,
            validator: (v) => v == null || v.trim().isEmpty
                ? AppStrings.validationRequired
                : _fieldErrors['fullName'],
          ),
          const SizedBox(height: 14),
          BrandedTextField(
            controller: _emailController,
            label: AppStrings.employeeFormEmail,
            prefixIcon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return AppStrings.validationEmailRequired;
              }
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+').hasMatch(v.trim())) {
                return AppStrings.validationEmailInvalid;
              }
              return _fieldErrors['email'];
            },
          ),
          const SizedBox(height: 20),
          const _SectionHeader(title: AppStrings.employeeFormSectionEmployment),
          const SizedBox(height: 12),
          _RoleDropdown(
            value: _role,
            roles: _roles,
            onChanged: (v) => setState(() {
              _role = v;
              _isDirty = true;
            }),
          ),
          const SizedBox(height: 14),
          BrandedTextField(
            controller: _departmentController,
            label: AppStrings.employeeFormDepartment,
            prefixIcon: Icons.business_outlined,
          ),
          const SizedBox(height: 14),
          _LocationDropdown(
            value: _projectLocationId,
            onChanged: (id) => setState(() {
              _projectLocationId = id;
              _isDirty = true;
            }),
          ),
          const SizedBox(height: 14),
          BrandedTextField(
            controller: _gradeController,
            label: AppStrings.employeeFormGrade,
            prefixIcon: Icons.grade_outlined,
          ),
          const SizedBox(height: 14),
          _DateField(
            label: AppStrings.employeeFormJoinedDate,
            value: _joinedDate,
            onTap: _pickDate,
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
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

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

class _RoleDropdown extends StatelessWidget {
  final String value;
  final List<String> roles;
  final ValueChanged<String> onChanged;
  const _RoleDropdown({
    required this.value,
    required this.roles,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          AppStrings.employeeFormRole,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        // Using the non-deprecated `DropdownButton` instead of
        // DropdownButtonFormField — the latter's `value` parameter was
        // renamed to `initialValue` in Flutter 3.33 but our SDK floor
        // (3.10) still uses `value`. A plain DropdownButton wrapped in
        // an InputDecorator gives us the themed look without depending
        // on a moving Flutter API.
        InputDecorator(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.work_outline_rounded, size: 20),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              items: [
                for (final r in roles)
                  DropdownMenuItem(
                    value: r,
                    child: Text(r[0] + r.substring(1).toLowerCase()),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _LocationDropdown extends ConsumerWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _LocationDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationsAsync = ref.watch(allProjectLocationsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          AppStrings.employeeFormProjectLocation,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        locationsAsync.when(
          loading: () => const _LocationDropdownShell(
            child: ShimmerBox(height: 16, borderRadius: 6),
          ),
          error: (_, __) => const _LocationDropdownShell(
            child: Text(
              'Failed to load locations',
              style: TextStyle(fontSize: 14, color: AppColors.error),
            ),
          ),
          data: (locations) {
            // The current value may reference a deactivated location not in
            // the active list — keep the selection valid by surfacing it.
            final hasOrphan =
                value != null && !locations.any((l) => l.id == value);
            return InputDecorator(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.location_on_outlined, size: 20),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: value,
                  isExpanded: true,
                  hint: const Text(
                    'Select location',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('— None —'),
                    ),
                    if (hasOrphan)
                      DropdownMenuItem<String?>(
                        value: value,
                        child: const Text('(current — inactive)'),
                      ),
                    for (final loc in locations)
                      DropdownMenuItem<String?>(
                        value: loc.id,
                        child: Text(
                          loc.displayLabel,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: onChanged,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _LocationDropdownShell extends StatelessWidget {
  final Widget child;
  const _LocationDropdownShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider, width: 1.2),
      ),
      child: child,
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
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
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
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
                Text(
                  value == null ? 'Select date' : HrFormatters.date(value!),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: value == null
                        ? AppColors.textMuted
                        : AppColors.textPrimary,
                  ),
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
