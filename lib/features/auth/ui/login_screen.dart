import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../providers/notifiers/auth_notifier.dart';
import '../providers/onboarding_provider.dart';
import '../providers/signup_state_provider.dart';
import '../utils/auth_error_messages.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isSignUp = !_isSignUp;
      _errorMessage = null;
      _passwordController.clear();
    });
  }

  void _clearError() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  Future<void> _submit() async {
    _clearError();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final notifier = ref.read(authNotifierProvider.notifier);

    if (_isSignUp) {
      try {
        await notifier.signUpWithEmail(email: email, password: password);
        // Only set onboarding flag after signup succeeds.
        if (mounted && !ref.read(authNotifierProvider).hasError) {
          ref.read(needsOnboardingProvider.notifier).state = true;
        }
      } catch (_) {
        // Error is surfaced via authNotifierProvider listener.
        return;
      }
      _finishAutofillIfSucceeded();
      // If signup succeeded and email confirmation is pending, navigate.
      if (mounted && ref.read(signupPendingEmailProvider) != null) {
        context.go('/email-confirmation');
      }
    } else {
      await notifier.signInWithEmail(email: email, password: password);
      _finishAutofillIfSucceeded();
    }
  }

  /// Closes the [AutofillGroup] context after a successful submission so the
  /// OS surfaces its save-credentials prompt — Android Credential Manager on
  /// API 34+, the iOS Passwords sheet on iOS 12+. Only fires when the
  /// notifier did NOT land in [AsyncError]; a failed sign-in / sign-up must
  /// not trigger the OS save flow with the wrong credentials. The call is a
  /// pure platform-channel message (`TextInput.finishAutofillContext`) — it
  /// does not emit `AuthChangeEvent`s, so `_RouterRefreshListenable` and the
  /// `authStateProvider` redirect chain are untouched.
  void _finishAutofillIfSucceeded() {
    if (!mounted) return;
    if (ref.read(authNotifierProvider).hasError) return;
    TextInput.finishAutofillContext();
  }

  Future<void> _signInWithGoogle() async {
    _clearError();
    await ref.read(authNotifierProvider.notifier).signInWithGoogle();
  }

  Future<void> _forgotPassword() async {
    final l10n = AppLocalizations.of(context);
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _errorMessage = l10n.forgotPasswordHint;
      });
      return;
    }
    _clearError();

    // Show confirmation dialog before sending reset email (QA-006).
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dialogTheme = Theme.of(ctx);
        return AlertDialog(
          backgroundColor: dialogTheme.cardTheme.color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(l10n.resetPassword),
          content: Text(l10n.sendResetEmailTo(email)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            Semantics(
              container: true,
              identifier: 'auth-send-reset',
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.sendResetEmail),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    await ref.read(authNotifierProvider.notifier).resetPassword(email);
    if (mounted && !ref.read(authNotifierProvider).hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.resetEmailSent),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  static final _emailRegex = RegExp(r'^[\w\-.+]+@([\w\-]+\.)+[\w\-]{2,}$');

  String? _validateEmail(String? value) {
    final l10n = AppLocalizations.of(context);
    if (value == null || value.trim().isEmpty) return l10n.emailRequired;
    if (!_emailRegex.hasMatch(value.trim())) return l10n.emailInvalid;
    return null;
  }

  String? _validatePassword(String? value) {
    final l10n = AppLocalizations.of(context);
    if (value == null || value.isEmpty) return l10n.passwordRequired;
    if (value.length < 6) return l10n.passwordTooShort;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.isLoading;

    // Show user-friendly error on auth failure.
    ref.listen(authNotifierProvider, (prev, next) {
      if (next.hasError && !next.isLoading) {
        setState(() {
          _errorMessage = AuthErrorMessages.fromError(next.error!, l10n);
        });
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Form(
              key: _formKey,
              // AutofillGroup binds the email + password fields into a single
              // OS-level autofill scope. On successful submit `_submit` calls
              // `TextInput.finishAutofillContext`, which prompts Android
              // Credential Manager (API 34+) / iOS Passwords sheet to save
              // the just-entered credentials. The `disposeAction` defaults to
              // `commit`, which is what we want — saving on a clean dispose
              // would surface the prompt even after navigating away mid-flow.
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand sigil — the Arcane launcher-icon foreground. The
                    // colored composite (rune + barbell) already carries the
                    // palette, so no color tint is applied. Sized 96dp for the
                    // login header, which reads balanced against the 32dp
                    // displayMedium wordmark below.
                    Image.asset(
                      'assets/app_icon/arcane_sigil_foreground.png',
                      width: 96,
                      height: 96,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.appName,
                      style: AppTextStyles.display.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Semantics(
                      container: true,
                      identifier: 'auth-welcome-back',
                      child: Text(
                        _isSignUp ? l10n.createYourAccount : l10n.welcomeBack,
                        style: AppTextStyles.body.copyWith(
                          fontSize: 16,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 40),
                    // Inline error message
                    if (_errorMessage != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.error.withValues(
                                alpha: 0.4,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: theme.colorScheme.error,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: AppTextStyles.body.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    AppTextField(
                      label: l10n.email,
                      controller: _emailController,
                      validator: _validateEmail,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      prefixIcon: Icons.email_outlined,
                      semanticsIdentifier: 'auth-email-input',
                      autofillHints: const [AutofillHints.email],
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: l10n.password,
                      controller: _passwordController,
                      validator: _validatePassword,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      prefixIcon: Icons.lock_outlined,
                      onFieldSubmitted: (_) => _submit(),
                      semanticsIdentifier: 'auth-password-input',
                      // Login → ask Credential Manager to FILL an existing
                      // password (`AutofillHints.password`). Signup → ask it
                      // to SAVE a brand-new password
                      // (`AutofillHints.newPassword`), which the OS surfaces as
                      // a strong-password suggestion + save prompt.
                      autofillHints: _isSignUp
                          ? const [AutofillHints.newPassword]
                          : const [AutofillHints.password],
                    ),
                    if (!_isSignUp) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: Semantics(
                          container: true,
                          identifier: 'auth-forgot-pwd',
                          child: TextButton(
                            onPressed: isLoading ? null : _forgotPassword,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            child: Text(
                              l10n.forgotPassword,
                              style: AppTextStyles.body.copyWith(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.8,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    GradientButton(
                      label: _isSignUp ? l10n.signUp : l10n.logIn,
                      onPressed: isLoading ? null : _submit,
                      isLoading: isLoading,
                      semanticsIdentifier: _isSignUp
                          ? 'auth-signup-btn'
                          : 'auth-login-btn',
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            l10n.or,
                            style: AppTextStyles.body.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Semantics(
                      container: true,
                      identifier: 'auth-google-btn',
                      child: OutlinedButton.icon(
                        onPressed: isLoading ? null : _signInWithGoogle,
                        icon: SvgPicture.asset(
                          'assets/icons/google_logo.svg',
                          width: 20,
                          height: 20,
                        ),
                        label: Text(l10n.continueWithGoogle),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: BorderSide(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.3,
                            ),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Semantics(
                      container: true,
                      identifier: _isSignUp
                          ? 'auth-toggle-login'
                          : 'auth-toggle-signup',
                      child: TextButton(
                        onPressed: isLoading ? null : _toggleMode,
                        child: Text(
                          _isSignUp
                              ? l10n.alreadyHaveAccount
                              : l10n.dontHaveAccount,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _LegalFooter(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LegalFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final mutedColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final linkColor = theme.colorScheme.primary.withValues(alpha: 0.85);
    final baseStyle = AppTextStyles.bodySmall.copyWith(color: mutedColor);
    final linkStyle = AppTextStyles.bodySmall.copyWith(
      color: linkColor,
      fontWeight: FontWeight.w600,
    );

    TextButton legalButton(String label, String path) {
      return TextButton(
        onPressed: () => context.push(path),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          minimumSize: const Size(0, 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, style: linkStyle),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(l10n.legalAgreePrefix, style: baseStyle),
        legalButton(l10n.termsOfService, '/terms-of-service'),
        Text(l10n.andSeparator, style: baseStyle),
        legalButton(l10n.privacyPolicy, '/privacy-policy'),
        Text('.', style: baseStyle),
      ],
    );
  }
}
