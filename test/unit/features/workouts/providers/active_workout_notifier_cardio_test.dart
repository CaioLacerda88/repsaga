// Phase 38b — cardio entry lifecycle on the active-workout notifier.
//
// Pins the user-visible state contracts (behavior-not-wiring):
//   * adding a cardio exercise seeds a default 30:00 CardioSession and NO
//     weight×reps sets;
//   * duration / distance / RPE edits land on the state (what the
//     CardioEntryCard renders);
//   * "Concluir cardio" toggles completion;
//   * a completed cardio entry counts as committable work for the
//     empty-session finish guard (`totalSetsCount`);
//   * swap is modality-safe (cardio→cardio carries the entry; cross-modality
//     resets the payload);
//   * finish persists ONLY completed cardio entries via the repo `cardio:`
//     param (online) / `PendingSaveWorkout.cardioJson` (offline), and cardio
//     entries never produce workout_exercises / sets payload rows.

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
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/workouts/data/workout_local_storage.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/cardio_session.dart';
import 'package:repsaga/features/workouts/models/exercise_set.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/models/workout_exercise.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase show User;

import '../../../../fixtures/test_factories.dart';

class _MockWorkoutRepository extends Mock implements WorkoutRepository {}

class _MockWorkoutLocalStorage extends Mock implements WorkoutLocalStorage {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _FakeActiveWorkoutState extends Fake implements ActiveWorkoutState {}

class _FakeWorkout extends Fake implements Workout {}

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

supabase.User _fakeUser({String id = 'user-cardio-001'}) {
  return supabase.User(
    id: id,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
    isAnonymous: false,
  );
}

Exercise _treadmill({String id = 'exercise-treadmill'}) {
  return Exercise.fromJson(
    TestExerciseFactory.create(
      id: id,
      name: 'Treadmill',
      muscleGroup: 'cardio',
      equipmentType: 'machine',
      slug: 'treadmill',
    ),
  );
}

Exercise _rowingMachine() {
  return Exercise.fromJson(
    TestExerciseFactory.create(
      id: 'exercise-rower',
      name: 'Rowing Machine',
      muscleGroup: 'cardio',
      equipmentType: 'machine',
      slug: 'rowing_machine',
    ),
  );
}

Exercise _benchPress() {
  return Exercise.fromJson(
    TestExerciseFactory.create(
      id: 'exercise-bench',
      name: 'Bench Press',
      muscleGroup: 'chest',
      equipmentType: 'barbell',
      slug: 'barbell_bench_press',
    ),
  );
}

({
  ProviderContainer container,
  _MockWorkoutRepository mockRepo,
  _CapturingPendingSyncNotifier pendingSync,
})
_makeBundle(ActiveWorkoutState? initial) {
  final mockRepo = _MockWorkoutRepository();
  final mockStorage = _MockWorkoutLocalStorage();
  final mockAuth = _MockAuthRepository();
  final pendingSync = _CapturingPendingSyncNotifier();

  when(() => mockStorage.loadActiveWorkout()).thenReturn(initial);
  when(() => mockStorage.saveActiveWorkout(any())).thenAnswer((_) async {});
  when(() => mockStorage.clearActiveWorkout()).thenAnswer((_) async {});
  when(() => mockAuth.currentUser).thenReturn(_fakeUser());
  when(() => mockRepo.getCachedWorkoutCount(any())).thenReturn(1);
  when(() => mockRepo.incrementCachedWorkoutCount(any())).thenAnswer((_) {});
  when(() => mockRepo.evictHistoryCaches(any())).thenAnswer((_) {});
  when(
    () => mockRepo.getLastWorkoutSets(any()),
  ).thenAnswer((_) async => const <String, List<ExerciseSet>>{});

  final container = ProviderContainer(
    overrides: [
      workoutRepositoryProvider.overrideWithValue(mockRepo),
      workoutLocalStorageProvider.overrideWithValue(mockStorage),
      authRepositoryProvider.overrideWithValue(mockAuth),
      analyticsRepositoryProvider.overrideWithValue(
        const _FakeAnalyticsRepository(),
      ),
      pendingSyncProvider.overrideWith(() => pendingSync),
    ],
  );
  return (container: container, mockRepo: mockRepo, pendingSync: pendingSync);
}

/// An active workout with one strength exercise (1 completed set) and one
/// cardio entry. [cardioCompleted] toggles the entry's done state;
/// [strengthCompleted] the bench set's.
ActiveWorkoutState _mixedState({
  bool cardioCompleted = false,
  bool strengthCompleted = true,
}) {
  return ActiveWorkoutState(
    workout: Workout.fromJson(TestWorkoutFactory.create(isActive: true)),
    exercises: [
      ActiveWorkoutExercise(
        workoutExercise: WorkoutExercise(
          id: 'we-bench',
          workoutId: 'workout-001',
          exerciseId: 'exercise-bench',
          order: 0,
          exercise: _benchPress(),
        ),
        sets: [
          ExerciseSet.fromJson(
            TestSetFactory.create(
              id: 'set-bench-1',
              workoutExerciseId: 'we-bench',
              isCompleted: strengthCompleted,
            ),
          ),
        ],
      ),
      ActiveWorkoutExercise(
        workoutExercise: WorkoutExercise(
          id: 'we-cardio',
          workoutId: 'workout-001',
          exerciseId: 'exercise-treadmill',
          order: 1,
          exercise: _treadmill(),
        ),
        sets: const [],
        cardioSession: CardioSession(
          id: 'cardio-001',
          workoutId: 'workout-001',
          exerciseId: 'exercise-treadmill',
          durationSeconds: 1725,
          distanceM: 5200.0,
          rpe: 7,
          isCompleted: cardioCompleted,
          createdAt: DateTime.utc(2026, 6, 12, 10),
        ),
      ),
    ],
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeActiveWorkoutState());
    registerFallbackValue(_FakeWorkout());
  });

  group('addExercise — cardio modality', () {
    test('seeds a default 30:00 CardioSession and NO sets', () async {
      final bundle = _makeBundle(
        ActiveWorkoutState.fromJson(TestActiveWorkoutStateFactory.create()),
      );
      addTearDown(bundle.container.dispose);
      await bundle.container.read(activeWorkoutProvider.future);

      await bundle.container
          .read(activeWorkoutProvider.notifier)
          .addExercise(_treadmill());

      final state = bundle.container.read(activeWorkoutProvider).value!;
      final entry = state.exercises.single;
      expect(entry.sets, isEmpty, reason: 'cardio carries no weight×reps sets');
      final session = entry.cardioSession;
      expect(session, isNotNull);
      expect(
        session!.durationSeconds,
        30 * 60,
        reason: 'locked mockup empty-state default is 30:00',
      );
      expect(session.distanceM, isNull, reason: 'distance invites, never 0.0');
      expect(session.rpe, isNull);
      expect(session.isCompleted, isFalse);
      expect(session.exerciseId, 'exercise-treadmill');
      expect(session.workoutId, state.workout.id);
    });

    test(
      'strength addExercise is untouched — seeds set 1, no cardio session',
      () async {
        final bundle = _makeBundle(
          ActiveWorkoutState.fromJson(TestActiveWorkoutStateFactory.create()),
        );
        addTearDown(bundle.container.dispose);
        await bundle.container.read(activeWorkoutProvider.future);

        await bundle.container
            .read(activeWorkoutProvider.notifier)
            .addExercise(_benchPress());

        final entry = bundle.container
            .read(activeWorkoutProvider)
            .value!
            .exercises
            .single;
        expect(entry.sets, hasLength(1));
        expect(entry.cardioSession, isNull);
      },
    );
  });

  group('cardio entry mutations', () {
    test(
      'updateCardioSession lands duration / distance / RPE on the state',
      () async {
        final bundle = _makeBundle(_mixedState());
        addTearDown(bundle.container.dispose);
        await bundle.container.read(activeWorkoutProvider.future);
        final notifier = bundle.container.read(activeWorkoutProvider.notifier);

        await notifier.updateCardioSession(
          'we-cardio',
          durationSeconds: 2400,
          distanceM: 8000.0,
          rpe: 9,
        );

        final session = bundle.container
            .read(activeWorkoutProvider)
            .value!
            .exercises[1]
            .cardioSession!;
        expect(session.durationSeconds, 2400);
        expect(session.distanceM, 8000.0);
        expect(session.rpe, 9);
      },
    );

    test(
      'null params leave fields unchanged (same contract as updateSet)',
      () async {
        final bundle = _makeBundle(_mixedState());
        addTearDown(bundle.container.dispose);
        await bundle.container.read(activeWorkoutProvider.future);
        final notifier = bundle.container.read(activeWorkoutProvider.notifier);

        await notifier.updateCardioSession('we-cardio', durationSeconds: 600);

        final session = bundle.container
            .read(activeWorkoutProvider)
            .value!
            .exercises[1]
            .cardioSession!;
        expect(session.durationSeconds, 600);
        expect(session.distanceM, 5200.0, reason: 'distance untouched');
        expect(session.rpe, 7, reason: 'rpe untouched');
      },
    );

    test('completeCardioEntry toggles (complete, then un-complete)', () async {
      final bundle = _makeBundle(_mixedState());
      addTearDown(bundle.container.dispose);
      await bundle.container.read(activeWorkoutProvider.future);
      final notifier = bundle.container.read(activeWorkoutProvider.notifier);

      await notifier.completeCardioEntry('we-cardio');
      expect(
        bundle.container
            .read(activeWorkoutProvider)
            .value!
            .exercises[1]
            .cardioSession!
            .isCompleted,
        isTrue,
      );

      await notifier.completeCardioEntry('we-cardio');
      expect(
        bundle.container
            .read(activeWorkoutProvider)
            .value!
            .exercises[1]
            .cardioSession!
            .isCompleted,
        isFalse,
        reason: 'the green ✓ tap re-opens the entry for edits',
      );
    });
  });

  group('totalSetsCount — empty-session finish guard', () {
    test('a completed cardio entry counts as committable work', () async {
      // Cardio-only shape: bench set NOT completed, cardio completed. The
      // pre-38b getter would return 0 and the finish guard would block a
      // user who genuinely logged a run.
      final bundle = _makeBundle(
        _mixedState(cardioCompleted: true, strengthCompleted: false),
      );
      addTearDown(bundle.container.dispose);
      await bundle.container.read(activeWorkoutProvider.future);

      expect(
        bundle.container.read(activeWorkoutProvider.notifier).totalSetsCount,
        1,
      );
    });

    test(
      'an INCOMPLETE cardio entry does not count (guard still fires)',
      () async {
        final bundle = _makeBundle(_mixedState(strengthCompleted: false));
        addTearDown(bundle.container.dispose);
        await bundle.container.read(activeWorkoutProvider.future);

        expect(
          bundle.container.read(activeWorkoutProvider.notifier).totalSetsCount,
          0,
        );
      },
    );

    test('mixed session sums completed sets + completed cardio', () async {
      final bundle = _makeBundle(_mixedState(cardioCompleted: true));
      addTearDown(bundle.container.dispose);
      await bundle.container.read(activeWorkoutProvider.future);

      expect(
        bundle.container.read(activeWorkoutProvider.notifier).totalSetsCount,
        2,
      );
    });
  });

  group('swapExercise — modality safety', () {
    test('cardio→cardio carries the in-progress entry, re-pointed at the new '
        'exercise', () async {
      final bundle = _makeBundle(_mixedState());
      addTearDown(bundle.container.dispose);
      await bundle.container.read(activeWorkoutProvider.future);

      await bundle.container
          .read(activeWorkoutProvider.notifier)
          .swapExercise('we-cardio', _rowingMachine());

      final entry = bundle.container
          .read(activeWorkoutProvider)
          .value!
          .exercises[1];
      expect(entry.workoutExercise.exerciseId, 'exercise-rower');
      final session = entry.cardioSession!;
      expect(session.exerciseId, 'exercise-rower');
      expect(
        session.durationSeconds,
        1725,
        reason: 'in-progress duration must survive a same-modality swap',
      );
      expect(session.distanceM, 5200.0);
      expect(session.rpe, 7);
    });

    test(
      'cardio→strength drops the cardio payload (no dangling session)',
      () async {
        final bundle = _makeBundle(_mixedState());
        addTearDown(bundle.container.dispose);
        await bundle.container.read(activeWorkoutProvider.future);

        await bundle.container
            .read(activeWorkoutProvider.notifier)
            .swapExercise('we-cardio', _benchPress());

        final entry = bundle.container
            .read(activeWorkoutProvider)
            .value!
            .exercises[1];
        expect(entry.cardioSession, isNull);
        expect(entry.sets, isEmpty, reason: 'user adds sets via Add Set');
      },
    );

    test(
      'strength→cardio drops the sets and seeds a fresh default entry',
      () async {
        final bundle = _makeBundle(_mixedState());
        addTearDown(bundle.container.dispose);
        await bundle.container.read(activeWorkoutProvider.future);

        await bundle.container
            .read(activeWorkoutProvider.notifier)
            .swapExercise('we-bench', _treadmill(id: 'exercise-treadmill-2'));

        final entry = bundle.container
            .read(activeWorkoutProvider)
            .value!
            .exercises[0];
        expect(
          entry.sets,
          isEmpty,
          reason:
              'stale strength sets must not ride '
              'invisibly under a cardio card into history',
        );
        final session = entry.cardioSession!;
        expect(session.durationSeconds, 30 * 60);
        expect(session.exerciseId, 'exercise-treadmill-2');
        expect(session.isCompleted, isFalse);
      },
    );

    test(
      'strength→strength keeps the sets (historical contract untouched)',
      () async {
        final bundle = _makeBundle(_mixedState());
        addTearDown(bundle.container.dispose);
        await bundle.container.read(activeWorkoutProvider.future);

        final replacement = Exercise.fromJson(
          TestExerciseFactory.create(
            id: 'exercise-incline',
            name: 'Incline Press',
            muscleGroup: 'chest',
            slug: 'incline_press',
          ),
        );
        await bundle.container
            .read(activeWorkoutProvider.notifier)
            .swapExercise('we-bench', replacement);

        final entry = bundle.container
            .read(activeWorkoutProvider)
            .value!
            .exercises[0];
        expect(entry.sets, hasLength(1));
        expect(entry.workoutExercise.exerciseId, 'exercise-incline');
        expect(entry.cardioSession, isNull);
      },
    );
  });

  group('finishWorkout — cardio persistence', () {
    test('online save: completed cardio entries ride the repo `cardio:` '
        'param; cardio produces NO workout_exercises / sets rows', () async {
      final bundle = _makeBundle(_mixedState(cardioCompleted: true));
      addTearDown(bundle.container.dispose);

      late List<WorkoutExercise> capturedExercises;
      late List<ExerciseSet> capturedSets;
      late List<CardioSession> capturedCardio;
      when(
        () => bundle.mockRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
          cardio: any(named: 'cardio'),
          routineId: any(named: 'routineId'),
        ),
      ).thenAnswer((invocation) async {
        capturedExercises =
            invocation.namedArguments[#exercises] as List<WorkoutExercise>;
        capturedSets = invocation.namedArguments[#sets] as List<ExerciseSet>;
        capturedCardio =
            invocation.namedArguments[#cardio] as List<CardioSession>;
        return invocation.namedArguments[#workout] as Workout;
      });

      await bundle.container.read(activeWorkoutProvider.future);
      await bundle.container
          .read(activeWorkoutProvider.notifier)
          .finishWorkout();

      // The completed cardio entry lands in p_cardio …
      expect(capturedCardio, hasLength(1));
      expect(capturedCardio.single.id, 'cardio-001');
      expect(capturedCardio.single.durationSeconds, 1725);
      // … and NOT in the strength payload (cardio entries are deliberately
      // not workout_exercises rows — an empty set-table card in history
      // would read as a bug; CardioLiftRow rendering is 38c/38d).
      expect(capturedExercises.map((e) => e.id).toList(), equals(['we-bench']));
      expect(
        capturedSets.every((s) => s.workoutExerciseId == 'we-bench'),
        isTrue,
      );
    });

    test('online save: an INCOMPLETE cardio entry is dropped (same contract '
        'as incomplete sets)', () async {
      final bundle = _makeBundle(_mixedState());
      addTearDown(bundle.container.dispose);

      late List<CardioSession> capturedCardio;
      when(
        () => bundle.mockRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
          cardio: any(named: 'cardio'),
          routineId: any(named: 'routineId'),
        ),
      ).thenAnswer((invocation) async {
        capturedCardio =
            invocation.namedArguments[#cardio] as List<CardioSession>;
        return invocation.namedArguments[#workout] as Workout;
      });

      await bundle.container.read(activeWorkoutProvider.future);
      await bundle.container
          .read(activeWorkoutProvider.notifier)
          .finishWorkout();

      expect(capturedCardio, isEmpty);
    });

    test('offline queue: cardioJson mirrors the online payload via '
        'toRpcJson (no online/offline drift)', () async {
      final bundle = _makeBundle(_mixedState(cardioCompleted: true));
      addTearDown(bundle.container.dispose);

      when(
        () => bundle.mockRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
          cardio: any(named: 'cardio'),
          routineId: any(named: 'routineId'),
        ),
      ).thenThrow(const app.NetworkException('No connection'));

      await bundle.container.read(activeWorkoutProvider.future);
      await bundle.container
          .read(activeWorkoutProvider.notifier)
          .finishWorkout();

      expect(bundle.pendingSync.enqueued, hasLength(1));
      final action = bundle.pendingSync.enqueued.single as PendingSaveWorkout;
      expect(action.cardioJson, hasLength(1));
      expect(action.cardioJson.single, {
        'id': 'cardio-001',
        'workout_id': 'workout-001',
        'exercise_id': 'exercise-treadmill',
        'duration_seconds': 1725,
        'distance_m': 5200.0,
        'rpe': 7,
        'created_at': '2026-06-12T10:00:00.000Z',
      });
    });
  });
}
