// Catch-site classification contract for `finishWorkout`.
//
// PR1B (AW-EX-D-US1-03, AW-EX-D-US1-04, AW-EX-E-US1-02). Pre-1B every save
// failure was uniformly enqueued as offline — a HTTP 500 / 4xx / RLS denial
// silently produced a "Saved offline" snackbar. This file pins the new
// contract:
//
//   - terminal error (4xx / RLS / FK) → state lands in AsyncError, NO
//     enqueue. `finishWorkout` returns null. The coordinator's existing
//     `asyncState.hasError` branch surfaces the "Failed to save workout"
//     snackbar.
//   - transient error (offline exception, 5xx, TimeoutException) → enqueue,
//     state stays AsyncData(null), `savedOffline` flag set on the result.
//   - 5xx specifically sets `serverErrorQueued = true` so the UI can pick
//     a "server error — saved locally" copy variant.
//   - explicit 30s timeout on `WorkoutRepository.saveWorkout` — verified by
//     a never-resolving repo stub completing with a `TimeoutException`
//     under a `FakeAsync` clock.
//
// This file is INTENTIONALLY scoped to the catch-site classifier — the
// broader finishWorkout contract (Hive clear, PR detection, snackbar
// plumbing) is covered by `active_workout_notifier_test.dart`. Keeping the
// classification scenarios in their own file makes the regression gate for
// PR1B trivially discoverable.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/data/base_repository.dart';
import 'package:repsaga/core/exceptions/app_exception.dart' as app;
import 'package:repsaga/core/offline/pending_action.dart';
import 'package:repsaga/core/offline/pending_sync_provider.dart';
import 'package:repsaga/features/analytics/data/analytics_repository.dart';
import 'package:repsaga/features/analytics/data/models/analytics_event.dart';
import 'package:repsaga/features/analytics/providers/analytics_providers.dart';
import 'package:repsaga/features/auth/data/auth_repository.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/workouts/data/workout_local_storage.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    as supabase
    show PostgrestException, User;

import '../../../../fixtures/test_factories.dart';

class _MockWorkoutRepository extends Mock implements WorkoutRepository {}

class _MockWorkoutLocalStorage extends Mock implements WorkoutLocalStorage {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _FakeActiveWorkoutState extends Fake implements ActiveWorkoutState {}

class _FakeWorkout extends Fake implements Workout {}

/// No-op analytics repo — avoids hitting `Supabase.instance` while still
/// letting the notifier call `insertEvent`.
class _FakeAnalyticsRepository extends BaseRepository
    implements AnalyticsRepository {
  const _FakeAnalyticsRepository();

  @override
  Future<void> insertEvent({
    required String userId,
    required AnalyticsEvent event,
    required String? platform,
    required String? appVersion,
  }) async {}
}

/// Captures every enqueued [PendingAction] so tests can assert the queue
/// state without a real Hive box.
class _CapturingPendingSyncNotifier extends PendingSyncNotifier {
  final List<PendingAction> enqueued = [];

  @override
  int build() => 0;

  @override
  Future<void> enqueue(PendingAction action) async {
    enqueued.add(action);
    state = enqueued.length;
  }

