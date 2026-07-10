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

/// Requests a password-reset email. The backend returns the same response
/// whether or not the address exists (no account enumeration), so success
/// always shows the same confirmation.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _submitting = false;
  String? _error;
  String? _successMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      final message = await ref
          .read(authRepositoryProvider)
          .forgotPassword(_emailController.text.trim());
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
      title: AppStrings.forgotTitle,
      subtitle: AppStrings.forgotSubtitle,
      child: _successMessage != null
          ? _buildSuccess()
          : _buildForm(),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrandedTextField(
            controller: _emailController,
            label: AppStrings.loginEmailLabel,
            hint: AppStrings.loginEmailHint,
            prefixIcon: Icons.person_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username],
            autofocus: true,
            onSubmitted: (_) => _submit(),
            validator: (v) {
              final s = (v ?? '').trim();
              if (s.isEmpty) return AppStrings.validationEmailRequired;
              return null;
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            AuthErrorBanner(message: _error!),
          ],
          const SizedBox(height: 24),
          BrandedPrimaryButton(
            label: AppStrings.forgotSubmit,
            onPressed: _submitting ? null : _submit,
            isLoading: _submitting,
            icon: Icons.mail_outline_rounded,
          ),
          const SizedBox(height: 14),
          _backToLogin(),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.mark_email_read_outlined,
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
          label: AppStrings.resetSubmit,
          onPressed: () => context.go(AppRoutes.resetPassword),
          icon: Icons.arrow_forward_rounded,
        ),
        const SizedBox(height: 14),
        _backToLogin(),
      ],
    );
  }

  Widget _backToLogin() {
    return TextButton(
      onPressed: () => context.go(AppRoutes.login),
      child: const Text(AppStrings.forgotBackToLogin),
    );
  }
}
