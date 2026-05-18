import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_strings.dart';
import '../../../../../core/network/connectivity_service.dart';
import '../../../../../core/router/app_router.dart';
import '../../../../../core/widgets/shimmer_skeletons.dart';
import '../../../../hr/presentation/widgets/confirm_action_dialog.dart';
import '../../../data/models/employee_profile.dart';
import '../../providers/my_profile_providers.dart';

/// Limited edit screen — only `phone` is user-editable per spec.
/// Photo upload is reserved for a future stage; we show a "Coming
/// soon" placeholder so the user knows it's planned.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() =>
      _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  String _originalPhone = '';
  bool _seeded = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _seedFrom(EmployeeProfile profile) {
    if (_seeded) return;
    _seeded = true;
    _originalPhone = profile.phone ?? '';
    _phoneController.text = _originalPhone;
  }

  bool get _isDirty => _phoneController.text.trim() != _originalPhone;

  String? _validatePhone(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null; // optional
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10) {
      return AppStrings.profileEditPhoneInvalid;
    }
    return null;
  }

  Future<bool> _confirmDiscardIfDirty() async {
    if (!_isDirty) return true;
    final ok = await ConfirmActionDialog.show(
      context,
      title: AppStrings.employeeFormUnsavedTitle,
      message: AppStrings.employeeFormUnsavedMessage,
      confirmLabel: AppStrings.commonDiscard,
      cancelLabel: AppStrings.commonCancel,
      icon: Icons.edit_note_rounded,
      accentColor: AppColors.error,
    );
    return ok == true;
  }

  Future<void> _onSave() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final newPhone = _phoneController.text.trim();
    final changes = <String, dynamic>{
      if (newPhone != _originalPhone) 'phone': newPhone,
    };
    if (changes.isEmpty) {
      if (!mounted) return;
      context.go(AppRoutes.employeeProfile);
      return;
    }
    final ok =
        await ref.read(myProfileEditProvider.notifier).save(changes);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.profileEditSaved)),
      );
      context.go(AppRoutes.employeeProfile);
    } else {
      final err = ref.read(myProfileEditProvider).error;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err)),
        );
        ref.read(myProfileEditProvider.notifier).clearError();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myProfileProvider);
    final edit = ref.watch(myProfileEditProvider);
    final isOnline = ref.watch(connectivityProvider).maybeWhen(
          data: (v) => v,
          orElse: () => true,
        );

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscardIfDirty()) {
          if (!context.mounted) return;
          context.go(AppRoutes.employeeProfile);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text(
            AppStrings.profileEditTitle,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () async {
              if (await _confirmDiscardIfDirty() && context.mounted) {
                context.go(AppRoutes.employeeProfile);
              }
            },
          ),
        ),
        body: async.when(
          loading: () => const _Loading(),
          error: (e, _) => _Error(
            message: e.toString(),
            onRetry: () => ref.invalidate(myProfileProvider),
          ),
          data: (profile) {
            _seedFrom(profile);
            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  // ── Photo placeholder ──
                  _PhotoPlaceholder(profile: profile),
                  const SizedBox(height: 24),

                  // ── Phone field ──
                  const Text(
                    AppStrings.profileFieldPhone,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9 \-+]')),
                      LengthLimitingTextInputFormatter(16),
                    ],
                    validator: _validatePhone,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: '10-digit mobile number',
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: AppColors.divider, width: 1),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: AppColors.divider, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.primaryPurple,
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    !_isDirty || edit.isSubmitting || !isOnline
                        ? null
                        : _onSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      AppColors.primaryPurple.withValues(alpha: 0.25),
                  disabledForegroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: edit.isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        AppStrings.commonSave,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Pieces
// ─────────────────────────────────────────────────────────────────────

class _PhotoPlaceholder extends StatelessWidget {
  final EmployeeProfile profile;
  const _PhotoPlaceholder({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primaryPurple.withValues(alpha: 0.12),
            ),
            child: const Icon(
              Icons.add_a_photo_outlined,
              color: AppColors.primaryPurple,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStrings.profileEditPhotoLabel,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  AppStrings.profileEditPhotoComingSoon,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        ProfileHeaderSkeleton(),
        SizedBox(height: 14),
        DashboardCardSkeleton(),
      ],
    );
  }
}

class _Error extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _Error({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 44,
              color: AppColors.error,
            ),
            const SizedBox(height: 12),
            const Text(
              AppStrings.errorGeneric,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(AppStrings.commonRetry),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryPurple,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
