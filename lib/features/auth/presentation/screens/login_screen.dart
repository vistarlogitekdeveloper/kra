import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_assets.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/network/connectivity_service.dart';
import '../../../../core/widgets/connectivity_wrapper.dart';
import '../providers/auth_providers.dart';
import '../widgets/branded_primary_button.dart';
import '../widgets/branded_text_field.dart';
import '../widgets/gradient_blobs_background.dart';

/// Email pattern — RFC 5322 simplified. Matches the common cases without
/// the false-rejection rate of stricter regexes.
final RegExp _emailRegex = RegExp(
  r'^[\w.+-]+@([\w-]+\.)+[\w-]{2,}$',
);

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  bool _obscurePassword = true;
  bool _rememberMe = true;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    _animController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _onLoginPressed() {
    FocusScope.of(context).unfocus();
    ref.read(authStateProvider.notifier).clearError();
    if (!_formKey.currentState!.validate()) return;

    ref.read(authStateProvider.notifier).login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final isLoading = authState is AuthLoading;
    final errorMessage = authState is AuthError ? authState.message : null;

    final connectivity = ref.watch(connectivityProvider);
    final isOnline = connectivity.maybeWhen(
      data: (online) => online,
      orElse: () => true,
    );

    return ConnectivityWrapper(
      child: Scaffold(
        body: Stack(
          children: [
            const GradientBlobsBackground(),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 720;
                  return Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: isWide ? 32 : 24,
                        vertical: 24,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: FadeTransition(
                          opacity: _fadeAnim,
                          child: SlideTransition(
                            position: _slideAnim,
                            child: _buildLoginCard(
                              isLoading: isLoading,
                              isOnline: isOnline,
                              errorMessage: errorMessage,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginCard({
    required bool isLoading,
    required bool isOnline,
    required String? errorMessage,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.6),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryPurple.withValues(alpha: 0.08),
            blurRadius: 40,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 32),
            BrandedTextField(
              controller: _emailController,
              label: AppStrings.loginEmailLabel,
              hint: AppStrings.loginEmailHint,
              prefixIcon: Icons.person_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.username],
              autofocus: true,
              onSubmitted: (_) => _passwordFocus.requestFocus(),
              validator: _validateEmail,
            ),
            const SizedBox(height: 18),
            BrandedTextField(
              controller: _passwordController,
              focusNode: _passwordFocus,
              label: AppStrings.loginPasswordLabel,
              hint: AppStrings.loginPasswordHint,
              prefixIcon: Icons.lock_outline_rounded,
              obscureText: _obscurePassword,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _onLoginPressed(),
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
                splashRadius: 20,
              ),
              validator: _validatePassword,
            ),
            const SizedBox(height: 14),
            _buildOptionsRow(),
            if (errorMessage != null) ...[
              const SizedBox(height: 16),
              _LoginErrorBanner(message: errorMessage),
            ],
            const SizedBox(height: 24),
            BrandedPrimaryButton(
              label: AppStrings.loginButton,
              onPressed: isOnline ? _onLoginPressed : null,
              isLoading: isLoading,
              icon: Icons.arrow_forward_rounded,
            ),
            if (!isOnline) ...[
              const SizedBox(height: 10),
              const Text(
                AppStrings.offlineLoginDisabled,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 22),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  String? _validateEmail(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return AppStrings.validationEmailRequired;
    if (!_emailRegex.hasMatch(v)) return AppStrings.validationEmailInvalid;
    return null;
  }

  String? _validatePassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return AppStrings.validationPasswordRequired;
    if (v.length < 8) return AppStrings.validationPasswordTooShort;
    return null;
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.accentOrange.withValues(alpha: 0.18),
                blurRadius: 30,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Image.asset(
            AppAssets.logo,
            height: 92,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox(
              height: 92,
              width: 92,
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          AppStrings.loginWelcome,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          AppStrings.loginSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w400,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildOptionsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        InkWell(
          onTap: () => setState(() => _rememberMe = !_rememberMe),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 22,
                  width: 22,
                  child: Checkbox(
                    value: _rememberMe,
                    onChanged: (val) =>
                        setState(() => _rememberMe = val ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  AppStrings.loginRememberMe,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(AppStrings.loginForgotComingSoon),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(AppStrings.loginForgotPassword),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 1,
                color: AppColors.divider,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                AppStrings.companyName,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            Expanded(
              child: Container(
                height: 1,
                color: AppColors.divider,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          AppStrings.loginFooter,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _LoginErrorBanner extends StatelessWidget {
  final String message;
  const _LoginErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.error.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
