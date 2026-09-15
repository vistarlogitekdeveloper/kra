import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/enums/review_flow.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/shimmer_box.dart';
import '../../data/models/organization.dart';
import '../providers/organization_providers.dart';
import '../widgets/confirm_action_dialog.dart';

/// Tenant administration — list, create, edit and switch between organizations.
///
/// Super admin only. Every other role is scoped to a single organization by the
/// backend, so this screen would be meaningless (and 403) for them.
///
/// One thing this screen deliberately does NOT do is show "all users across all
/// organizations". Every employee read is org-scoped server-side, so a combined
/// roster is not obtainable by looping this list — it needs a dedicated
/// cross-org endpoint. Switching in is the supported way to see a tenant's
/// people.
class OrganizationsScreen extends ConsumerStatefulWidget {
  const OrganizationsScreen({super.key});

  @override
  ConsumerState<OrganizationsScreen> createState() =>
      _OrganizationsScreenState();
}

class _OrganizationsScreenState extends ConsumerState<OrganizationsScreen> {
  final _searchController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(canManageOrganizationsProvider);
    final orgs = ref.watch(organizationsProvider);
    final currentOrgId = ref.watch(currentOrganizationIdProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.orgTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.hrHome),
          tooltip: AppStrings.commonBack,
        ),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primaryPurple,
              foregroundColor: Colors.white,
              onPressed: _busy ? null : () => _openForm(),
              icon: const Icon(Icons.add_rounded),
              label: const Text(AppStrings.orgAdd),
            )
          : null,
      body: !canManage
          // Defence in depth. The route is guarded too, but a role can change
          // under a screen that is already open.
          ? const _Message(
              icon: Icons.lock_outline_rounded,
              text: 'Only a super admin can manage organizations.',
            )
          : RefreshIndicator(
              color: AppColors.primaryPurple,
              onRefresh: () async {
                ref.invalidate(organizationsProvider);
                await ref.read(organizationsProvider.future);
              },
              child: orgs.when(
                loading: () => ListView(
                  padding: const EdgeInsets.all(16),
                  physics: const NeverScrollableScrollPhysics(),
                  children: const [
                    ShimmerBox(height: 92, borderRadius: 14),
                    SizedBox(height: 12),
                    ShimmerBox(height: 92, borderRadius: 14),
                    SizedBox(height: 12),
                    ShimmerBox(height: 92, borderRadius: 14),
                  ],
                ),
                error: (e, _) => ListView(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  children: [
                    _Message(
                      icon: Icons.cloud_off_rounded,
                      // A 404 here means the endpoints are not deployed, which
                      // is a known state rather than a failure — say so plainly
                      // instead of showing "Route not found".
                      text: _isMissingApi(e)
                          ? AppStrings.orgApiMissing
                          : (e is ApiError
                              ? e.combinedMessage
                              : 'Could not load organizations.'),
                      onRetry: () => ref.invalidate(organizationsProvider),
                    ),
                  ],
                ),
                data: (list) => _list(list, currentOrgId),
              ),
            ),
    );
  }

  /// The endpoints ship after the client. Treat "route not found" as
  /// not-deployed-yet rather than an error the user caused.
  bool _isMissingApi(Object e) =>
      e is ApiError && (e.statusCode == 404 || e.code == 'RES_001');

  Widget _list(List<Organization> list, String? currentOrgId) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text(
          AppStrings.orgSubtitle,
          style: TextStyle(
              fontSize: 12.5, height: 1.45, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _searchController,
          onChanged: (v) =>
              ref.read(organizationSearchProvider.notifier).state = v,
          decoration: InputDecoration(
            hintText: AppStrings.orgSearchHint,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            isDense: true,
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.divider),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (list.isEmpty)
          const _Message(
            icon: Icons.domain_outlined,
            text: '${AppStrings.orgEmpty}\n\n${AppStrings.orgEmptyBody}',
          )
        else
          for (final org in list) ...[
            _OrgCard(
              org: org,
              isCurrent: org.id == currentOrgId,
              busy: _busy,
              onEdit: () => _openForm(existing: org),
              onSwitch: () => _switchTo(org),
              onOpen: () => _open(org),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Future<void> _openForm({Organization? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _OrgForm(existing: existing),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              existing == null ? AppStrings.orgCreated : AppStrings.orgUpdated),
        ),
      );
    }
  }

  /// Drills into a tenant: switch into it, then show its employee list.
  ///
  /// There is no way to list another organisation's employees without being
  /// scoped to it — `GET /employees` filters by the `organizationId` claim in
  /// the caller's token, not by a parameter — so "open" genuinely means
  /// "switch". That is a session-wide change, hence the confirmation: the user
  /// is not filtering a view, they are moving the whole app to another tenant.
  ///
  /// Already inside it, this is a plain navigation with no token round-trip.
  ///
  /// Uses `go`, NOT `push`. [AppRoutes.hrEmployees] is a StatefulShellBranch of
  /// the HR shell, and pushing a shell-branch route builds a SECOND copy of
  /// that shell — so its `GlobalKey<NavigatorState>` ends up in the tree twice
  /// and Flutter throws "A GlobalKey was used multiple times inside one
  /// widget's child list". `go` moves to the location instead, entering the
  /// existing shell with the Employees tab selected. (The router says as much
  /// at its StatefulShellRoute: push routes live OUTSIDE the shell. This screen
  /// is one of those; the employees list is not.)
  Future<void> _open(Organization org) async {
    final isCurrent = org.id == ref.read(currentOrganizationIdProvider);
    if (isCurrent) {
      context.go(AppRoutes.hrEmployees);
      return;
    }

    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.orgOpenTitle,
      message: '${AppStrings.orgOpenMessage}\n\n${org.name}',
      confirmLabel: AppStrings.orgOpenConfirm,
      cancelLabel: AppStrings.commonCancel,
      icon: Icons.groups_rounded,
      accentColor: AppColors.primaryPurple,
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(organizationActionsProvider).switchTo(org.id);
      if (!mounted) return;
      context.go(AppRoutes.hrEmployees);
    } catch (e) {
      if (mounted) _reportSwitchFailure(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reportSwitchFailure(Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isMissingApi(e)
            ? AppStrings.orgApiMissing
            : '${AppStrings.orgSwitchFailed} '
                '${e is ApiError ? e.combinedMessage : e}'),
      ),
    );
  }

  Future<void> _switchTo(Organization org) async {
    if (org.id == ref.read(currentOrganizationIdProvider)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.orgAlreadyCurrent)),
      );
      return;
    }

    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.orgSwitchTitle,
      message: '${AppStrings.orgSwitchMessage}\n\n${org.name}',
      confirmLabel: AppStrings.orgSwitchConfirm,
      cancelLabel: AppStrings.commonCancel,
      icon: Icons.swap_horiz_rounded,
      accentColor: AppColors.primaryPurple,
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(organizationActionsProvider).switchTo(org.id);
      if (!mounted) return;
      // The whole app is now scoped to a different tenant, so anything cached
      // from the previous one is wrong. Bounce to the HR home rather than
      // leaving the user on a list built for the old organization.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.orgSwitchDone)),
      );
      context.go(AppRoutes.hrHome);
    } catch (e) {
      if (mounted) _reportSwitchFailure(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _OrgCard extends StatelessWidget {
  final Organization org;
  final bool isCurrent;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onSwitch;
  final VoidCallback onOpen;

  const _OrgCard({
    required this.org,
    required this.isCurrent,
    required this.busy,
    required this.onEdit,
    required this.onSwitch,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      // The whole card opens the tenant — tapping a row to drill into it is the
      // expectation, and the explicit actions below stay for discoverability.
      onTap: busy ? null : onOpen,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isCurrent
                ? AppColors.primaryPurple.withValues(alpha: 0.55)
                : AppColors.divider,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    org.name.isEmpty ? org.slug : org.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
                if (isCurrent)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryPurple.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      AppStrings.orgCurrentBadge,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryPurple,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              org.slug,
              style: TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                  color: AppColors.textMuted),
            ),
            // Shown on EVERY card, not only the non-default one. The flow decides
            // who may rate at all, so "which pipeline is this tenant on?" should
            // be answerable without opening the editor — and a badge that only
            // appears sometimes leaves you unsure whether the others are standard
            // or simply unlabelled.
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (org.reviewFlow == ReviewFlow.standard
                            ? AppColors.textMuted
                            : AppColors.accentOrange)
                        .withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${AppStrings.orgFlowLabel}: ${org.reviewFlow.displayName}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: org.reviewFlow == ReviewFlow.standard
                          ? AppColors.textSecondary
                          : AppColors.accentOrange,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.groups_outlined,
                    size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 5),
                Text(
                  AppStrings.orgEmployeeCount(org.employeeCount),
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton.icon(
                  onPressed: busy ? null : onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text(AppStrings.commonEdit),
                ),
                const Spacer(),
                if (isCurrent)
                  TextButton.icon(
                    onPressed: busy ? null : onOpen,
                    icon: const Icon(Icons.groups_rounded, size: 16),
                    label: const Text(AppStrings.orgViewPeople),
                  )
                else
                  TextButton.icon(
                    onPressed: busy ? null : onSwitch,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                    label: const Text(AppStrings.orgSwitchAction),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Create / edit form. Slug is validated locally against the same shape the
/// server enforces, so an obviously bad value is caught before a round-trip.
class _OrgForm extends ConsumerStatefulWidget {
  final Organization? existing;
  const _OrgForm({this.existing});

  @override
  ConsumerState<_OrgForm> createState() => _OrgFormState();
}

class _OrgFormState extends ConsumerState<_OrgForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _slug;
  late final TextEditingController _logo;
  bool _saving = false;
  String? _serverError;
  late ReviewFlow _flow;

  /// Mirrors the server's regex exactly (organizations.routes.js): lowercase
  /// letters and digits in hyphen-separated groups, no leading, trailing or
  /// doubled hyphens.
  static final _slugPattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _slug = TextEditingController(text: widget.existing?.slug ?? '');
    _logo = TextEditingController(text: widget.existing?.logoUrl ?? '');
    // Existing organizations keep whatever they have; new ones start on the
    // standard pipeline, which is what every organization ran before this
    // setting existed.
    _flow = widget.existing?.reviewFlow ?? ReviewFlow.standard;
  }

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _logo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEdit ? AppStrings.orgEdit : AppStrings.orgAdd,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: AppStrings.orgNameLabel,
                hintText: AppStrings.orgNameHint,
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? AppStrings.orgNameRequired
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _slug,
              decoration: const InputDecoration(
                labelText: AppStrings.orgSlugLabel,
                hintText: AppStrings.orgSlugHint,
                helperText: AppStrings.orgSlugHelp,
                helperMaxLines: 3,
              ),
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.isEmpty) return AppStrings.orgSlugRequired;
                if (!_slugPattern.hasMatch(s)) return AppStrings.orgSlugInvalid;
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _logo,
              decoration: const InputDecoration(
                labelText: AppStrings.orgLogoLabel,
              ),
            ),
            const SizedBox(height: 18),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                AppStrings.orgFlowLabel,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              AppStrings.orgFlowHelp,
              style: TextStyle(
                  fontSize: 11.5, height: 1.4, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            // A radio list rather than a dropdown: the two pipelines differ in
            // WHO rates, which needs a sentence each to be an informed choice.
            for (final f in ReviewFlow.values)
              RadioListTile<ReviewFlow>(
                value: f,
                // ignore: deprecated_member_use
                groupValue: _flow,
                // ignore: deprecated_member_use
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _flow = v ?? ReviewFlow.standard),
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeColor: AppColors.primaryPurple,
                title: Text(f.displayName,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                subtitle: Text(
                  f.description,
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: AppColors.textSecondary),
                ),
              ),
            if (_serverError != null) ...[
              const SizedBox(height: 12),
              Text(
                _serverError!,
                style: const TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(_isEdit ? AppStrings.commonSave : AppStrings.orgAdd),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _serverError = null;
    });
    try {
      final actions = ref.read(organizationActionsProvider);
      final logo = _logo.text.trim();
      if (_isEdit) {
        await actions.update(
          widget.existing!.id,
          name: _name.text,
          slug: _slug.text,
          logoUrl: logo.isEmpty ? null : logo,
          // An emptied field means "remove the logo", which the server only
          // honours as an explicit null.
          clearLogo:
              logo.isEmpty && (widget.existing!.logoUrl ?? '').isNotEmpty,
          // Only when changed, so a rename cannot silently re-assert a flow
          // against a server that does not know the field.
          reviewFlow: _flow == widget.existing!.reviewFlow ? null : _flow,
        );
      } else {
        await actions.create(
          name: _name.text,
          slug: _slug.text,
          logoUrl: logo.isEmpty ? null : logo,
          reviewFlow: _flow,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // 409 is specifically the unique-slug collision, which belongs on the
        // slug field rather than as a generic failure.
        final conflict = e is ApiError && e.statusCode == 409;
        _serverError = conflict
            ? AppStrings.orgSlugTaken
            : (e is ApiError && (e.statusCode == 404 || e.code == 'RES_001')
                ? AppStrings.orgApiMissing
                : (e is ApiError ? e.combinedMessage : 'Could not save.'));
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onRetry;
  const _Message({required this.icon, required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: AppColors.textMuted),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13, height: 1.5, color: AppColors.textSecondary),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text(AppStrings.commonRetry),
            ),
          ],
        ],
      ),
    );
  }
}
