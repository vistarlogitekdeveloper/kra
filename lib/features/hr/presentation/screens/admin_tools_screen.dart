import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/router/app_router.dart';
import '../../../auth/data/models/user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/models/bulk_operation_result.dart';
import '../providers/employee_providers.dart';
import '../providers/review_cycle_providers.dart';

/// Danger Zone — admin-only bulk-destruction surface.
///
/// Hosts three irreversible actions:
///   1. Reset every employee's monthly incentive amount to 0
///   2. Delete every review cycle
///   3. Deactivate every active employee
///
/// Each action is gated by a typed confirmation field (must match a
/// specific phrase) to defend against a misclick wiping the org.
/// Reachable only via [AppRoutes.hrAdminTools] which the router and the
/// HR home quick-actions tile both restrict to HR_ADMIN / ADMIN.
class AdminToolsScreen extends ConsumerStatefulWidget {
  const AdminToolsScreen({super.key});

  @override
  ConsumerState<AdminToolsScreen> createState() => _AdminToolsScreenState();
}

class _AdminToolsScreenState extends ConsumerState<AdminToolsScreen> {
  // Tracks which action (if any) is in-flight so we can disable every
  // other tile while one is running. Avoids racing PATCHes against
  // DELETEs against the same employee row.
  String? _runningAction;

  @override
  Widget build(BuildContext context) {
    // Belt-and-braces role check inside the screen even though the router
    // restricts the route — keeps a copy-paste of the route constant
    // elsewhere from accidentally exposing it.
    final authState = ref.watch(authStateProvider);
    final user =
        authState is AuthAuthenticated ? authState.user : null;
    final allowed = user != null && _canAccessAdminTools(user.role);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Admin tools'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: allowed ? _buildBody() : _buildForbidden(),
    );
  }

  Widget _buildForbidden() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'You don\'t have permission to access admin tools.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        _DangerHeader(),
        const SizedBox(height: 18),
        _DangerCard(
          title: 'Delete all performance incentives',
          subtitle:
              'Resets the monthly incentive amount to ₹0 on every active '
              'employee. Configured bonus-slab tiers are not affected.',
          buttonLabel: 'Delete all incentive amounts',
          confirmationPhrase: 'DELETE INCENTIVES',
          isRunning: _runningAction == 'incentives',
          isDisabled:
              _runningAction != null && _runningAction != 'incentives',
          onConfirmed: () => _run('incentives', () async {
            return ref
                .read(employeeRepositoryProvider)
                .clearAllIncentiveAmounts();
          }),
        ),
        const SizedBox(height: 14),
        _DangerCard(
          title: 'Delete all review cycles',
          subtitle:
              'Permanently removes every review cycle. KRA assignments + '
              'reviews tied to those cycles will also be removed by the '
              'backend\'s cascade.',
          buttonLabel: 'Delete all cycles',
          confirmationPhrase: 'DELETE CYCLES',
          isRunning: _runningAction == 'cycles',
          isDisabled: _runningAction != null && _runningAction != 'cycles',
          onConfirmed: () => _run('cycles', () async {
            return ref
                .read(reviewCycleRepositoryProvider)
                .deleteAll();
          }),
        ),
        const SizedBox(height: 14),
        _DangerCard(
          title: 'Delete all employees',
          subtitle:
              'Deactivates every active employee (soft delete — sets '
              'isActive=false). Employees stay in the database for audit '
              'but disappear from all lists and can no longer log in.',
          buttonLabel: 'Delete all employees',
          confirmationPhrase: 'DELETE EMPLOYEES',
          isRunning: _runningAction == 'employees',
          isDisabled:
              _runningAction != null && _runningAction != 'employees',
          onConfirmed: () => _run('employees', () async {
            return ref.read(employeeRepositoryProvider).deactivateAll();
          }),
        ),
      ],
    );
  }

  Future<void> _run(
    String key,
    Future<BulkOperationResult> Function() action,
  ) async {
    setState(() => _runningAction = key);
    BulkOperationResult? result;
    String? error;
    try {
      result = await action();
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => _runningAction = null);
    }
    // Re-fetch the dependent lists so the rest of the app reflects
    // reality after a bulk wipe.
    ref.invalidate(employeeListProvider);
    ref.invalidate(reviewCyclesProvider);

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (error != null) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: Text('Operation failed: $error'),
        ),
      );
      return;
    }
    if (result == null) return;
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: result.isFullyClean
            ? AppColors.success.withValues(alpha: 0.95)
            : AppColors.warning.withValues(alpha: 0.95),
        content: Text(_formatResult(result)),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  String _formatResult(BulkOperationResult r) {
    if (r.totalAttempted == 0) return 'Nothing to delete — list was empty.';
    if (r.isFullyClean) {
      return 'Done — ${r.successCount} row${r.successCount == 1 ? '' : 's'} '
          'processed cleanly.';
    }
    final preview =
        r.failures.isEmpty ? '' : ' (e.g. ${r.failures.join(', ')})';
    return '${r.successCount} succeeded, '
        '${r.failureCount} failed$preview.';
  }
}

/// Admin-tools is tighter than the rest of `/hr/*`. Regular HR users can
/// read dashboards but only HR_ADMIN + ADMIN can wipe data. Exposed at
/// library scope so [AppRouter]'s redirect uses the same predicate the
/// quick-actions tile + this screen do — single source of truth.
bool canAccessAdminTools(UserRole role) =>
    role == UserRole.admin || role == UserRole.hrAdmin;

bool _canAccessAdminTools(UserRole role) => canAccessAdminTools(role);

class _DangerHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              color: AppColors.error, size: 22),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'These actions are irreversible. Read each card carefully, '
              'type the confirmation phrase exactly, and check the result '
              'summary before walking away.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DangerCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String buttonLabel;
  final String confirmationPhrase;
  final bool isRunning;
  final bool isDisabled;
  final VoidCallback onConfirmed;

  const _DangerCard({
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.confirmationPhrase,
    required this.isRunning,
    required this.isDisabled,
    required this.onConfirmed,
  });

  @override
  State<_DangerCard> createState() => _DangerCardState();
}

class _DangerCardState extends State<_DangerCard> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phraseMatches = _controller.text.trim() == widget.confirmationPhrase;
    final canFire = phraseMatches && !widget.isRunning && !widget.isDisabled;

    return Opacity(
      opacity: widget.isDisabled ? 0.55 : 1.0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.error.withValues(alpha: 0.30),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.subtitle,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            Text.rich(
              TextSpan(
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
                children: [
                  const TextSpan(text: 'Type '),
                  TextSpan(
                    text: widget.confirmationPhrase,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.error,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const TextSpan(text: ' to enable the button.'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              enabled: !widget.isDisabled && !widget.isRunning,
              onChanged: (_) => setState(() {}),
              autocorrect: false,
              decoration: InputDecoration(
                hintText: widget.confirmationPhrase,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              style: const TextStyle(
                fontFamily: 'monospace',
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: canFire ? widget.onConfirmed : null,
                icon: widget.isRunning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Icon(Icons.delete_forever_rounded, size: 18),
                label: Text(
                  widget.isRunning ? 'Working…' : widget.buttonLabel,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      AppColors.error.withValues(alpha: 0.25),
                  disabledForegroundColor:
                      Colors.white.withValues(alpha: 0.6),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
