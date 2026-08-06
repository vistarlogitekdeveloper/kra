import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/constants/feature_flags.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../../../core/widgets/shimmer_skeletons.dart';
import '../../../auth/data/models/user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
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

  // The selected job designation (title). The functional access role defaults
  // to whatever [_roleFromDesignation] infers from it.
  String _designation = '';

  /// Explicit access roles, overriding the designation-derived default. Empty =
  /// follow the designation.
  ///
  /// A set because one post can hold several review seats (HR admin who also
  /// rates the Accounts seat). Only the FIRST is sent as the scalar `role`; the
  /// rest ride along in `roles`, which the backend does not accept yet — so
  /// picking more than one is inert until it does (the form says so).
  final Set<String> _rolesOverride = {};

  /// The PRIMARY overridden role — the scalar the API actually stores. Null when
  /// nothing is overridden, so the designation's default applies.
  ///
  /// Access and job title are genuinely separate axes: a "Commercial Manager"
  /// may administer HR, and a founder needs the management-review seat no title
  /// rule should have to guess at. Deriving the role from the title alone made
  /// HR_ADMIN unreachable — no designation produced it — so that grant was
  /// impossible to make from this form at all.
  String? get _roleOverride =>
      _rolesOverride.isEmpty ? null : _rolesOverride.first;

  /// Whether the signed-in user may GRANT roles.
  ///
  /// The target is super admin ONLY: an HR admin who can edit roles can grant
  /// themselves any role, which is a privilege-escalation path, so the authority
  /// sits a tier above them ([User.isSuperAdmin]).
  ///
  /// Until the backend can store `SUPER_ADMIN` nobody holds that tier, and
  /// restricting the field to it would leave NO ONE able to assign roles at all
  /// — including the assignments needed to bootstrap the tier itself. So while
  /// [FeatureFlags.roleTiers] is off, HR admins keep the ability they have
  /// today.
  bool get _canGrantRoles {
    final auth = ref.watch(authStateProvider);
    if (auth is! AuthAuthenticated) return false;
    if (auth.user.isSuperAdmin) return true;
    return !FeatureFlags.roleTiers &&
        auth.user.hasAnyRole({UserRole.hrAdmin});
  }

  /// Access roles HR can grant explicitly.
  ///
  /// EXACTLY the values the backend's employees endpoint accepts — anything else
  /// comes back as `VAL_001 Validation failed`, so offering an unsupported value
  /// would only ever produce a 400 on save. `MANAGEMENT` / `SUPER_ADMIN` appear
  /// once the server accepts them ([FeatureFlags.roleTiers]).
  static const _accessRoles = [
    'EMPLOYEE',
    'MANAGER',
    'BD_MANAGER',
    'WAREHOUSE_MGR',
    'OPS',
    'OPS_EXCELLENCE',
    'HR',
    'HR_ADMIN',
    'FINANCE',
    if (FeatureFlags.roleTiers) ...['MANAGEMENT', 'SUPER_ADMIN'],
  ];
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

  /// The employee as first loaded (edit mode). Used to send only the fields
  /// that actually changed on save, so an untouched record isn't re-sent
  /// wholesale — that re-clobbered nullable columns and, before the backend
  /// accepted nulls, 500'd on a cleared incentive.
  Employee? _original;

  /// Field-level server errors keyed by field name. Surface from the
  /// API on a 400 (validation) and clear on the next keystroke.
  final Map<String, String> _fieldErrors = {};

  /// Job designations HR picks from. The functional access role
  /// (EMPLOYEE / MANAGER / HR / FINANCE) is inferred from the choice by
  /// [_roleFromDesignation], so reviews + permissions keep working while HR
  /// works purely in org titles.
  static const _designations = [
    'Founder & CEO',
    'Director',
    'Manager',
    'Assistant Manager',
    'Cluster Manager',
    'Cluster Manager-Tpt',
    'Commercial Manager',
    'Regional Manager',
    'Regional Manager-Ka',
    'Sr. General Manager',
    'Project Incharge',
    'Senior Officer',
    'Senior Officer-Hr',
    'Software Developer',
    'Sr. Accountant',
  ];

  /// Maps a designation to the functional role that drives access + reviews:
  ///   * Founder / CEO / Director  → MANAGEMENT, the management-review tier
  ///     (HR_ADMIN until the backend accepts it — see [FeatureFlags.roleTiers])
  ///   * "…-Hr" / anything HR      → HR (reviews HR-assigned KRAs)
  ///   * "…Accountant" / Finance   → FINANCE (reviews Accounts-assigned KRAs)
  ///   * any Manager / Incharge    → MANAGER
  ///   * everything else           → EMPLOYEE
  ///
  /// This is only a DEFAULT. A title can't express every access grant — a
  /// Commercial Manager who also administers HR is a real case — so HR can
  /// override the result per person via the Access role field
  /// ([_roleOverride]). Management titles are matched first: the management
  /// tier is the narrowest, highest-privilege seat, and an unmatched title
  /// silently falling through to EMPLOYEE is how a founder ended up with no
  /// management-review access at all.
  static String _roleFromDesignation(String designation) {
    final d = designation.toUpperCase();
    // Management tier. Falls back to HR_ADMIN while the backend's employees
    // endpoint rejects MANAGEMENT (VAL_001) — sending it would 400 every save
    // for these titles. See [FeatureFlags.roleTiers].
    if (d.contains('CEO') ||
        d.contains('FOUNDER') ||
        d.contains('DIRECTOR') ||
        d.contains('CHAIRMAN')) {
      return FeatureFlags.roleTiers ? 'MANAGEMENT' : 'HR_ADMIN';
    }
    if (d.contains('HR')) return 'HR';
    if (d.contains('ACCOUNT') || d.contains('FINANCE')) return 'FINANCE';
    if (d.contains('MANAGER') ||
        d.contains('INCHARGE') ||
        d.contains('IN-CHARGE') ||
        d.contains('IN CHARGE')) {
      return 'MANAGER';
    }
    return 'EMPLOYEE';
  }

  /// Department options as they appear in the company Master Data sheet,
  /// with the sheet's "Transporation" typo corrected — the backend data is
  /// being normalised to "Transportation" to match. Values are stored
  /// verbatim on the employee record.
  static const _departments = [
    'Wh-Operation',
    'Accounts & Finance',
    'Transportation',
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
    _original = e;
    _codeController.text = e.employeeCode;
    _nameController.text = e.fullName;
    _emailController.text = e.email;
    _gradeController.text = e.grade ?? '';
    _monthlyIncentiveController.text = e.monthlyIncentiveAmount == null
        ? ''
        : e.monthlyIncentiveAmount!.toStringAsFixed(0);
    setState(() {
      // Prefer the stored designation; if an older record has none, leave it
      // empty (HR picks one) rather than guessing from the functional role.
      _designation =
          (e.position?.trim().isEmpty ?? true) ? '' : e.position!.trim();
      // An access role the title would NOT produce is shown as an explicit
      // override — otherwise editing an unrelated field would silently reset
      // it to the derived default on save (e.g. demoting an HR-admin
      // Commercial Manager back to MANAGER).
      final derived =
          _designation.isEmpty ? null : _roleFromDesignation(_designation);
      // Prefer the multi-role list when the API supplies one; otherwise the
      // scalar. Either way, a set matching the designation's default stays
      // "Auto" so the field only shows an override when there really is one.
      final stored = <String>{
        for (final r in e.roles) r.trim().toUpperCase(),
        if (e.roles.isEmpty) e.role.trim().toUpperCase(),
      }..removeWhere((r) => r.isEmpty);
      _rolesOverride
        ..clear()
        ..addAll(
          stored.length == 1 && stored.first == derived ? const {} : stored,
        );
      _department = (e.department?.isEmpty ?? true) ? null : e.department;
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
      // EVERY employee has a reporting manager, whatever their role — managers
      // report to senior managers and HR admins report to someone too. This
      // used to force `null` for any non-EMPLOYEE role, which silently wiped a
      // manager's reporting line on every edit and made "manager of a manager"
      // impossible to express. The mapping now drives who may rate whom, so it
      // is sent as selected regardless of role.
      final managerIdForPayload = _managerId;
      final passwordText = _passwordController.text;
      // Designation → stored title (position) + derived functional role. A
      // blank designation keeps the existing role (edit) or defaults to
      // EMPLOYEE (create), so editing an unrelated field can't downgrade a
      // manager just because the title wasn't set yet.
      final designation = _designation.trim();
      final position = designation.isEmpty ? null : designation;
      // An explicit Access role wins; otherwise fall back to the designation's
      // default (and, with no designation, to whatever the record already had).
      final role = _roleOverride ??
          (designation.isEmpty
              ? (_original?.role ?? 'EMPLOYEE')
              : _roleFromDesignation(designation));
      // Full grant set — only sent once the server accepts it. While it doesn't,
      // an unrecognised `roles` field would 400 EVERY save, single-role ones
      // included, so the scalar `role` above carries the primary alone.
      final roles = FeatureFlags.multiRole && _rolesOverride.isNotEmpty
          ? _rolesOverride.toList()
          : null;
      if (widget.isEdit) {
        final grade = _gradeController.text.trim().isEmpty
            ? null
            : _gradeController.text.trim();
        // Send only the fields that actually changed. Re-sending an
        // untouched record clobbers nullable columns needlessly (and used
        // to 500 on a null incentive); a field the user deliberately
        // cleared still differs from the original, so it's sent as null and
        // clears server-side. NB: password is never sent here — edit-mode
        // password changes go through POST /employees/:id/set-password
        // (see _showResetPasswordDialog).
        final changes = _diffFromOriginal(
          code: _codeController.text.trim(),
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          role: role,
          roles: roles,
          position: position,
          department: _department,
          projectLocationId: _projectLocationId,
          managerId: managerIdForPayload,
          grade: grade,
          monthlyIncentiveAmount: monthlyIncentive,
          joinedDate: _joinedDate,
        );
        if (changes.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(AppStrings.employeeFormSaved)),
          );
          context.pop();
          return;
        }
        final updated = await repo.update(widget.employeeId!, changes);
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
          role: role,
          roles: roles,
          position: position,
          department: _department,
          projectLocationId: _projectLocationId,
          managerId: managerIdForPayload,
          grade: _gradeController.text.trim().isEmpty
              ? null
              : _gradeController.text.trim(),
          monthlyIncentiveAmount: monthlyIncentive,
          joinedDate: _joinedDate,
          password: passwordText.isEmpty ? null : passwordText,
          forcePasswordReset: passwordText.isEmpty ? null : _forcePasswordReset,
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

  /// Builds the PATCH body for edit mode, keeping only fields whose value
  /// differs from the originally-loaded employee. A field the user cleared
  /// still differs from its original, so it's sent as null and cleared
  /// server-side; untouched fields are omitted entirely. Falls back to the
  /// full field set if the original wasn't captured.
  Map<String, dynamic> _diffFromOriginal({
    required String code,
    required String name,
    required String email,
    required String role,
    required List<String>? roles,
    required String? position,
    required String? department,
    required String? projectLocationId,
    required String? managerId,
    required String? grade,
    required double? monthlyIncentiveAmount,
    required DateTime? joinedDate,
  }) {
    final o = _original;
    if (o == null) {
      return {
        'employeeCode': code,
        'name': name,
        'email': email,
        'role': role,
        if (roles != null && roles.isNotEmpty) 'roles': roles,
        'position': position,
        'department': department,
        'projectLocationId': projectLocationId,
        'managerId': managerId,
        'grade': grade,
        'monthlyIncentiveAmount': monthlyIncentiveAmount,
        if (joinedDate != null) 'joinedDate': joinedDate.toIso8601String(),
      };
    }

    final oDept = (o.department?.isEmpty ?? true) ? null : o.department;
    final oGrade = (o.grade?.isEmpty ?? true) ? null : o.grade;
    final oPosition = (o.position?.isEmpty ?? true) ? null : o.position;
    final changes = <String, dynamic>{};
    if (code != o.employeeCode) changes['employeeCode'] = code;
    if (name != o.fullName) changes['name'] = name;
    if (email != o.email) changes['email'] = email;
    if (role != o.role) changes['role'] = role;
    // Compare as sets — grant order carries no meaning, so a reordered list is
    // not a change worth PATCHing.
    if (roles != null && roles.toSet() != o.roles.toSet()) {
      changes['roles'] = roles;
    }
    if (position != oPosition) changes['position'] = position;
    if (department != oDept) changes['department'] = department;
    if (projectLocationId != o.projectLocationId) {
      changes['projectLocationId'] = projectLocationId;
    }
    if (managerId != o.managerId) changes['managerId'] = managerId;
    if (grade != oGrade) changes['grade'] = grade;
    if (monthlyIncentiveAmount != o.monthlyIncentiveAmount) {
      changes['monthlyIncentiveAmount'] = monthlyIncentiveAmount;
    }
    final a = joinedDate, b = o.joinedDate;
    final sameDate = (a == null && b == null) ||
        (a != null && b != null && a.isAtSameMomentAs(b));
    if (!sameDate) changes['joinedDate'] = a?.toIso8601String();
    return changes;
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
            value: _designation,
            roles: _designations,
            onChanged: (v) => setState(() {
              // The reporting line is independent of the designation — changing
              // someone's title must NOT clear who they report to.
              _designation = v;
              _isDirty = true;
            }),
          ),
          // Access roles are SUPER-ADMIN only. HR admins maintain employee
          // records, but handing out roles — including their own — is a
          // privilege-escalation path, so the field is hidden (and never sent)
          // for anyone below that tier.
          if (_canGrantRoles) ...[
            const SizedBox(height: 14),
            _AccessRolesField(
              selected: _rolesOverride,
              roles: _accessRoles,
              derived: _designation.trim().isEmpty
                  ? null
                  : _roleFromDesignation(_designation.trim()),
              onToggle: (role, on) => setState(() {
                if (on) {
                  _rolesOverride.add(role);
                } else {
                  _rolesOverride.remove(role);
                }
                _isDirty = true;
              }),
              onClear: () => setState(() {
                _rolesOverride.clear();
                _isDirty = true;
              }),
            ),
          ],
          // Shown for every role: managers report to senior managers and HR
          // admins report to someone too. Whoever is selected here is the one
          // who rates this person.
          const SizedBox(height: 14),
          _ManagerDropdown(
            value: _managerId,
            excludeEmployeeId: widget.employeeId,
            onChanged: (id) => setState(() {
              _managerId = id;
              _isDirty = true;
            }),
          ),
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
            Text(
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
            Text(
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
              title: Text(
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
              style: TextStyle(
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
          onPressed:
              _submitting ? null : () => Navigator.of(context).pop(false),
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
      style: TextStyle(
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
        Text(
          AppStrings.employeeFormDesignation,
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
            prefixIcon: Icon(Icons.badge_outlined, size: 20),
          ),
          child: DropdownButtonHideUnderline(
            // Empty (no designation yet) → null so the hint shows instead of
            // asserting on a value that matches no item.
            child: DropdownButton<String>(
              value: value.isEmpty ? null : value,
              isExpanded: true,
              hint: const Text(AppStrings.employeeFormDesignationHint),
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              items: [
                if (hasOrphan)
                  DropdownMenuItem(
                    value: value,
                    child: Text('$value (current)'),
                  ),
                for (final r in roles)
                  DropdownMenuItem(value: r, child: Text(r)),
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


/// Access-role picker — which permissions/review seats this person holds.
///
/// Multi-select, and separate from the designation on purpose. A job title can't
/// express every grant (a Commercial Manager who also administers HR), and
/// inferring the role from the title alone left HR_ADMIN unreachable entirely.
/// Selecting nothing means "Auto" — follow the designation — so the common case
/// stays a one-field decision for HR.
///
/// Super-admin only; the caller gates rendering.
class _AccessRolesField extends StatelessWidget {
  /// Explicitly granted roles. Empty = follow the designation.
  final Set<String> selected;
  final List<String> roles;

  /// What the current designation would infer — shown so HR can see what Auto
  /// gives them without having to know the mapping.
  final String? derived;
  final void Function(String role, bool selected) onToggle;
  final VoidCallback onClear;
  const _AccessRolesField({
    required this.selected,
    required this.roles,
    required this.derived,
    required this.onToggle,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    // Legacy records can carry a role outside the list (e.g. 'Ops_excellence');
    // show it as a chip so it's visible rather than silently dropped on save.
    final orphans = selected.where((r) => !roles.contains(r)).toList();
    final isAuto = selected.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.employeeFormAccessRole,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text(derived == null
                  ? AppStrings.employeeFormAccessRoleAuto
                  : '${AppStrings.employeeFormAccessRoleAuto} — $derived'),
              selected: isAuto,
              onSelected: (_) => onClear(),
            ),
            for (final r in [...orphans, ...roles])
              FilterChip(
                label: Text(r),
                selected: selected.contains(r),
                onSelected: (on) => onToggle(r, on),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          AppStrings.employeeFormAccessRoleHelp,
          style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
        // Multi-role can't persist until the server accepts a `roles` array:
        // the API stores a single `role`. Say so where the choice is made rather
        // than letting a silent 400 explain it.
        if (!FeatureFlags.multiRole && selected.length > 1) ...[
          const SizedBox(height: 6),
          const Text(
            AppStrings.employeeFormAccessRoleMultiPending,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.accentOrange,
            ),
          ),
        ],
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
        Text(
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
              hint: Text(
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
///
/// Rendered for EVERY role: being a reporting manager is a relationship, not a
/// role, so a manager can report to a senior manager and an HR admin reports to
/// someone too. The candidate list is therefore every active employee, minus
/// [excludeEmployeeId] (the person being edited) so nobody can be set as their
/// own manager — the backend rejects that, and cycles, as well.
///
/// If the saved manager isn't in the active list (e.g. they left the org and
/// were deactivated) we surface it as an orphan item so the dropdown can render
/// without asserting.
class _ManagerDropdown extends ConsumerWidget {
  final String? value;

  /// The employee being edited — filtered out of the candidate list so they
  /// can't be picked as their own reporting manager. Null in create mode.
  final String? excludeEmployeeId;
  final ValueChanged<String?> onChanged;
  const _ManagerDropdown({
    required this.value,
    required this.excludeEmployeeId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final managersAsync = ref.watch(managerCandidatesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
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
          data: (all) {
            // You cannot report to yourself.
            final managers = excludeEmployeeId == null
                ? all
                : all.where((m) => m.id != excludeEmployeeId).toList();
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
                  hint: Text(
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
        Text(
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
                  hint: Text(
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
          style: TextStyle(
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
                Icon(Icons.calendar_today_outlined,
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
