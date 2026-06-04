import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/device/platform_info.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/local_storage/hive_service.dart';
import '../../../../core/observability/sentry_report.dart';
import '../../data/auth_repository.dart';
import '../auth_providers.dart';
import '../signup_state_provider.dart';

/// Manages auth actions (sign in, sign up, sign out).
class AuthNotifier extends AsyncNotifier<Session?> {
  late AuthRepository _repo;
  late HiveService _hive;

  @override
  FutureOr<Session?> build() {
    _repo = ref.watch(authRepositoryProvider);
    _hive = ref.watch(hiveServiceProvider);
    return _repo.currentSession;
  }

  Future<void> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      // Forward the app locale to Supabase user_metadata so the email
      // templates can route on `.Data.locale` — Brazilian users get pt-BR
      // confirmation emails, English users get English. Google OAuth users
      // currently default to English because the OAuth flow writes no
      // user_metadata; see `docs/auth-email-templates/README.md` →
      // "Known edge case".
      final locale = ref.read(localeProvider).languageCode;
      final response = await _repo.signUpWithEmail(
        email: email,
        password: password,
        locale: locale,
      );
      // If no session returned, email confirmation is required.
      if (response.session == null) {
        ref.read(signupPendingEmailProvider.notifier).state = email;
      }
      SentryReport.addBreadcrumb(category: 'auth', message: 'sign_up_email');
      return response.session;
    });
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final response = await _repo.signInWithEmail(
        email: email,
        password: password,
      );
      SentryReport.addBreadcrumb(category: 'auth', message: 'sign_in_email');
      return response.session;
    });
  }

  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.signInWithGoogle();
      SentryReport.addBreadcrumb(category: 'auth', message: 'sign_in_google');
      // OAuth redirects externally; session comes via onAuthStateChange.
      return _repo.currentSession;
    });
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.signOut();
      SentryReport.addBreadcrumb(category: 'auth', message: 'sign_out');
      return null;
    });
    // Best-effort cache clear — a Hive I/O failure must never prevent
    // sign-out from completing. Mirrors the deleteAccount() pattern.
    try {
      await _hive.clearAll();
    } catch (_) {
      // Intentionally swallowed.
    }
  }

  /// Resend the confirmation email for a pending signup.
  Future<void> resendConfirmationEmail(String email) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.resendConfirmationEmail(email);
      return _repo.currentSession;
    });
  }

  /// Send a password reset email.
  Future<void> resetPassword(String email) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.resetPassword(email);
      return _repo.currentSession;
    });
  }

  /// Permanently delete the current user's account.
  ///
  /// Invokes the `delete-user` Edge Function via [AuthRepository]. On
  /// success the state transitions to [AsyncData] and a best-effort local
  /// sign-out is attempted to trigger the auth state listener redirect to
  /// the login screen. Sign-out errors after a successful delete are
  /// swallowed intentionally: the server has already invalidated the user,
  /// so surfacing "Failed to delete account" here would be catastrophically
  /// misleading (the account IS gone and the user cannot log in again).
  ///
  /// On delete failure, the state transitions to [AsyncError] with the
  /// wrapped [AppException] so the UI can surface a safe error message and
  /// the caller returns early before the sign-out attempt.
  ///
  /// The `account_deleted` audit event is written from inside the Edge
  /// Function (service role, pre-delete, into the no-FK
  /// `account_deletion_events` table). Doing it client-side would be
  /// pointless — the CASCADE on `analytics_events.user_id` would wipe the
  /// row the moment `auth.admin.deleteUser()` ran.
  Future<void> deleteAccount() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _repo.deleteAccount(
        platform: currentPlatform(),
        appVersion: currentAppVersion(),
      );
      return null;
    });
    if (state.hasError) return;

    SentryReport.addBreadcrumb(category: 'auth', message: 'account_deleted');

    // Clear all offline caches so the next sign-in starts with a clean slate.
    await _hive.clearAll();

    // Account deleted successfully — best-effort local sign-out. Any error
    // here is ignored because the server-side user is already gone and the
    // auth state listener will handle the redirect regardless.
    try {
      await _repo.signOut();
    } catch (_) {
      // Intentionally swallowed: see doc comment above.
    }
    state = const AsyncData(null);
  }
}

final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, Session?>(
  AuthNotifier.new,
);
