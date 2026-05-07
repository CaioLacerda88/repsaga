import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/base_repository.dart';

class AuthRepository extends BaseRepository {
  /// [authTimeout] is exposed for tests so they can drive the timeout path
  /// without having to advance fake-time by 30 seconds. Production callers
  /// must not override it.
  AuthRepository(
    this._auth, {
    FunctionsClient? functions,
    @visibleForTesting Duration? authTimeout,
  }) : _injectedFunctions = functions,
       _authTimeout = authTimeout ?? _defaultAuthTimeout;

  static const Duration _defaultAuthTimeout = Duration(seconds: 30);

  final GoTrueClient _auth;
  final FunctionsClient? _injectedFunctions;

  /// Per-call timeout applied to every network operation on this repository.
  /// The Supabase Dart SDK does not impose a default request timeout, so a
  /// silent network black hole (captive portal dropping packets, dead Wi-Fi
  /// handoff) would otherwise leave the auth notifier in `AsyncLoading()`
  /// indefinitely. A `TimeoutException` here propagates through
  /// `BaseRepository.mapException` -> `ErrorMapper.mapException` and lands
  /// in `AsyncError`, which the UI surfaces via `AuthErrorMessages.fromError`.
  final Duration _authTimeout;

  /// Functions client used for invoking Edge Functions. Tests can inject a
  /// mock via the constructor; in production we fall back to the global
  /// Supabase client's functions instance.
  FunctionsClient get _functions =>
      _injectedFunctions ?? Supabase.instance.client.functions;

  /// Stream of auth state changes.
  Stream<AuthState> onAuthStateChange() => _auth.onAuthStateChange;

  /// Current session, if any.
  Session? get currentSession => _auth.currentSession;

  /// Current user, if any.
  User? get currentUser => _auth.currentUser;

  /// Sign up with email and password.
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
  }) {
    return mapException(
      () =>
          _auth.signUp(email: email, password: password).timeout(_authTimeout),
    );
  }

  /// Sign in with email and password.
  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) {
    return mapException(
      () => _auth
          .signInWithPassword(email: email, password: password)
          .timeout(_authTimeout),
    );
  }

  /// Sign in with Google OAuth.
  Future<bool> signInWithGoogle() {
    return mapException(
      () => _auth
          .signInWithOAuth(
            OAuthProvider.google,
            redirectTo: 'io.supabase.repsaga://login-callback/',
          )
          .timeout(_authTimeout),
    );
  }

  /// Sign out the current user.
  Future<void> signOut() {
    return mapException(() => _auth.signOut().timeout(_authTimeout));
  }

  /// Resend the confirmation email to the given address.
  Future<void> resendConfirmationEmail(String email) {
    return mapException(
      () => _auth
          .resend(type: OtpType.signup, email: email)
          .timeout(_authTimeout),
    );
  }

  /// Send a password reset email.
  Future<void> resetPassword(String email) {
    return mapException(
      () => _auth.resetPasswordForEmail(email).timeout(_authTimeout),
    );
  }

  /// Refresh the current session token.
  Future<AuthResponse> refreshSession() {
    return mapException(() => _auth.refreshSession().timeout(_authTimeout));
  }

  /// Delete the current user's account permanently.
  ///
  /// Calls the `delete-user` Edge Function, which verifies the caller's JWT
  /// and then uses the service-role key to call `auth.admin.deleteUser()`.
  /// All user-owned rows in public tables cascade via FK constraints, so a
  /// single successful call removes the account and every piece of data
  /// tied to it. Before the delete, the Edge Function writes an anonymous
  /// row to `account_deletion_events` for churn analytics — [platform] and
  /// [appVersion] are forwarded so the audit row carries that context.
  /// Callers should follow up with [signOut] so the auth state listener
  /// can redirect to the login screen.
  Future<void> deleteAccount({String? platform, String? appVersion}) {
    return mapException(() async {
      // Use `if (x != null)` collection-if rather than the newer null-aware
      // map value syntax (`'platform': ?platform`): build_runner's bundled
      // analyzer on CI can't parse the latter, so the freezed/json_serializable
      // generators fail at the `auth_repository.dart` parse step.
      final response = await _functions
          .invoke(
            'delete-user',
            body: <String, dynamic>{
              // ignore: use_null_aware_elements
              if (platform != null) 'platform': platform,
              // ignore: use_null_aware_elements
              if (appVersion != null) 'app_version': appVersion,
            },
          )
          .timeout(_authTimeout);
      if (response.status >= 400) {
        throw Exception('Delete account failed (status ${response.status})');
      }
    });
  }
}
