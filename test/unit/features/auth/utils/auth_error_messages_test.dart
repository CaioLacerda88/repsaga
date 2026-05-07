import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/exceptions/app_exception.dart';
import 'package:repsaga/features/auth/utils/auth_error_messages.dart';
import 'package:repsaga/l10n/app_localizations.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() {
    l10n = lookupAppLocalizations(const Locale('en'));
  });

  group('AuthErrorMessages.fromError', () {
    test('maps invalid login credentials', () {
      final message = AuthErrorMessages.fromError(
        Exception('Invalid login credentials'),
        l10n,
      );
      expect(message, l10n.authErrorInvalidCredentials);
    });

    test('maps invalid_credentials code', () {
      final message = AuthErrorMessages.fromError(
        Exception('invalid_credentials'),
        l10n,
      );
      expect(message, l10n.authErrorInvalidCredentials);
    });

    test('maps email not confirmed', () {
      final message = AuthErrorMessages.fromError(
        Exception('Email not confirmed'),
        l10n,
      );
      expect(message, l10n.authErrorEmailNotConfirmed);
    });

    test('maps user already registered', () {
      final message = AuthErrorMessages.fromError(
        Exception('User already registered'),
        l10n,
      );
      expect(message, l10n.authErrorAlreadyRegistered);
    });

    test('maps rate limit error', () {
      final message = AuthErrorMessages.fromError(
        Exception('email rate limit exceeded'),
        l10n,
      );
      expect(message, l10n.authErrorRateLimit);
    });

    test('maps weak password', () {
      final message = AuthErrorMessages.fromError(
        Exception('Password should be at least 6 characters'),
        l10n,
      );
      expect(message, l10n.authErrorWeakPassword);
    });

    test('maps network error', () {
      final message = AuthErrorMessages.fromError(
        Exception('SocketException: Connection refused'),
        l10n,
      );
      expect(message, l10n.authErrorNetwork);
    });

    test('maps timeout error', () {
      final message = AuthErrorMessages.fromError(
        Exception('Request timeout'),
        l10n,
      );
      expect(message, l10n.authErrorTimeout);
    });

    test('maps expired token/otp', () {
      final message = AuthErrorMessages.fromError(
        Exception('otp has expired'),
        l10n,
      );
      expect(message, l10n.authErrorTokenExpired);
    });

    test('returns fallback for unknown errors', () {
      final message = AuthErrorMessages.fromError(
        Exception('some random error xyz'),
        l10n,
      );
      expect(message, l10n.authErrorGeneric);
    });

    // ---------------------------------------------------------------------
    // Type-based dispatch — guards the Critical fix from PR #173 review.
    //
    // Pre-fix, `error.toString()` was lowercased and substring-matched. Since
    // `AppException.toString()` is `"$runtimeType: $message"`, every
    // `NetworkException` produced a string starting with `"networkexception:"`
    // — short-circuiting any subsequent type-specific branch. Post-fix,
    // dispatch is type-first, so a `NetworkException` whose message happens
    // to contain `timeout` (or vice-versa) routes by type, not substring.
    // ---------------------------------------------------------------------
    test('TimeoutException dispatches to authErrorTimeout (type-based)', () {
      final message = AuthErrorMessages.fromError(
        const TimeoutException(),
        l10n,
      );
      expect(message, l10n.authErrorTimeout);
    });

    test('NetworkException dispatches to authErrorNetwork (type-based)', () {
      final message = AuthErrorMessages.fromError(
        const NetworkException('No connection'),
        l10n,
      );
      expect(message, l10n.authErrorNetwork);
    });

    test('NetworkException whose message contains "timeout" still routes to '
        'authErrorNetwork — type wins over substring', () {
      // Defensive regression test. Even if a future code path constructs
      // `NetworkException('Request timeout.')`, the user must see the
      // network copy because the type IS NetworkException.
      final message = AuthErrorMessages.fromError(
        const NetworkException('Request timeout.'),
        l10n,
      );
      expect(message, l10n.authErrorNetwork);
    });

    test(
      'substring fallback inspects AppException.message only — not toString()',
      () {
        // Regression guard for PR #173 Critical: pre-fix, `error.toString()`
        // (`"$runtimeType: $message"`) was lowercased and matched. So an
        // `AuthException('Invalid login credentials', code: ...)` produced
        // the string `"authexception: invalid login credentials"` and would
        // happen to match — but a raw `AppException` whose runtimeType
        // contained any keyword (e.g. a future `OtpException` subclass)
        // would silently mis-route. Post-fix, only `error.message` is
        // scanned, so the runtimeType prefix can't poison the match.
        final message = AuthErrorMessages.fromError(
          const AuthException('Invalid login credentials', code: '400'),
          l10n,
        );
        expect(message, l10n.authErrorInvalidCredentials);
      },
    );
  });
}
