import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/connectivity/recovery_recorder_provider.dart';
import '../data/auth_repository.dart';

/// Provides the [AuthRepository] singleton.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    Supabase.instance.client.auth,
    recoveryRecorder: ref.watch(recoveryRecorderProvider),
  );
});

/// Synchronous read of the signed-in user's id, so UI/providers don't have to
/// import `supabase_flutter` just to look up `auth.currentUser?.id`.
///
/// Not reactive: consumers get the value at read time. Auth transitions
/// (sign-in/sign-out) are handled by the router via [authStateProvider], so
/// there's no need to `watch` this to stay in sync.
final currentUserIdProvider = Provider<String?>((ref) {
  return Supabase.instance.client.auth.currentUser?.id;
});

/// Synchronous read of the signed-in user's email — companion to
/// [currentUserIdProvider]. Same contract: read-time value, not reactive
/// (the router-level auth stream handles sign-in/sign-out transitions).
///
/// Used by surfaces that need a name fallback when [Profile.displayName] is
/// unset (e.g. [HomeGreeting] derives a name from the email prefix). Exposed
/// as a Riverpod provider so widgets don't have to import `supabase_flutter`
/// just to fall back to `auth.currentUser?.email`.
final currentUserEmailProvider = Provider<String?>((ref) {
  return Supabase.instance.client.auth.currentUser?.email;
});

/// Exposes the current auth state as a stream.
/// Used by the router to decide redirects.
///
/// Emits the initial state synchronously from [GoTrueClient.currentSession]
/// so the app leaves the splash screen immediately without waiting for the
/// Supabase Realtime WebSocket. The stream subscription handles subsequent
/// auth state changes (login, logout, token refresh).
///
/// A 5-second fallback timer is kept as a safety net in case the synchronous
/// check races with SDK initialisation (should not happen since
/// `Supabase.initialize()` is awaited in `main()`).
final authStateProvider = StreamProvider<AuthState>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  final controller = StreamController<AuthState>();

  // Emit the initial state synchronously from the session cache.
  // This does NOT depend on Realtime/WebSocket — it reads from local storage
  // (SharedPreferences on mobile, IndexedDB on web). After
  // `Supabase.initialize()` completes, currentSession is accurate.
  final currentSession = repo.currentSession;
  final initialEvent = currentSession != null
      ? AuthState(AuthChangeEvent.initialSession, currentSession)
      : const AuthState(AuthChangeEvent.signedOut, null);
  controller.add(initialEvent);

  var hasEmittedFromStream = false;
  final fallbackTimer = Timer(const Duration(seconds: 5), () {
    if (!hasEmittedFromStream && !controller.isClosed) {
      controller.add(const AuthState(AuthChangeEvent.signedOut, null));
    }
  });

  final subscription = repo.onAuthStateChange().listen(
    (event) {
      hasEmittedFromStream = true;
      fallbackTimer.cancel();
      if (!controller.isClosed) controller.add(event);
    },
    onError: (Object e, StackTrace s) {
      // If the Realtime stream errors (e.g. WebSocket connection refused),
      // cancel the fallback timer — we already emitted the initial state
      // synchronously above, so the app is not stuck.
      fallbackTimer.cancel();
      if (!controller.isClosed) controller.addError(e, s);
    },
    onDone: () {
      fallbackTimer.cancel();
      if (!controller.isClosed) controller.close();
    },
  );

  ref.onDispose(() {
    fallbackTimer.cancel();
    subscription.cancel();
    controller.close();
  });

  return controller.stream;
});
