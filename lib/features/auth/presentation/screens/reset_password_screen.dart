import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/router/app_router.dart';
import '../../data/repositories/auth_repository.dart';
import '../providers/auth_providers.dart';
import '../widgets/branded_primary_button.dart';
import '../widgets/branded_text_field.dart';
import 'auth_scaffold.dart';

/// Completes a password reset with the token from the emailed link
/// (`/reset-password?token=...`). The token is pre-filled but editable so a
/// user who received a code can paste it manually.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  final String? token;
  const ResetPasswordScreen({super.key, this.token});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _tokenController;
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscure = true;
  bool _submitting = false;
  String? _error;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(text: widget.token ?? '');
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      final message = await ref.read(authRepositoryProvider).resetPassword(
            token: _tokenController.text.trim(),
            password: _passwordController.text,
          );
      if (!mounted) return;
      setState(() => _successMessage = message);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: AppStrings.resetTitle,
      subtitle: AppStrings.resetSubtitle,
      child: _successMessage != null ? _buildSuccess() : _buildForm(),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrandedTextField(
            controller: _tokenController,
            label: AppStrings.resetTokenLabel,
            hint: AppStrings.resetTokenHint,
            prefixIcon: Icons.key_outlined,
            validator: (v) => (v ?? '').trim().isEmpty
                ? AppStrings.resetTokenRequired
                : null,
          ),
          const SizedBox(height: 18),
          BrandedTextField(
            controller: _passwordController,
            label: AppStrings.resetNewPasswordLabel,
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
              if (s.length < 8) return AppStrings.validationPasswordTooShort;
              return null;
            },
          ),
          const SizedBox(height: 18),
          BrandedTextField(
            controller: _confirmController,
            label: AppStrings.resetConfirmPasswordLabel,
            hint: AppStrings.loginPasswordHint,
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: _obscure,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            validator: (v) => (v ?? '') != _passwordController.text
                ? AppStrings.resetPasswordsDontMatch
                : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            AuthErrorBanner(message: _error!),
          ],
          const SizedBox(height: 24),
          BrandedPrimaryButton(
            label: AppStrings.resetSubmit,
            onPressed: _submitting ? null : _submit,
            isLoading: _submitting,
            icon: Icons.check_rounded,
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: () => context.go(AppRoutes.login),
            child: const Text(AppStrings.forgotBackToLogin),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle_outline_rounded,
            color: AppColors.success, size: 44),
        const SizedBox(height: 16),
        Text(
          _successMessage!,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        BrandedPrimaryButton(
          label: AppStrings.loginButton,
          onPressed: () => context.go(AppRoutes.login),
          icon: Icons.arrow_forward_rounded,
        ),
      ],
    );
  }
}
