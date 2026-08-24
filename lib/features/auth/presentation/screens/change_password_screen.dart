import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../data/repositories/auth_repository.dart';
import '../providers/auth_providers.dart';
import '../widgets/branded_primary_button.dart';
import '../widgets/branded_text_field.dart';
import 'auth_scaffold.dart' show AuthErrorBanner;

/// Lets a SIGNED-IN user change their own password.
///
/// Distinct from the reset flow, which is for people who are locked out and
/// proves identity with an emailed token. Here the user is already
/// authenticated, so intent is proved with their current password instead —
/// verified server-side, so an unlocked borrowed phone is not enough to take
/// an account over.
///
/// A normal in-app screen rather than the login-style [AuthScaffold]: it is
/// reached from Profile, and keeping the app chrome means the back button and
/// bottom navigation behave like every other settings page.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: _currentController.text,
            newPassword: _newController.text,
          );
      if (!mounted) return;
      // Deliberately NOT signing the user out. The session's tokens stay valid
      // server-side, and forcing a re-login here would look like the change had
      // failed. They simply return to Profile with a confirmation.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.changePasswordSuccess)),
      );
      context.pop();
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = AppStrings.errorGeneric);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.changePasswordTitle),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  AppStrings.changePasswordSubtitle,
                  style:
                      TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 22),
                BrandedTextField(
                  controller: _currentController,
                  label: AppStrings.changePasswordCurrentLabel,
                  hint: AppStrings.loginPasswordHint,
                  prefixIcon: Icons.lock_clock_outlined,
                  obscureText: _obscure,
                  keyboardType: TextInputType.visiblePassword,
                  validator: (v) => (v ?? '').isEmpty
                      ? AppStrings.validationPasswordRequired
                      : null,
                ),
                const SizedBox(height: 18),
                BrandedTextField(
                  controller: _newController,
                  label: AppStrings.changePasswordNewLabel,
                  hint: AppStrings.loginPasswordHint,
                  prefixIcon: Icons.lock_outline_rounded,
                  obscureText: _obscure,
                  keyboardType: TextInputType.visiblePassword,
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                    ),
                    splashRadius: 20,
                  ),
                  validator: (v) {
                    final s = v ?? '';
                    if (s.isEmpty) return AppStrings.validationPasswordRequired;
                    // Matches the server's own floor (min 8), so a rejection
                    // never has to round-trip.
                    if (s.length < 8) {
                      return AppStrings.validationPasswordTooShort;
                    }
                    if (s == _currentController.text) {
                      return AppStrings.changePasswordSameAsOld;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                BrandedTextField(
                  controller: _confirmController,
                  label: AppStrings.changePasswordConfirmLabel,
                  hint: AppStrings.loginPasswordHint,
                  prefixIcon: Icons.lock_outline_rounded,
                  obscureText: _obscure,
                  keyboardType: TextInputType.visiblePassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  validator: (v) => (v ?? '') != _newController.text
                      ? AppStrings.resetPasswordsDontMatch
                      : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  AuthErrorBanner(message: _error!),
                ],
                const SizedBox(height: 26),
                BrandedPrimaryButton(
                  label: AppStrings.changePasswordSubmit,
                  onPressed: _submitting ? null : _submit,
                  isLoading: _submitting,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
