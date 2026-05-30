import 'dart:async';

import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/exceptions/app_exception.dart' as app;
import 'package:repsaga/core/l10n/locale_provider.dart';
import 'package:repsaga/features/auth/data/auth_repository.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/providers/workout_history_providers.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../fixtures/test_factories.dart';

/// Locale-provider stub that returns a fixed `en` Locale without touching
/// the Hive backing box. The real provider reads `Hive.box(userPrefs)` in
/// its build() so unit tests that exercise `WorkoutHistoryNotifier.build()`
/// — which `ref.watch(localeProvider)` — would otherwise need full Hive
/// init. The notifier consumes only `.languageCode`, so a constant Locale
/// is contract-compatible.
class _LocaleStub extends Notifier<Locale> implements LocaleNotifier {
  @override
  Locale build() => const Locale('en');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockWorkoutRepository extends Mock implements WorkoutRepository {}

class _MockAuthRepository extends Mock implements AuthRepository {}

User _fakeUser({String id = 'user-A'}) {
  return User(
    id: id,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
    isAnonymous: false,
  );
}

Session _fakeSession({String userId = 'user-A'}) {
  return Session(
    accessToken: 'fake-token-$userId',
    tokenType: 'bearer',
    user: _fakeUser(id: userId),
  );
}

AuthState _signedInAs(String userId) {
  return AuthState(AuthChangeEvent.signedIn, _fakeSession(userId: userId));
}

/// BUG-040 — keepAlive providers must invalidate when the signed-in user
/// changes, otherwise user A's cached data leaks into user B's session
/// after sign-out → sign-in.
///
/// We pin the contract at the provider boundary (no Hive, no Supabase
/// client) by overriding `authStateProvider` with a synthetic stream and
/// observing how many times `getFinishedWorkoutCount` is called as the
/// auth state transitions.
void main() {
  group('BUG-040: workoutCountProvider auth invalidation', () {
    late StreamController<AuthState> authController;
    late _MockWorkoutRepository mockRepo;
    late _MockAuthRepository mockAuth;
    late ProviderContainer container;
    // Drives what `repo.getFinishedWorkoutCount(userId)` returns per call.
    late Map<String, int> countsByUser;

    setUp(() {
      authController = StreamController<AuthState>.broadcast();
      mockRepo = _MockWorkoutRepository();
      mockAuth = _MockAuthRepository();
      countsByUser = {'user-A': 7, 'user-B': 2};

      // currentUser tracks whichever user we last "signed in" via the
      // synthetic stream. Tests below mutate this in lock-step with the
      // auth event push.
      User? currentUser = _fakeUser(id: 'user-A');
      when(() => mockAuth.currentUser).thenAnswer((_) => currentUser);

      when(() => mockRepo.getFinishedWorkoutCount(any())).thenAnswer((
        invocation,
      ) async {
        final userId = invocation.positionalArguments.first as String;
        return countsByUser[userId] ?? 0;
      });

      container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockAuth),
          workoutRepositoryProvider.overrideWithValue(mockRepo),
          authStateProvider.overrideWith((ref) => authController.stream),
        ],
      );

      addTearDown(() async {
        container.dispose();
        await authController.close();
      });

      // Helper closure for tests to "sign in" as a different user.
      addTearDown(() {
        // Re-seed for the next test even though setUp will run again — keeps
        // the mocked repository stable across container disposal.
      });
      // Expose the swap closure via the test scope.
      _swapUser = (String userId) {
        currentUser = _fakeUser(id: userId);
        authController.add(_signedInAs(userId));
      };
    });

    test('invalidates and re-fetches when user-id changes', () async {
      // Subscribing through the container starts the FutureProvider body
      // (which registers the auth listener). It's keepAlive, so the
      // subscription drives lifetime.
      final sub = container.listen(workoutCountProvider, (_, _) {});
      addTearDown(sub.close);

      // Seed the auth stream with the initial signed-in event. Because the
      // listener inside the provider body sees prev==null vs next==user-A
      // as a transition, this triggers an invalidate-and-refetch. Drain
      // microtasks so the rebuild settles before assertions.
      authController.add(_signedInAs('user-A'));
      await container.read(workoutCountProvider.future);
      // After the rebuild settles, the value must reflect user-A.
      expect(container.read(workoutCountProvider).value, 7);

      // Sign in as user-B in one step (skip the intermediate signed-out
      // emission so we don't churn the body through a null-user fetch
      // before the user-B fetch). The single signed-in→signed-in
      // transition still flips the user-id slice, which is the only thing
      // the listener compares.
      _swapUser('user-B');

      // Drain the microtask queue so the stream emission propagates to the
      // listener and invalidateSelf marks the provider dirty BEFORE we
      // read .future (otherwise .future returns the cached completed
      // future from the previous user-A fetch).
      await Future<void>.delayed(Duration.zero);

      // Wait for the invalidate → rebuild → fetch chain to settle.
      // Reading `.future` forces the test to await the fresh in-flight
      // future the rebuild registered.
      await container.read(workoutCountProvider.future);
      expect(container.read(workoutCountProvider).value, 2);

      // Repository was queried at least once per distinct user-id. The
      // initial fetch hits user-A; the post-swap fetch hits user-B.
      verify(
        () => mockRepo.getFinishedWorkoutCount('user-A'),
      ).called(greaterThanOrEqualTo(1));
      verify(
        () => mockRepo.getFinishedWorkoutCount('user-B'),
      ).called(greaterThanOrEqualTo(1));
    });