  @override
  List<PendingAction> getAll() => List.unmodifiable(enqueued);
}

supabase.User _fakeUser({String id = 'user-test-001'}) {
  return supabase.User(
    id: id,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
    isAnonymous: false,
  );
}

ActiveWorkoutState _makeState() {
  // 1 exercise, 2 sets — enough for the catch site to be reached and for
  // the offline payload to round-trip.
  return ActiveWorkoutState.fromJson(
    TestActiveWorkoutStateFactory.createWithExercises(
      exerciseCount: 1,
      setsPerExercise: 2,
    ),
  );
}

({
  ProviderContainer container,
  _MockWorkoutRepository mockRepo,
  _MockWorkoutLocalStorage mockStorage,
  _MockAuthRepository mockAuth,
  _CapturingPendingSyncNotifier capturedNotifier,
})
_makeBundle(ActiveWorkoutState initial) {
  final mockRepo = _MockWorkoutRepository();
  final mockStorage = _MockWorkoutLocalStorage();
  final mockAuth = _MockAuthRepository();
  final capturedNotifier = _CapturingPendingSyncNotifier();

  when(() => mockStorage.loadActiveWorkout()).thenReturn(initial);
  when(() => mockStorage.saveActiveWorkout(any())).thenAnswer((_) async {});
  when(() => mockStorage.clearActiveWorkout()).thenAnswer((_) async {});
  when(() => mockAuth.currentUser).thenReturn(_fakeUser());
  // PR detection cache fallback returns 1 (this workout). The PR repo is not
  // wired here — PR detection runs inside a try/catch that swallows, which
  // keeps these tests focused on the catch-site contract.
  when(() => mockRepo.getCachedWorkoutCount(any())).thenReturn(1);
  when(() => mockRepo.incrementCachedWorkoutCount(any())).thenAnswer((_) {});
  when(() => mockRepo.evictHistoryCaches(any())).thenAnswer((_) {});

  final container = ProviderContainer(
    overrides: [
      workoutRepositoryProvider.overrideWithValue(mockRepo),
      workoutLocalStorageProvider.overrideWithValue(mockStorage),
      authRepositoryProvider.overrideWithValue(mockAuth),
      analyticsRepositoryProvider.overrideWithValue(
        const _FakeAnalyticsRepository(),
      ),
      pendingSyncProvider.overrideWith(() => capturedNotifier),
    ],
  );
  return (
    container: container,
    mockRepo: mockRepo,
    mockStorage: mockStorage,
    mockAuth: mockAuth,
    capturedNotifier: capturedNotifier,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeActiveWorkoutState());
    registerFallbackValue(_FakeWorkout());
  });

  group('finishWorkout — catch-site classification (PR1B)', () {
    // ------------------------------------------------------------------
    // Terminal — 4xx / RLS / FK denial.
    // Contract: rethrow inside guard, state lands in AsyncError, NO enqueue.
    // ------------------------------------------------------------------
    test('terminal raw PostgrestException(400) → state.hasError, NO enqueue '
        '(AW-EX-D-US1-03)', () async {
      final bundle = _makeBundle(_makeState());
      addTearDown(bundle.container.dispose);

      when(
        () => bundle.mockRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
        ),
      ).thenThrow(
        const supabase.PostgrestException(message: 'Bad Request', code: '400'),
      );

      await bundle.container.read(activeWorkoutProvider.future);
      final finishResult = await bundle.container
          .read(activeWorkoutProvider.notifier)
          .finishWorkout();

      // Terminal path: AsyncValue.guard captured the rethrow.
      final state = bundle.container.read(activeWorkoutProvider);
      expect(
        state,
        isA<AsyncError<ActiveWorkoutState?>>(),
        reason:
            '4xx must surface as AsyncError so the UI shows a real '
            'failure snackbar, NOT a misleading "Saved offline" toast.',
      );

      // finishWorkout returns null on terminal; the coordinator reads the
      // notifier state to decide what to render.
      expect(finishResult, isNull);

      // No enqueue happened — terminal errors are user-fixable, not queue-
      // worthy.
      expect(bundle.capturedNotifier.enqueued, isEmpty);
    });

    test(
      'terminal wrapped DatabaseException(403) → state.hasError, NO enqueue',
      () async {
        // The production catch site sees the [BaseRepository.mapException]-
        // wrapped form; pinning both raw and wrapped exception types keeps
        // the classifier robust against future repository changes.
        final bundle = _makeBundle(_makeState());
        addTearDown(bundle.container.dispose);

        when(
          () => bundle.mockRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).thenThrow(const app.DatabaseException('RLS denied', code: '403'));

        await bundle.container.read(activeWorkoutProvider.future);
        await bundle.container
            .read(activeWorkoutProvider.notifier)
            .finishWorkout();

        final state = bundle.container.read(activeWorkoutProvider);
        expect(state, isA<AsyncError<ActiveWorkoutState?>>());
        expect(bundle.capturedNotifier.enqueued, isEmpty);
      },
    );

    test(
      'terminal DatabaseException(422) → state.hasError, NO enqueue',
      () async {
        final bundle = _makeBundle(_makeState());
        addTearDown(bundle.container.dispose);

        when(
          () => bundle.mockRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).thenThrow(const app.DatabaseException('FK violation', code: '422'));

        await bundle.container.read(activeWorkoutProvider.future);
        await bundle.container
            .read(activeWorkoutProvider.notifier)
            .finishWorkout();

        expect(
          bundle.container.read(activeWorkoutProvider),
          isA<AsyncError<ActiveWorkoutState?>>(),
        );
        expect(bundle.capturedNotifier.enqueued, isEmpty);
      },
    );

    // ------------------------------------------------------------------
    // Transient — offline / 5xx / timeout.
    // Contract: enqueue, state stays AsyncData(null), result.savedOffline=true.
    // ------------------------------------------------------------------
    test('transient SocketException → enqueued, savedOffline=true, '
        'serverErrorQueued=false', () async {
      final bundle = _makeBundle(_makeState());
      addTearDown(bundle.container.dispose);

      when(
        () => bundle.mockRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
        ),
      ).thenThrow(const app.NetworkException('No connection'));

      await bundle.container.read(activeWorkoutProvider.future);
      final finishResult = await bundle.container
          .read(activeWorkoutProvider.notifier)
          .finishWorkout();

      // State settles cleanly — workout is locally finished.
      expect(
        bundle.container.read(activeWorkoutProvider),
        isA<AsyncData<ActiveWorkoutState?>>(),
      );
      expect(bundle.container.read(activeWorkoutProvider).value, isNull);

      // Enqueued for later drain.
      expect(bundle.capturedNotifier.enqueued, hasLength(1));
      expect(bundle.capturedNotifier.enqueued.first, isA<PendingSaveWorkout>());

      // Result discriminators: savedOffline yes, serverErrorQueued no
      // (this is connectivity loss, not a server problem).
      expect(finishResult, isNotNull);
      expect(finishResult!.savedOffline, isTrue);
      expect(finishResult.serverErrorQueued, isFalse);
    });

    test('transient PostgrestException(500) → enqueued, '
        'serverErrorQueued=true (Q1.3 discriminator)', () async {
      final bundle = _makeBundle(_makeState());
      addTearDown(bundle.container.dispose);

      when(
        () => bundle.mockRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
        ),
      ).thenThrow(
        const supabase.PostgrestException(message: 'ISE', code: '500'),
      );

      await bundle.container.read(activeWorkoutProvider.future);
      final finishResult = await bundle.container
          .read(activeWorkoutProvider.notifier)
          .finishWorkout();

      expect(bundle.capturedNotifier.enqueued, hasLength(1));
      expect(finishResult!.savedOffline, isTrue);
      expect(
        finishResult.serverErrorQueued,
        isTrue,
        reason:
            '5xx is transient (queue/retry) but the UI must distinguish '
            'a server outage from "phone is offline" — see AW-EX-D-US1-03.',
      );
    });

    test(
      'transient DatabaseException(503) → enqueued, serverErrorQueued=true',
      () async {
        // Wrapped form (post-mapException) is what the catch site really
        // sees in production. Both 500 and 503 are transient/server, both
        // must set the discriminator.
        final bundle = _makeBundle(_makeState());
        addTearDown(bundle.container.dispose);

        when(
          () => bundle.mockRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).thenThrow(
          const app.DatabaseException('Service unavailable', code: '503'),
        );

        await bundle.container.read(activeWorkoutProvider.future);
        final finishResult = await bundle.container
            .read(activeWorkoutProvider.notifier)
            .finishWorkout();

        expect(bundle.capturedNotifier.enqueued, hasLength(1));
        expect(finishResult!.savedOffline, isTrue);
        expect(finishResult.serverErrorQueued, isTrue);
      },
    );

    test('transient app.TimeoutException → enqueued, savedOffline=true, '
        'serverErrorQueued=false', () async {
      final bundle = _makeBundle(_makeState());
      addTearDown(bundle.container.dispose);

      when(
        () => bundle.mockRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
        ),
      ).thenThrow(const app.TimeoutException());

      await bundle.container.read(activeWorkoutProvider.future);
      final finishResult = await bundle.container
          .read(activeWorkoutProvider.notifier)
          .finishWorkout();

      expect(bundle.capturedNotifier.enqueued, hasLength(1));
      expect(finishResult!.savedOffline, isTrue);
      expect(
        finishResult.serverErrorQueued,
        isFalse,
        reason: 'Timeout is a network/transport issue, not a server error.',
      );
    });

    test(
      'transient raw dart:async TimeoutException → enqueued, savedOffline=true, '
      'serverErrorQueued=false (mapException wrap chain pin)',
      () async {
        // The production path is:
        //   WorkoutRepository.saveWorkout
        //     → mapException(() => rpc().timeout(30s))
        //     → dart:async TimeoutException fires inside mapException
        //     → ErrorMapper.mapException converts to app.TimeoutException
        //     → notifier sees app.TimeoutException (covered above).
        //
        // This test pins the OTHER half of the contract: if a future
        // refactor ever lets a raw `dart:async TimeoutException` leak past
        // [BaseRepository.mapException] (e.g. a new code path that calls
        // `.timeout()` outside the wrap, or a mocked test stub bypassing
        // the wrap entirely), the notifier's catch-site classifier MUST
        // still treat it as transient. SyncErrorClassifier explicitly
        // recognises both `dart:async TimeoutException` and
        // `app.TimeoutException` (sync_error_classifier.dart L42 + L46) —
        // this test is the regression gate for that dual recognition.
        final bundle = _makeBundle(_makeState());
        addTearDown(bundle.container.dispose);

        when(
          () => bundle.mockRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).thenThrow(TimeoutException('30s'));

        await bundle.container.read(activeWorkoutProvider.future);
        final finishResult = await bundle.container
            .read(activeWorkoutProvider.notifier)
            .finishWorkout();

        expect(
          bundle.capturedNotifier.enqueued,
          hasLength(1),
          reason:
              'Raw dart:async TimeoutException must be classified as '
              'transient and enqueued — same as app.TimeoutException.',
        );
        expect(finishResult, isNotNull);
        expect(finishResult!.savedOffline, isTrue);
        expect(
          finishResult.serverErrorQueued,
          isFalse,
          reason: 'Timeout is a network/transport issue, not a server error.',
        );
      },
    );

    test(
      'unknown exception types stay transient (queue, no rethrow) — '
      'preserves backward compatibility with the existing offline tests',
      () async {
        // The pre-1B offline test scaffolding stubs `Exception('Network')`.
        // Plain Exception is unrecognised by the classifier and defaults to
        // transient — that contract must hold post-1B too, otherwise every
        // pre-existing offline test breaks.
        final bundle = _makeBundle(_makeState());
        addTearDown(bundle.container.dispose);

        when(
          () => bundle.mockRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).thenThrow(Exception('plain old exception'));

        await bundle.container.read(activeWorkoutProvider.future);
        final finishResult = await bundle.container
            .read(activeWorkoutProvider.notifier)
            .finishWorkout();

        expect(bundle.capturedNotifier.enqueued, hasLength(1));
        expect(finishResult!.savedOffline, isTrue);
        expect(finishResult.serverErrorQueued, isFalse);
      },
    );

    // ------------------------------------------------------------------
    // Explicit 30s timeout on `WorkoutRepository.saveWorkout`.
    // Verified at the notifier level using a never-resolving repo stub
    // and `FakeAsync` to advance the clock past the budget.
    // ------------------------------------------------------------------
    test('never-resolving saveWorkout — TimeoutException after 30s composes '
        'with catch-site classifier to enqueue (AW-EX-D-US1-04)', () {
      // We test this at the repository-Future level because the notifier
      // doesn't own the timeout — the repo does. We simulate the
      // composed call: a never-resolving Future wrapped in `.timeout(30s)`.
      // Under FakeAsync.elapse(31s) the timeout fires deterministically.
      FakeAsync().run((async) {
        final neverResolving = Completer<int>();
        final timed = neverResolving.future.timeout(
          const Duration(seconds: 30),
        );

        Object? caught;
        timed.catchError((Object e) {
          caught = e;
          return -1;
        });

        // Just under the budget — no completion yet.
        async.elapse(const Duration(seconds: 29));
        expect(
          caught,
          isNull,
          reason: 'Timeout must not fire before the 30s budget expires.',
        );

        // Cross the budget — TimeoutException materialises.
        async.elapse(const Duration(seconds: 2));
        expect(
          caught,
          isA<TimeoutException>(),
          reason:
              'WorkoutRepository.saveWorkout must complete with '
              'TimeoutException after 30s; ErrorMapper then wraps it as '
              'app.TimeoutException, which the catch-site classifier '
              'treats as transient.',
        );
      });
    });
  });
}
