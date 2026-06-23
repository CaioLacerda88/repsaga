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
  // Option A (full-form signup): the display name field is signup-only. It is
  // created here for the screen lifetime (cheap) but only mounted into the
  // tree when `_isSignUp`, and cleared on every mode flip so a Login -> Sign
  // Up toggle never inherits stale text.
  final _displayNameController = TextEditingController();
  bool _isSignUp = false;
  String? _errorMessage;

  // One-time per-session nudge under the signup strength bar telling the user
  // they can reveal their password. There is no confirm-password field to
  // catch typos, so the reveal toggle is the typo-safety net — this hint
  // surfaces it. Dismissed permanently (for the session) the first time the
  // user taps the eye. Local state, not Hive: per-session is sufficient.
  bool _passwordRevealHintDismissed = false;

  // Live password-strength score (0–3) for the non-blocking signup strength
  // bar. Recomputed on every password keystroke (signup mode only). Purely
  // presentational — it NEVER gates submission; `_validatePassword` (>= 6
  // chars) remains the only hard requirement.
  int _passwordStrength = 0;

  // Legal PR 2 — age-confirmation checkbox state. Local to the screen
  // (transient per signup attempt — no Hive). Required ticked before the
  // Sign Up CTA enables. Cluster: `data-protection-compliance`.
  //
  // Gated on `_isSignUp` so toggling between modes resets the value
  // (`_toggleMode` clears it explicitly). Login mode ignores the flag
  // entirely.
  bool _ageConfirmed = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isSignUp = !_isSignUp;
      _errorMessage = null;
      _passwordController.clear();
      // Clear the signup-only field so neither mode inherits the other's text.
      _displayNameController.clear();
      _passwordStrength = 0;
      // Re-arm the one-time reveal hint on a fresh signup entry.
      _passwordRevealHintDismissed = false;
      // Reset on every mode flip so a user toggling Login -> Sign Up
      // can't accidentally inherit a pre-checked state from a prior
      // mount or hot reload.
      _ageConfirmed = false;
    });
  }

  /// Pure local password-strength scoring for the non-blocking signup bar.
  /// Scoring rubric (design-locked):
  ///   * 0 — empty.
  ///   * 1 (weak)   — length >= 6.
  ///   * 2 (medium) — length >= 8 OR contains a digit OR a special char.
  ///   * 3 (strong) — length >= 8 AND a digit AND a special char.
  /// Never gates submission — `_validatePassword` is the only hard rule.
  static int passwordStrengthScore(String value) {
    if (value.isEmpty) return 0;
    final hasDigit = value.contains(RegExp(r'\d'));
    final hasSpecial = value.contains(RegExp(r'[^A-Za-z0-9]'));
    final longEnough = value.length >= 8;
    if (longEnough && hasDigit && hasSpecial) return 3;
    if (longEnough || hasDigit || hasSpecial) return 2;
    if (value.length >= 6) return 1;
    return 0;
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
      // `signUpWithEmail` wraps its work in `AsyncValue.guard`, so it
      // catches all exceptions internally and never re-throws — a
      // try/catch here would be unreachable. We gate every post-call
      // side-effect on `!hasError` so a failed signup leaves the
      // autofill commit + navigation untouched. PR 1 — the explicit
      // `needsOnboardingProvider.state = true` write that used to live
      // here is gone; onboarding-state is derived from the profile row's
      // `onboarded_at` column instead (a fresh signup has no profile row
      // until `handle_new_user` trigger fires, so the derived provider
      // returns `true` deterministically — no flag write needed).
      await notifier.signUpWithEmail(
        email: email,
        password: password,
        // Option A — collect the display name at signup so onboarding only
        // gathers fitness signals. Trimmed; the validator already enforced
        // non-empty before we got here.
        displayName: _displayNameController.text.trim(),
      );
      _finishAutofillIfSucceeded();
      // If signup succeeded and email confirmation is pending, navigate.
      if (mounted &&
          !ref.read(authNotifierProvider).hasError &&
          ref.read(signupPendingEmailProvider) != null) {
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
  /// not trigger the OS save flow with the wrong credentials. Passes
  /// `shouldSave: true` explicitly so the OS prompt is requested only here,
  /// never on a dispose-without-success (the [AutofillGroup] is configured
  /// with `onDisposeAction: cancel` for the same reason). The call is a
  /// pure platform-channel message (`TextInput.finishAutofillContext`) — it
  /// does not emit `AuthChangeEvent`s, so `_RouterRefreshListenable` and the
  /// `authStateProvider` redirect chain are untouched.
  void _finishAutofillIfSucceeded() {
    if (!mounted) return;
    if (ref.read(authNotifierProvider).hasError) return;
    TextInput.finishAutofillContext(shouldSave: true);
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
            // cluster: semantics-identifier-pair-rule — container +
            // explicitChildNodes pair prevents AOM label-merge with the
            // FilledButton's child Text node.
            Semantics(
              container: true,
              explicitChildNodes: true,
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

  /// Display-name validator (signup only). Non-empty is the only rule — no
  /// length minimum, matching the mockup's "Como quer ser chamado?" intent.
  String? _validateDisplayName(String? value) {
    final l10n = AppLocalizations.of(context);
    if (value == null || value.trim().isEmpty) return l10n.displayNameRequired;
    return null;
  }

  @override
  Widget build(BuildContext context) {
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
              // `TextInput.finishAutofillContext(shouldSave: true)`, which
              // prompts Android Credential Manager (API 34+) / iOS Passwords
              // sheet to save the just-entered credentials. We pin
              // `onDisposeAction: cancel` so abandoning the form mid-flow
              // (toggle to signup, route away, hot-reload) NEVER surfaces a
              // save prompt with partial / wrong credentials. The save flow
              // fires exclusively from our explicit
              // `finishAutofillContext(shouldSave: true)` call on success.
              child: AutofillGroup(
                onDisposeAction: AutofillContextAction.cancel,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _BrandHeader(isSignUp: _isSignUp),
                    const SizedBox(height: 40),
                    // Display name — signup only, above email. Non-empty
                    // validation only (no length minimum). Forwarded into
                    // user_metadata.display_name on signUp.
                    if (_isSignUp) ...[
                      AppTextField(
                        // Stable key: signup inserts this field ABOVE email,
                        // shifting positions. Without keys Flutter reuses
                        // sibling State by position, leaking the password
                        // field's obscured state onto email.
                        // cluster: missing-key-state-reuse.
                        key: const ValueKey('auth-display-name-field'),
                        label: l10n.displayName,
                        controller: _displayNameController,
                        validator: _validateDisplayName,
                        textInputAction: TextInputAction.next,
                        prefixIcon: Icons.person_outlined,
                        maxLength: 50,
                        showCounter: false,
                        semanticsIdentifier: 'auth-display-name-input',
                        autofillHints: const [AutofillHints.name],
                      ),
                      const SizedBox(height: 16),
                    ],
                    // Inline error message
                    if (_errorMessage != null) ...[
                      _ErrorBanner(message: _errorMessage!),
                      const SizedBox(height: 16),
                    ],
                    AppTextField(
                      key: const ValueKey('auth-email-field'),
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
                      key: const ValueKey('auth-password-field'),
                      label: l10n.password,
                      controller: _passwordController,
                      validator: _validatePassword,
                      obscureText: true,
                      // With the confirm field gone, the password field is the
                      // keyboard-submit point in BOTH modes, so "Done" closes
                      // the form. (Previously signup chained to a confirm
                      // field via TextInputAction.next.)
                      textInputAction: TextInputAction.done,
                      prefixIcon: Icons.lock_outlined,
                      // The password field now inherits the age-gate guard
                      // that used to live on the confirm field: in signup mode
                      // a keyboard "Done" must NOT bypass the unticked-age
                      // structural guarantee. Mirrors the CTA's exact gate so
                      // it is correct in both login and signup modes.
                      onFieldSubmitted:
                          isLoading || (_isSignUp && !_ageConfirmed)
                          ? null
                          : (_) => _submit(),
                      // State-aware tooltip → Material 3 reveal-eye semantics
                      // label. Localized show/hide handles.
                      obscureTooltipShow: l10n.showPassword,
                      obscureTooltipHide: l10n.hidePassword,
                      // First eye tap dismisses the one-time reveal hint.
                      onObscureToggle: _isSignUp
                          ? () {
                              if (!_passwordRevealHintDismissed) {
                                setState(
                                  () => _passwordRevealHintDismissed = true,
                                );
                              }
                            }
                          : null,
                      onChanged: _isSignUp
                          ? (value) {
                              final score = passwordStrengthScore(value);
                              if (score != _passwordStrength) {
                                setState(() => _passwordStrength = score);
                              }
                            }
                          : null,
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
                    // Non-blocking password-strength bar + tip (signup only).
                    // Purely presentational — never gates submit. The bar
                    // names the single highest-priority MISSING requirement
                    // (length -> number -> symbol) so the hint is always
                    // accurate to the typed value.
                    if (_isSignUp) ...[
                      const SizedBox(height: 8),
                      _PasswordStrengthBar(
                        score: _passwordStrength,
                        password: _passwordController.text,
                      ),
                      // One-time ghost hint: shown from the first keystroke
                      // until the user taps the eye once (regardless of the
                      // field's current obscure state — `_AppTextFieldState`
                      // owns `_obscured`, not readable here). The local
                      // `_passwordRevealHintDismissed` flips on the first
                      // `onObscureToggle` callback.
                      if (!_passwordRevealHintDismissed) ...[
                        const SizedBox(height: 6),
                        Text(
                          l10n.passwordRevealHint,
                          // Phase 38.9 T2.6: inherits bodySmall's AA textDimAA
                          // (dropped the textDim override).
                          style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
                        ),
                      ],
                    ],
                    if (!_isSignUp) ...[
                      _ForgotPasswordLink(
                        onPressed: isLoading ? null : _forgotPassword,
                      ),
                    ],
                    // Legal PR 2 — age confirmation checkbox.
                    // Cluster: `data-protection-compliance`. Shown only
                    // in signup mode. Required ticked before the Sign Up
                    // CTA enables (LGPD Art. 14 minimum-age compliance,
                    // mirrored by ToS §3 + Privacy Policy §8).
                    if (_isSignUp) ...[
                      const SizedBox(height: 8),
                      // Option A — inline the Privacy + Terms links INTO the
                      // age-gate checkbox label (one LGPD-compliant sentence)
                      // instead of an orphaned chip row. Reuses the existing
                      // `privacyPolicy` / `termsOfService` link-label strings.
                      // The links use `MaterialTapTargetSize.shrinkWrap` +
                      // `minimumSize: Size.zero` + small vertical padding so
                      // they flow inline at the 14sp line height instead of
                      // inflating the line to a 48dp tap floor (the prior
                      // 48dp min-height was what misaligned this label). The
                      // 48dp gesture target stays on the checkbox itself; the
                      // inline links are conventional sub-48dp text links.
                      Semantics(
                        container: true,
                        identifier: 'auth-age-confirmation',
                        child: Row(
                          // Top-align the checkbox box with the first text
                          // line. The Checkbox keeps a compact tap-target box
                          // (shrinkWrap) so it doesn't push the label down with
                          // its default 48dp padded box; the prior magic
                          // `Padding(top: 12)` faking alignment is gone.
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: _ageConfirmed,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              onChanged: isLoading
                                  ? null
                                  : (value) {
                                      setState(() {
                                        _ageConfirmed = value ?? false;
                                      });
                                    },
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _AgeGateLabel(
                                enabled: !isLoading,
                                onTapTerms: () =>
                                    context.push('/terms-of-service'),
                                onTapPrivacy: () =>
                                    context.push('/privacy-policy'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    GradientButton(
                      label: _isSignUp ? l10n.signUp : l10n.logIn,
                      // Legal PR 2 — gate the CTA on age confirmation in
                      // signup mode. Passing `null` to onPressed both
                      // disables the visual state and prevents the tap
                      // from dispatching, which is the structural guarantee
                      // (per the architectural rule "structural guarantees
                      // over runtime flags"). Login mode is unaffected.
                      onPressed: isLoading || (_isSignUp && !_ageConfirmed)
                          ? null
                          : _submit,
                      isLoading: isLoading,
                      semanticsIdentifier: _isSignUp
                          ? 'auth-signup-btn'
                          : 'auth-login-btn',
                    ),
                    // Helper text explaining WHY the signup CTA is disabled —
                    // the disabled GradientButton alone is a subtle cue on the
                    // dark surface. Only shown while the age-gate blocks submit.
                    if (_isSignUp && !_ageConfirmed) ...[
                      const SizedBox(height: 8),
                      Text(
                        l10n.signupAgeRequiredHint,
                        style: AppTextStyles.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 16),
                    const _OrDivider(),
                    const SizedBox(height: 16),
                    _GoogleButton(
                      onPressed: isLoading ? null : _signInWithGoogle,
                    ),
                    const SizedBox(height: 24),
                    _ModeToggleButton(
                      isSignUp: _isSignUp,
                      onPressed: isLoading ? null : _toggleMode,
                    ),
                    // Login mode keeps the bottom legal footer. In signup mode
                    // the inline age-gate checkbox label already satisfies the
                    // LGPD disclosure requirement, so the footer is suppressed
                    // to avoid duplicated Terms/Privacy link sets.
                    if (!_isSignUp) ...[
                      const SizedBox(height: 16),
                      _LegalFooter(),
                    ],
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

/// Brand header — Arcane sigil + wordmark + the login/signup mode context line.
///
/// The sigil is the colored launcher-icon foreground (no tint — the composite
/// already carries the palette), sized 96dp. The mode line preserves the
/// `auth-welcome-back` / `auth-signup-heading` identifier swap across modes so
/// the existing E2E anchors keep resolving.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.isSignUp});

  final bool isSignUp;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
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
          // Phase 38.9 T2.6: wordmark on the interactive violet (hotViolet,
          // 6.27:1) instead of primaryViolet (2.48:1 < 3.0 large-text AA).
          style: AppTextStyles.display.copyWith(color: AppColors.hotViolet),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        // Mode context line. In signup mode this is a promoted
        // Rajdhani-700 16sp "CREATE ACCOUNT" heading (full cream)
        // per Option A — it replaces the dim subtitle so the
        // login-vs-signup mode is unambiguous. In login mode it
        // stays the dim 16sp "Welcome back" subtitle. The
        // `auth-welcome-back` identifier is preserved across both
        // modes so the existing E2E anchor keeps resolving.
        Semantics(
          container: true,
          identifier: isSignUp ? 'auth-signup-heading' : 'auth-welcome-back',
          child: Text(
            isSignUp ? l10n.signupHeading : l10n.welcomeBack,
            style: isSignUp
                ? AppTextStyles.display.copyWith(fontSize: 16)
                : AppTextStyles.body.copyWith(
                    fontSize: 16,
                    // Phase 38.9 T2.6: AA dim subtitle (was onSurface@0.7).
                    color: AppColors.textDimAA,
                  ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

/// Inline error banner shown above the email field on auth failure. The error
/// text is resolved by the screen layer (`AuthErrorMessages.fromError`) and
/// passed in; this widget is pure presentation.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.error.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.body.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Right-aligned "Forgot password?" link (login mode only). Disabled (null
/// callback) while an auth request is in flight.
class _ForgotPasswordLink extends StatelessWidget {
  const _ForgotPasswordLink({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Semantics(
        container: true,
        identifier: 'auth-forgot-pwd',
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 8),
          ),
          child: Text(
            l10n.forgotPassword,
            // Phase 38.9 T2.6: interactive violet solid (was primary@0.8,
            // 1.21:1 — the worst Login offender).
            style: AppTextStyles.body.copyWith(color: AppColors.hotViolet),
          ),
        ),
      ),
    );
  }
}

/// The "OR" divider separating the email/password form from the Google CTA.
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Divider(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l10n.or,
            // Phase 38.9 T2.6: AA dim "OR" (was onSurface@0.5, 2.95:1).
            style: AppTextStyles.body.copyWith(color: AppColors.textDimAA),
          ),
        ),
        Expanded(
          child: Divider(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
        ),
      ],
    );
  }
}

/// "Continue with Google" outlined button. Disabled (null callback) while an
/// auth request is in flight.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      identifier: 'auth-google-btn',
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: SvgPicture.asset(
          'assets/icons/google_logo.svg',
          width: 20,
          height: 20,
        ),
        label: Text(l10n.continueWithGoogle),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          side: BorderSide(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

/// Bottom "Don't have an account? / Already have an account?" mode-toggle
/// button. Disabled (null callback) while an auth request is in flight.
class _ModeToggleButton extends StatelessWidget {
  const _ModeToggleButton({required this.isSignUp, required this.onPressed});

  final bool isSignUp;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      identifier: isSignUp ? 'auth-toggle-login' : 'auth-toggle-signup',
      child: TextButton(
        onPressed: onPressed,
        // Phase 38.9 T2.6: interactive violet (was the default TextButton
        // primaryViolet foreground, 2.48:1 < 4.5).
        style: TextButton.styleFrom(foregroundColor: AppColors.hotViolet),
        child: Text(isSignUp ? l10n.alreadyHaveAccount : l10n.dontHaveAccount),
      ),
    );
  }
}

/// Non-blocking 3-segment password-strength bar (signup mode only).
///
/// Purely presentational — it visualizes [_LoginScreenState.passwordStrengthScore]
/// (0–3) and NEVER gates submission. Three fixed-width segments fill from the
/// left as the score rises; the active color escalates error -> warning ->
/// success.
///
/// The label below the bar names the tier word AND the single highest-priority
/// MISSING requirement, composed as `{tier} — {tip}`. The tip is prioritized
/// length -> number -> symbol, so it always reflects what the typed value is
/// actually short on (e.g. "Test12." has a digit + symbol but only 7 chars →
/// "Medium — use 8+ characters"). The strong tier (3) shows a standalone
/// celebratory string with no tip. At score 0 (empty field) the bar shows
/// three empty tracks and no label, occupying stable vertical space without
/// shouting at a not-yet-typed field.
class _PasswordStrengthBar extends StatelessWidget {
  const _PasswordStrengthBar({required this.score, required this.password});

  /// 0 (empty) … 3 (strong). See [_LoginScreenState.passwordStrengthScore].
  final int score;

  /// The live password value — used to derive the next-step tip. The score
  /// alone is insufficient (a short value with a digit+symbol and a long
  /// alpha-only value are both score 2 but need different tips).
  final String password;

  /// The single highest-priority unmet requirement for [password], prioritized
  /// length -> number -> symbol. Returns `null` only when all three are met
  /// (which corresponds to the strong tier, where no tip is shown).
  String? _nextStepTip(AppLocalizations l10n) {
    if (password.length < 8) return l10n.passwordTipLength;
    if (!password.contains(RegExp(r'\d'))) return l10n.passwordTipNumber;
    if (!password.contains(RegExp(r'[^A-Za-z0-9]'))) {
      return l10n.passwordTipSymbol;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final emptyTrack = AppColors.textDim.withValues(alpha: 0.18);

    // Active color + composed label keyed off the score. Null label at score 0
    // keeps the bar quiet before the user types. Tiers 1 & 2 compose the tier
    // word with the next-step tip; tier 3 is the standalone celebratory string.
    final (Color activeColor, String? tierWord) = switch (score) {
      3 => (AppColors.success, null),
      2 => (AppColors.warning, l10n.passwordStrengthMedium),
      1 => (AppColors.error, l10n.passwordStrengthWeak),
      _ => (emptyTrack, null),
    };
    final String? label;
    if (score == 3) {
      label = l10n.passwordStrengthStrong;
    } else if (tierWord != null) {
      final tip = _nextStepTip(l10n);
      label = tip != null ? '$tierWord — $tip' : tierWord;
    } else {
      label = null;
    }

    return Semantics(
      container: true,
      identifier: 'auth-password-strength',
      // Announce the tier (or "empty") so screen-reader users get the same
      // signal sighted users read off the colored segments.
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(3, (index) {
              final filled = index < score;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: index < 2 ? 6 : 0),
                  decoration: BoxDecoration(
                    color: filled ? activeColor : emptyTrack,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            }),
          ),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(color: activeColor),
            ),
          ],
        ],
      ),
    );
  }
}

/// Inline age-gate disclosure label: a single LGPD-compliant sentence with the
/// Terms and Privacy links embedded via [WidgetSpan]/[TextButton]. Replaces the
/// orphaned chip row PR #309 shipped.
///
/// The inline links use `MaterialTapTargetSize.shrinkWrap` with a small
/// vertical padding instead of the prior `minimumSize: Size(0, 48)`: a 48dp
/// inline height inflated the whole text line, breaking line flow and the
/// baseline against the checkbox (the on-device misplacement). The links still
/// expose a comfortable tap area via horizontal+vertical padding while wrapping
/// inline at the surrounding 14sp line height.
class _AgeGateLabel extends StatelessWidget {
  const _AgeGateLabel({
    required this.enabled,
    required this.onTapTerms,
    required this.onTapPrivacy,
  });

  final bool enabled;
  final VoidCallback onTapTerms;
  final VoidCallback onTapPrivacy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final baseStyle = AppTextStyles.body.copyWith(
      fontSize: 14,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
    );
    final linkStyle = AppTextStyles.body.copyWith(
      fontSize: 14,
      // Phase 38.9 T2.6: interactive violet (was primaryViolet, < AA) for the
      // inline Terms / Privacy links.
      color: AppColors.hotViolet,
      fontWeight: FontWeight.w600,
    );

    WidgetSpan linkSpan(String label, String identifier, VoidCallback onTap) {
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Semantics(
          container: true,
          // Cluster: `semantics-button-missing`. Without `button: true` the
          // outer Semantics node is passive on Flutter web's AOM, so
          // Playwright taps land but don't forward to the inner InkWell —
          // the inline legal links would be untappable in E2E.
          button: true,
          identifier: identifier,
          child: TextButton(
            onPressed: enabled ? onTap : null,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(label, style: linkStyle),
          ),
        ),
      );
    }

    // Sentence: "I'm 18+ and agree to the {Terms} and the {Privacy}".
    // `signupAgeConfirmationLead` carries the leading clause; the links reuse
    // the existing termsOfService / privacyPolicy labels and `andSeparator`.
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: '${l10n.signupAgeConfirmationLead} '),
          linkSpan(l10n.termsOfService, 'auth-age-link-terms', onTapTerms),
          TextSpan(text: l10n.andSeparator),
          linkSpan(l10n.privacyPolicy, 'auth-age-link-privacy', onTapPrivacy),
        ],
      ),
    );
  }
}

class _LegalFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Phase 38.9 T2.6: AA dim prose (was onSurface@0.6, 2.09:1) + interactive
    // violet links (was primary@0.85).
    final baseStyle = AppTextStyles.bodySmall.copyWith(
      color: AppColors.textDimAA,
    );
    final linkStyle = AppTextStyles.bodySmall.copyWith(
      color: AppColors.hotViolet,
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
