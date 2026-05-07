import '../../../l10n/app_localizations.dart';

/// Maps auth error codes/messages to user-friendly text.
class AuthErrorMessages {
  const AuthErrorMessages._();

  static String fromError(Object error, AppLocalizations l10n) {
    final message = error.toString().toLowerCase();

    // Supabase auth error patterns
    if (message.contains('invalid login credentials') ||
        message.contains('invalid_credentials')) {
      return l10n.authErrorInvalidCredentials;
    }
    if (message.contains('email not confirmed')) {
      return l10n.authErrorEmailNotConfirmed;
    }
    if (message.contains('user already registered') ||
        message.contains('already been registered')) {
      return l10n.authErrorAlreadyRegistered;
    }
    if (message.contains('email rate limit') ||
        message.contains('rate limit')) {
      return l10n.authErrorRateLimit;
    }
    if (message.contains('weak password') ||
        message.contains('password should be')) {
      return l10n.authErrorWeakPassword;
    }
    // Check `timeout` before `network`/`connection`: a TimeoutException is
    // mapped to `NetworkException('Request timeout.')` (see ErrorMapper),
    // and `error.toString()` includes the `NetworkException` runtimeType
    // prefix — which itself contains the substring `network`. Without this
    // ordering, every timeout would surface as the generic "no connection"
    // copy instead of the more accurate "request timed out" one.
    if (message.contains('timeout')) {
      return l10n.authErrorTimeout;
    }
    if (message.contains('network') ||
        message.contains('socket') ||
        message.contains('connection')) {
      return l10n.authErrorNetwork;
    }
    if (message.contains('otp') || message.contains('token')) {
      return l10n.authErrorTokenExpired;
    }

    // Fallback
    return l10n.authErrorGeneric;
  }
}
