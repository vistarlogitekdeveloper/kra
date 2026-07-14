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
  ConsumerState<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends ConsumerState<EmployeeFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _gradeController = TextEditingController();
  final _monthlyIncentiveController = TextEditingController();
  // Create-mode only. Edits don't change the password here — that's a
  // separate "reset password" flow if it ships later.
  final _passwordController = TextEditingController();

  String _role = 'EMPLOYEE';
  String? _department;
  String? _projectLocationId;
  String? _managerId;
  DateTime? _joinedDate;
  bool _forcePasswordReset = true;
  bool _obscurePassword = true;
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

  /// Department options as they appear in the company Master Data sheet.
  /// Values are stored verbatim on the employee record, so they must match
  /// the sheet spelling exactly (including "Wh-Operation" and the sheet's
  /// "Transporation" spelling) — the imported roster already carries these.
  static const _departments = [
    'Wh-Operation',
    'Accounts & Finance',
    'Transporation',
    'HR',
    'IT Department',
  ];

  @override
  void initState() {
    super.initState();
    for (final c in [
      _codeController,
      _nameController,
      _emailController,
      _gradeController,
      _monthlyIncentiveController,
      _passwordController,
    ]) {
      c.addListener(() => setState(() => _isDirty = true));
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _gradeController.dispose();
    _monthlyIncentiveController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _hydrateFrom(Employee e) {
    if (_hydrated) return;
    _codeController.text = e.employeeCode;
    _nameController.text = e.fullName;
    _emailController.text = e.email;
    _gradeController.text = e.grade ?? '';
    _monthlyIncentiveController.text = e.monthlyIncentiveAmount == null
        ? ''
        : e.monthlyIncentiveAmount!.toStringAsFixed(0);
    setState(() {
      _role = e.role;
      _department =
          (e.department?.isEmpty ?? true) ? null : e.department;
      _projectLocationId = e.projectLocationId;
      _managerId = e.managerId;
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
    // Empty field clears the per-employee override (falls back to the org
    // default); a value sets it. Parsed leniently — the validator has
    // already rejected non-numeric input.
    final incentiveText = _monthlyIncentiveController.text.trim();
    final monthlyIncentive =
        incentiveText.isEmpty ? null : double.tryParse(incentiveText);
    try {
      // ManagerId is only meaningful when the role is EMPLOYEE — other
      // roles report through the org chart differently or sit at the top.
      // Send `null` from non-EMPLOYEE submissions so an admin changing
      // someone's role to MANAGER also clears their stale reporting line.
      final managerIdForPayload =
          _role == 'EMPLOYEE' ? _managerId : null;
      final passwordText = _passwordController.text;
      if (widget.isEdit) {
        final updated = await repo.update(widget.employeeId!, {
          'employeeCode': _codeController.text.trim(),
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'role': _role,
          'department': _department,
          'projectLocationId': _projectLocationId,
          'managerId': managerIdForPayload,
          'grade': _gradeController.text.trim().isEmpty
              ? null
              : _gradeController.text.trim(),
          'monthlyIncentiveAmount': monthlyIncentive,
          if (_joinedDate != null) 'joinedDate': _joinedDate!.toIso8601String(),
          // NB: password is NOT sent here — the update endpoint ignores it.
          // Edit-mode password changes go through the dedicated
          // POST /employees/:id/set-password (see _showResetPasswordDialog).
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
          department: _department,
          projectLocationId: _projectLocationId,
          managerId: managerIdForPayload,
          grade: _gradeController.text.trim().isEmpty
              ? null
              : _gradeController.text.trim(),
          monthlyIncentiveAmount: monthlyIncentive,
          joinedDate: _joinedDate,
          password: passwordText.isEmpty ? null : passwordText,
          forcePasswordReset:
              passwordText.isEmpty ? null : _forcePasswordReset,
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
            'monthlyIncentiveAmount',
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

  /// Edit mode: opens the secure set-password dialog (dedicated endpoint,
  /// separate from the profile PATCH which ignores `password`).
  Future<void> _showResetPasswordDialog() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ResetPasswordDialog(
        employeeId: widget.employeeId!,
        employeeName: _nameController.text.trim(),
      ),
    );
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.setPasswordSuccess)),
      );
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
        body: widget.isEdit ? _buildEditBody() : _buildForm(),
      ),
    );
  }

  Widget _buildEditBody() {
    final detail = ref.watch(employeeDetailProvider(widget.employeeId!));
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
              // A non-EMPLOYEE role doesn't have a reporting manager
              // here, so clear any stale selection so the payload
              // doesn't carry it back to the server.
              if (v != 'EMPLOYEE') _managerId = null;
              _isDirty = true;
            }),
          ),
          // Manager picker only appears for normal employees — managers
          // and HR roles don't report through this surface.
          if (_role == 'EMPLOYEE') ...[
            const SizedBox(height: 14),
            _ManagerDropdown(
              value: _managerId,
              onChanged: (id) => setState(() {
                _managerId = id;
                _isDirty = true;
              }),
            ),
          ],
          const SizedBox(height: 14),
          _DepartmentDropdown(
            value: _department,
            departments: _departments,
            onChanged: (d) => setState(() {
              _department = d;
              _isDirty = true;
            }),
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
          const SizedBox(height: 20),
          const _SectionHeader(title: AppStrings.employeeFormIncentiveSection),
          const SizedBox(height: 12),
          BrandedTextField(
            controller: _monthlyIncentiveController,
            label: AppStrings.employeeFormMonthlyIncentive,
            hint: AppStrings.employeeFormMonthlyIncentiveHint,
            prefixIcon: Icons.payments_outlined,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            validator: (v) {
              final t = v?.trim() ?? '';
              if (t.isEmpty) return null; // optional — clears the override
              final parsed = double.tryParse(t);
              if (parsed == null || parsed < 0) {
                return AppStrings.validationNumberRequired;
              }
              return _fieldErrors['monthlyIncentiveAmount'];
            },
          ),
          // Credentials — collected on create, and changeable on edit so
          // an admin can rotate the (hypothetical) passwords once the app
          // is live. Everything on this form is editable, including email.
          const SizedBox(height: 20),
          _SectionHeader(
            title: widget.isEdit ? 'Password' : 'Login credentials',
          ),
          const SizedBox(height: 6),
          if (widget.isEdit) ...[
            const Text(
              'Reset this employee\'s password via a secure set-password '
              'action, then share the new one with them directly.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _isSubmitting ? null : _showResetPasswordDialog,
                icon: const Icon(Icons.lock_reset_rounded),
                label: const Text(AppStrings.setPasswordTitle),
              ),
            ),
          ] else ...[
            const Text(
              'Optional. Leave blank to create the account without a '
              'password — the employee won\'t be able to log in until '
              'HR sets one later.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            BrandedTextField(
              controller: _passwordController,
              label: 'Initial password',
              hint: 'At least 8 characters',
              prefixIcon: Icons.lock_outline_rounded,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.newPassword],
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
              ),
              validator: (v) {
                final t = v ?? '';
                if (t.isEmpty) return null; // optional
                if (t.length < 8) {
                  return AppStrings.validationPasswordTooShort;
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _forcePasswordReset,
              onChanged: _passwordController.text.isEmpty
                  ? null
                  : (v) => setState(() => _forcePasswordReset = v ?? false),
              title: const Text(
                'Require employee to change this password on first sign-in',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              activeColor: AppColors.primaryPurple,
            ),
          ],
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

/// Admin dialog to set an employee's password via the dedicated
/// POST /employees/:id/set-password endpoint.
class _ResetPasswordDialog extends ConsumerStatefulWidget {
  final String employeeId;
  final String employeeName;
  const _ResetPasswordDialog({
    required this.employeeId,
    required this.employeeName,
  });

  @override
  ConsumerState<_ResetPasswordDialog> createState() =>
      _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends ConsumerState<_ResetPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _forceReset = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(employeeRepositoryProvider).setPassword(
            widget.employeeId,
            password: _controller.text,
            forcePasswordReset: _forceReset,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _submitting = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = AppStrings.errorGeneric;
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.setPasswordTitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.employeeName.isEmpty
                  ? AppStrings.setPasswordSubtitle
                  : 'For ${widget.employeeName}. '
                      '${AppStrings.setPasswordSubtitle}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            BrandedTextField(
              controller: _controller,
              label: AppStrings.setPasswordLabel,
              hint: 'At least 8 characters',
              prefixIcon: Icons.lock_outline_rounded,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
              ),
              validator: (v) {
                final t = v ?? '';
                if (t.isEmpty) return AppStrings.validationPasswordRequired;
                if (t.length < 8) return AppStrings.validationPasswordTooShort;
                return null;
              },
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              value: _forceReset,
              onChanged: (v) => setState(() => _forceReset = v ?? false),
              title: const Text(
                AppStrings.setPasswordForceReset,
                style: TextStyle(fontSize: 13),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              activeColor: AppColors.primaryPurple,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.error, fontSize: 12.5),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : const Text(AppStrings.setPasswordSubmit),
        ),
      ],
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

  String _humanise(String r) {
    if (r.isEmpty) return r;
    return r[0].toUpperCase() + r.substring(1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    // Backend may return a role string that isn't in our standard list —
    // older accounts have values like 'Ops_excellence'. DropdownButton
    // asserts when `value` doesn't match exactly one item, so we surface
    // the orphan as an extra option (mirrors what _LocationDropdown
    // already does for deactivated locations). Without this, opening the
    // edit form for those employees crashed the screen.
    final hasOrphan = value.isNotEmpty && !roles.contains(value);

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
                if (hasOrphan)
                  DropdownMenuItem(
                    value: value,
                    child: Text('${_humanise(value)} (current)'),
                  ),
                for (final r in roles)
                  DropdownMenuItem(
                    value: r,
                    child: Text(_humanise(r)),
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

/// Department picker — fixed options from the company Master Data sheet.
/// Optional (— None — clears it). An employee whose stored department
/// isn't in the list (legacy/free-text data) is surfaced as an extra item
/// so the dropdown can render without asserting, mirroring [_RoleDropdown].
class _DepartmentDropdown extends StatelessWidget {
  final String? value;
  final List<String> departments;
  final ValueChanged<String?> onChanged;
  const _DepartmentDropdown({
    required this.value,
    required this.departments,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasOrphan = value != null && !departments.contains(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          AppStrings.employeeFormDepartment,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        InputDecorator(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.business_outlined, size: 20),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: value,
              isExpanded: true,
              hint: const Text(
                'Select department',
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
                    child: Text('$value (current)'),
                  ),
                for (final d in departments)
                  DropdownMenuItem<String?>(
                    value: d,
                    child: Text(d),
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

/// "Reporting manager" picker — mirrors the [_LocationDropdown] pattern.
/// Only rendered when the employee's role is EMPLOYEE (managers don't
/// report through this surface). If the saved manager isn't in the
/// active list (e.g. they left the org and were deactivated) we surface
/// it as an orphan item so the dropdown can render without asserting.
class _ManagerDropdown extends ConsumerWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _ManagerDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final managersAsync = ref.watch(allManagersProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Reporting manager',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        managersAsync.when(
          loading: () => const _LocationDropdownShell(
            child: ShimmerBox(height: 16, borderRadius: 6),
          ),
          error: (_, __) => const _LocationDropdownShell(
            child: Text(
              'Failed to load managers',
              style: TextStyle(fontSize: 14, color: AppColors.error),
            ),
          ),
          data: (managers) {
            final hasOrphan =
                value != null && !managers.any((m) => m.id == value);
            return InputDecorator(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.supervisor_account_outlined, size: 20),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: value,
                  isExpanded: true,
                  hint: const Text(
                    'Select manager',
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
                    for (final m in managers)
                      DropdownMenuItem<String?>(
                        value: m.id,
                        child: Text(
                          '${m.fullName} · ${m.employeeCode}',
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
