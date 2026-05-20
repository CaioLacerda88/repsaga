import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../providers/notifiers/auth_notifier.dart';
import '../providers/signup_state_provider.dart';
import '../utils/auth_error_messages.dart';

class EmailConfirmationScreen extends ConsumerStatefulWidget {
  const EmailConfirmationScreen({super.key});

  @override
  ConsumerState<EmailConfirmationScreen> createState() =>
      _EmailConfirmationScreenState();
}

class _EmailConfirmationScreenState
    extends ConsumerState<EmailConfirmationScreen> {
  bool _resendSuccess = false;

  Future<void> _resendEmail() async {
    final email = ref.read(signupPendingEmailProvider);
    if (email == null) return;

    setState(() => _resendSuccess = false);
    await ref
        .read(authNotifierProvider.notifier)
        .resendConfirmationEmail(email);

    if (mounted && !ref.read(authNotifierProvider).hasError) {
      setState(() => _resendSuccess = true);
    }
  }

  void _backToLogin() {
    ref.read(signupPendingEmailProvider.notifier).state = null;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final email = ref.watch(signupPendingEmailProvider) ?? '';
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.isLoading;

    // Show error feedback.
    ref.listen(authNotifierProvider, (prev, next) {
      if (next.hasError && !next.isLoading) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AuthErrorMessages.fromError(next.error!, l10n)),
            backgroundColor: theme.colorScheme.error,
          ),
        );
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.mark_email_read_outlined,
                    size: 40,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  l10n.checkYourInbox,
                  style: AppTextStyles.headline.copyWith(
                    fontSize: 28,
                    color: theme.colorScheme.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  email.isNotEmpty
                      ? l10n.confirmationSentTo
                      : l10n.confirmationSent,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    email,
                    style: AppTextStyles.title.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  l10n.tapLinkToVerify,
                  style: AppTextStyles.body.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (_resendSuccess)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      l10n.emailResent,
                      style: AppTextStyles.body.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: GradientButton(
                    label: l10n.backToLogin,
                    onPressed: isLoading ? null : _backToLogin,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: isLoading ? null : _resendEmail,
                  child: isLoading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : Text(l10n.didntReceiveResend),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