    test(
      'does NOT re-fetch on token-refresh emissions (same user-id)',
      () async {
        final sub = container.listen(workoutCountProvider, (_, _) {});
        addTearDown(sub.close);

        // Initial fetch + the synthetic null→user-A transition the first
        // emission triggers (the listener short-circuit only fires when
        // prevUserId == nextUserId, which is not the case for a null prior).
        authController.add(_signedInAs('user-A'));
        await container.read(workoutCountProvider.future);
        expect(container.read(workoutCountProvider).value, 7);

        // Drain the verify counter so the assertion below only sees the
        // post-token-refresh activity.
        verify(
          () => mockRepo.getFinishedWorkoutCount('user-A'),
        ).called(greaterThanOrEqualTo(1));

        // Push two more emissions with the same user-id (simulating
        // tokenRefreshed events). The user-id slice is unchanged → the
        // listener's short-circuit must prevent any extra repo call.
        authController.add(
          AuthState(
            AuthChangeEvent.tokenRefreshed,
            _fakeSession(userId: 'user-A'),
          ),
        );
        authController.add(_signedInAs('user-A'));
        await Future<void>.delayed(Duration.zero);

        // No additional repo invocations after the token-refresh emissions.
        verifyNever(() => mockRepo.getFinishedWorkoutCount(any()));
      },
    );
  });

  // --------------------------------------------------------------------------
  // PR #285 device-verification — `loadMore` must swallow transient errors
  // instead of rethrowing into the fire-and-forget caller `_onScroll`. The
  // caller doesn't `await` the future, so a rethrow becomes an unhandled
  // async exception logged to Flutter's `dart_vm_initializer` — spamming
  // Sentry without an actionable user-facing signal. The contract:
  //   * loadMore() returns normally on transient repo failure (does NOT throw)
  //   * state restored to `isLoadingMore: false` with the prior workouts intact
  //   * `refresh()` is the user's recovery path (verified by the existing
  //     workout history widget tests + e2e)
  // --------------------------------------------------------------------------
  group('PR #285: loadMore transient-error handling', () {
    late _MockWorkoutRepository mockRepo;
    late _MockAuthRepository mockAuth;
    late ProviderContainer container;

    setUp(() {
      mockRepo = _MockWorkoutRepository();
      mockAuth = _MockAuthRepository();
      when(() => mockAuth.currentUser).thenReturn(_fakeUser(id: 'user-A'));

      container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockAuth),
          workoutRepositoryProvider.overrideWithValue(mockRepo),
          // Notifier reads `ref.watch(localeProvider)` in build(); stub
          // it to skip the Hive bootstrap that the real notifier needs.
          localeProvider.overrideWith(_LocaleStub.new),
        ],
      );
      addTearDown(container.dispose);
    });

    Workout makeWorkout(int i) => Workout.fromJson(
      TestWorkoutFactory.create(
        id: 'workout-$i',
        finishedAt: DateTime(2026, 5, 28 - i).toIso8601String(),
      ),
    );

    test('swallows transient errors without throwing', () async {
      // First page returns 20 workouts (`hasMore: true` because the page
      // was full). Second page throws — simulating a transient network
      // blip on the load-more RPC. Discriminate by the presence of the
      // `offset` named arg: build() omits it, loadMore() always sets it
      // to the current page-end offset. Mocktail's `any(named: 'offset')`
      // would otherwise match the omit case too and the build() path
      // would throw on its initial fetch.
      final firstPage = List.generate(20, makeWorkout);
      when(
        () => mockRepo.getWorkoutHistory(
          any(),
          locale: any(named: 'locale'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => firstPage);
      when(
        () => mockRepo.getWorkoutHistory(
          any(),
          locale: any(named: 'locale'),
          limit: any(named: 'limit'),
          offset: 20,
        ),
      ).thenThrow(const app.NetworkException('boom'));

      // Build the notifier (resolves the initial page).
      await container.read(workoutHistoryProvider.future);
      final initial = container.read(workoutHistoryProvider).value!;
      expect(initial.workouts, hasLength(20));
      expect(initial.hasMore, isTrue);
      expect(initial.isLoadingMore, isFalse);

      // The contract: loadMore must return normally even though the repo
      // throws. A rethrow would land in Flutter's
      // `dart_vm_initializer` because `_onScroll` is fire-and-forget.
      await expectLater(
        container.read(workoutHistoryProvider.notifier).loadMore(),
        completes,
      );

      // State restored: spinner cleared, list unchanged.
      final after = container.read(workoutHistoryProvider).value!;
      expect(after.isLoadingMore, isFalse);
      expect(
        after.workouts,
        initial.workouts,
        reason: 'loadMore must not mutate the list on transient failure',
      );
      expect(after.hasMore, initial.hasMore);
    });
  });
}

// Test-scoped helper, populated in setUp so each test gets a fresh closure
// bound to the freshly-built container/stream.
late void Function(String userId) _swapUser;
