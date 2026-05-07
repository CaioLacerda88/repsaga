import '../../../core/exceptions/app_exception.dart';
import '../../../l10n/app_localizations.dart';

/// Maps auth error codes/messages to user-friendly text.
///
/// Type-based dispatch first (cheap, robust against runtimeType-prefixed
/// `toString()` collisions), then a substring fallback that ONLY inspects
/// the [AppException.message] field — never `toString()`. The latter is
/// `"$runtimeType: $message"` and would otherwise let any exception whose
/// runtimeType happens to contain `network`, `timeout`, `otp`, `token`, etc.
/// silently mis-route through the substring matchers.
class AuthErrorMessages {
  const AuthErrorMessages._();

  static String fromError(Object error, AppLocalizations l10n) {
    // Type-based dispatch — preferred path. Future [AppException] subtypes
    // get their own branch here; no substring fragility.
    if (error is TimeoutException) {
      return l10n.authErrorTimeout;
    }
    if (error is NetworkException) {
      return l10n.authErrorNetwork;
    }

    // Substring fallback only for exceptions that carry a free-form message
    // we control — typically [AppException.message] (Supabase-mapped auth
    // errors) or a raw [Exception('...')] thrown by tests / legacy callers.
    // We deliberately read `.message` (or `toString()` for non-AppException)
    // to avoid the runtimeType prefix poisoning the match.
    final raw = error is AppException ? error.message : error.toString();
    final msg = raw.toLowerCase();

    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid_credentials')) {
      return l10n.authErrorInvalidCredentials;
    }
    if (msg.contains('email not confirmed')) {
      return l10n.authErrorEmailNotConfirmed;
    }
    if (msg.contains('user already registered') ||
        msg.contains('already been registered')) {
      return l10n.authErrorAlreadyRegistered;
    }
    if (msg.contains('email rate limit') || msg.contains('rate limit')) {
      return l10n.authErrorRateLimit;
    }
    if (msg.contains('weak password') || msg.contains('password should be')) {
      return l10n.authErrorWeakPassword;
    }
    if (msg.contains('otp') || msg.contains('token')) {
      return l10n.authErrorTokenExpired;
    }
    // Defensive: an upstream layer may surface a network/timeout failure as
    // a plain [Exception] with these keywords in the message. Type-based
    // dispatch above already handles our [TimeoutException] /
    // [NetworkException] domain types — this branch only catches the rarer
    // raw-exception case.
    if (msg.contains('timeout')) {
      return l10n.authErrorTimeout;
    }
    if (msg.contains('network') ||
        msg.contains('socket') ||
        msg.contains('connection')) {
      return l10n.authErrorNetwork;
    }

    // Fallback
    return l10n.authErrorGeneric;
  }
}
