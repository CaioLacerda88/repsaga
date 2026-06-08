import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/base_repository.dart';

class AuthRepository extends BaseRepository {
  /// [authTimeout] / [signOutTimeout] are exposed for tests so they can drive
  /// the timeout path without having to advance fake-time by 30/5 seconds.
  /// Production callers must not override them.
  AuthRepository(
    this._auth, {
    FunctionsClient? functions,
    @visibleForTesting Duration? authTimeout,
    @visibleForTesting Duration? signOutTimeout,
    super.recoveryRecorder,
  }) : _injectedFunctions = functions,
       _authTimeout = authTimeout ?? _defaultAuthTimeout,
       _signOutTimeout = signOutTimeout ?? _defaultSignOutTimeout;

  static const Duration _defaultAuthTimeout = Duration(seconds: 30);

  /// Sign-out uses a tighter budget than the default auth timeout. Supabase's
  /// `GoTrueClient.signOut` defaults to `SignOutScope.local`, which clears
  /// local storage **before** the server call — so a server-side hang has no
  /// bearing on whether the user is locally signed out. A 30s wait followed
  /// by an `AsyncError` would be a strictly worse UX than failing fast at 5s.
  static const Duration _defaultSignOutTimeout = Duration(seconds: 5);

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

  /// Tighter timeout used by [signOut] only — see [_defaultSignOutTimeout].
  final Duration _signOutTimeout;

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
  ///
  /// [locale] — when non-null, forwarded to Supabase as `data.locale` so the
  /// new auth.users row carries `user_metadata.locale`. The hosted email
  /// templates read this via the Go conditional `{{ if eq .Data.locale "pt" }}`
  /// to render either pt-BR or English (the `{{ else }}` branch) — see
  /// `docs/auth-email-templates/README.md`.
  ///
  /// [displayName] — when non-null, forwarded as `data.display_name`. The
  /// `handle_new_user` trigger reads `raw_user_meta_data->>'display_name'`
  /// when seeding the `profiles` row, so collecting the name at signup means
  /// onboarding no longer has to ask for it (Option A — full-form signup).
  ///
  /// Each key is included only when its value is non-null, and the whole
  /// `data:` map is left null when BOTH are null — so the underlying `signUp`
  /// gets its default `data: null` and we leave `user_metadata` untouched
  /// server-side (never overwrite OAuth/admin-set metadata).
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    String? locale,
    String? displayName,
  }) {
    // Typed `Map<String, dynamic>?` lines up with `GoTrueClient.signUp(data:)`.
    // Stay null when there is nothing to write so we never send an empty map.
    final Map<String, dynamic>? signUpData =
        (locale == null && displayName == null)
        ? null
        : <String, dynamic>{
            // ignore: use_null_aware_elements
            if (locale != null) 'locale': locale,
            // ignore: use_null_aware_elements
            if (displayName != null) 'display_name': displayName,
          };
    return mapException(
      () => _auth
          .signUp(email: email, password: password, data: signUpData)
          .timeout(_authTimeout),
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
  ///
  /// No `.timeout()` here on purpose: `signInWithOAuth` resolves when the OS
  /// launches the browser (returning `true`), not when OAuth completes. The
  /// actual session arrives later via `onAuthStateChange` from the deep-link
  /// redirect, so a timeout would fire on the wrong operation — it would
  /// only ever trip if the OS itself failed to open Chrome. In-browser /
  /// post-redirect progress UX is a separate concern.
  Future<bool> signInWithGoogle() {
    return mapException(
      () => _auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.repsaga://login-callback/',
      ),
    );
  }

  /// Sign out the current user. Uses [_signOutTimeout] (shorter than the
  /// default auth timeout) — local sign-out happens regardless of the
  /// server response, so a slow server should fail fast rather than block
  /// the UI for half a minute.
  Future<void> signOut() {
    return mapException(() => _auth.signOut().timeout(_signOutTimeout));
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

  /// Merge-update the current user's `user_metadata` map server-side.
  ///
  /// PR A2 — used by `ProfileNotifier._hydrateLocaleMetadataIfMissing` to
  /// close the two `user_metadata.locale = NULL` populations documented
  /// in `docs/auth-email-templates/README.md` → "Known edge cases":
  /// legacy users created before PR #300 and Google OAuth signups (the
  /// OAuth flow cannot set `user_metadata` at authorization time).
  ///
  /// `data` is forwarded verbatim as `UserAttributes(data: data)` —
  /// Supabase merges the keys into `auth.users.raw_user_meta_data`:
  /// keys present in `data` overwrite their counterparts in
  /// `raw_user_meta_data`; keys absent from `data` are untouched. Pass
  /// the smallest map possible (e.g. `{'locale': 'pt'}`) so we never
  /// accidentally clobber metadata owned by another subsystem (OAuth
  /// provider data, admin-set keys, etc.).
  Future<void> updateUserMetadata(Map<String, Object?> data) {
    return mapException(
      () => _auth.updateUser(UserAttributes(data: data)).timeout(_authTimeout),
    );
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
