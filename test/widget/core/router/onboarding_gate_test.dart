/// PR 1 — router redirect derives onboarding-needed from `profile.onboardedAt`.
///
/// Strategy: pump the production `routerProvider` end-to-end (so the
/// `_RouterRefreshListenable` extension that wires `profileProvider` is
/// exercised), but read the destination via the router's matched location
/// rather than mounting the destination screen — the real screens depend on
/// many providers we don't want to stub in this test. The redirect is what
/// PR 1 changes; the screens are tested separately.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/connectivity/connectivity_provider.dart';
import 'package:repsaga/core/local_storage/cache_refresh_provider.dart';
import 'package:repsaga/core/offline/sync_service.dart';
import 'package:repsaga/core/router/app_router.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/personal_records/providers/pr_cache_bootstrap_provider.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:repsaga/features/profile/providers/profile_providers.dart';
import 'package:repsaga/features/rpg/providers/earned_titles_backfill_provider.dart';
import 'package:repsaga/features/rpg/providers/rpg_progress_provider.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/providers/notifiers/active_workout_notifier.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/l10n/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class _ValidSessionAuth extends Fake implements supabase.AuthState {
  _ValidSessionAuth(this._session);
  final supabase.Session _session;

  @override
  supabase.Session get session => _session;
}

class _FakeSession extends Fake implements supabase.Session {}

class _StubProfileNotifier extends ProfileNotifier {
  _StubProfileNotifier(this._value);
  final Profile? _value;

  @override
  Future<Profile?> build() async => _value;
}

class _LoadingForeverProfileNotifier extends ProfileNotifier {
  @override
  Future<Profile?> build() {
    return Completer<Profile?>().future;
  }
}

class _NullActiveWorkoutNotifier extends AsyncNotifier<ActiveWorkoutState?>
    implements ActiveWorkoutNotifier {
  @override
  Future<ActiveWorkoutState?> build() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopSyncService extends SyncService {
  @override
  SyncState build() => const SyncState();
}

class _EmptyRpgProgress extends AsyncNotifier<RpgProgressSnapshot>
    implements RpgProgressNotifier {
  @override
  Future<RpgProgressSnapshot> build() async => RpgProgressSnapshot.empty;

  @override
  Future<RpgProgressSnapshot> refreshAfterSave() async =>
      RpgProgressSnapshot.empty;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Override> _baseOverrides({
  required StreamController<supabase.AuthState> authController,
  required ProfileNotifier Function() profileNotifierBuilder,
}) {
  return [
    authStateProvider.overrideWith((ref) => authController.stream),
    profileProvider.overrideWith(profileNotifierBuilder),
    activeWorkoutProvider.overrideWith(_NullActiveWorkoutNotifier.new),
    isOnlineProvider.overrideWithValue(true),
    cacheRefreshProvider.overrideWith((_) async {}),
    syncServiceProvider.overrideWith(_NoopSyncService.new),
    rpgProgressProvider.overrideWith(_EmptyRpgProgress.new),
    prCacheBootstrapProvider.overrideWith((ref) async {}),
    earnedTitlesBackfillProvider.overrideWith((ref) async {}),
  ];
}

/// Resolves the destination the router lands on after the supplied auth
/// event arrives. We don't render the real destination screens (they have
/// their own deep provider trees); the router's `matchedLocation` is the
/// contract surface PR 1 changes.
Future<String> _destination(
  WidgetTester tester, {
  required ProviderContainer container,
  required StreamController<supabase.AuthState> authController,
  required supabase.AuthState authEvent,
}) async {
  // Pre-subscribe to auth + profile streams so they are attached
  // BEFORE the event is added. The production GoRouter widget tree
  // does this implicitly via the `_RouterRefreshListenable`'s `ref.listen`
  // calls, but at the point we read `routerProvider` below those listens
  // have already wired up; this is just defensive pinning.
  container.listen(authStateProvider, (_, _) {});
  container.listen(profileProvider, (_, _) {});
  final router = container.read(routerProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        routerConfig: router,
      ),
    ),
  );
  // `runAsync` lets `dart:async` microtasks (StreamController delivery)
  // run inside the test environment. `tester.pump()` alone advances the
  // synthetic clock but does NOT drain microtasks queued by
  // `add` on a Dart Stream, so the StreamProvider never receives the
  // event without this. 100ms is generous; in practice it's instant.
  await tester.runAsync(() async {
    authController.add(authEvent);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pump();
  final result = router.routerDelegate.currentConfiguration.uri.toString();
  // Drain any framework-detected exceptions / pending timers from the
  // destination screen's own provider tree (SagaIntroGate touches
  // `rpgRepositoryProvider` which requires a Supabase client we don't
  // stub here). The redirect contract is the test surface; the screen
  // is mounted but not asserted on.
  tester.takeException();
  return result;
}

void main() {
  group('Router onboarding gate (PR 1)', () {
    testWidgets(
      'session present + profile.onboardedAt null lands on /onboarding',
      (tester) async {
        final authController = StreamController<supabase.AuthState>();
        final container = ProviderContainer(
          overrides: _baseOverrides(
            authController: authController,
            profileNotifierBuilder: () => _StubProfileNotifier(
              const Profile(id: 'u1', displayName: 'Caio'),
            ),
          ),
        );
        addTearDown(container.dispose);

        final dest = await _destination(
          tester,
          container: container,
          authController: authController,
          authEvent: _ValidSessionAuth(_FakeSession()),
        );

        expect(dest, '/onboarding');
      },
    );

    testWidgets(
      'session present + profile.onboardedAt non-null lands on /home',
      (tester) async {
        final authController = StreamController<supabase.AuthState>();
        final container = ProviderContainer(
          overrides: _baseOverrides(
            authController: authController,
            profileNotifierBuilder: () => _StubProfileNotifier(
              Profile(
                id: 'u1',
                displayName: 'Caio',
                onboardedAt: DateTime(2026, 1, 1),
              ),
            ),
          ),
        );
        addTearDown(container.dispose);

        final dest = await _destination(
          tester,
          container: container,
          authController: authController,
          authEvent: _ValidSessionAuth(_FakeSession()),
        );

        expect(dest, '/home');
      },
    );

    testWidgets('session present + profile.isLoading parks on /splash', (
      tester,
    ) async {
      final authController = StreamController<supabase.AuthState>();
      final container = ProviderContainer(
        overrides: _baseOverrides(
          authController: authController,
          profileNotifierBuilder: _LoadingForeverProfileNotifier.new,
        ),
      );
      addTearDown(container.dispose);

      final dest = await _destination(
        tester,
        container: container,
        authController: authController,
        authEvent: _ValidSessionAuth(_FakeSession()),
      );

      expect(dest, '/splash');
    });
  });
}
