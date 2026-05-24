// Bug B regression — save-site filter for completed sets.
//
// User-reported 2026-05-23: "When completing just two sets of exercises and
// saving, it's showing in history as if I completed the whole routine, not
// just the two sets of one routine."
//
// Root cause (pre-existing since Phase 15f): `finishWorkout` forwarded
// `ActiveWorkoutState.exercises` verbatim to `_repo.saveWorkout(...)` —
// never filtered incomplete sets or empty-set exercises. `startFromRoutine`
// pre-populates state with EVERY routine exercise + pre-filled `setCount`
// sets each (`isCompleted: false`), so the finish path persisted the entire
// routine skeleton.
//
// Fix: `committedExercises` derives a filtered shape (only completed sets,
// no empty-set exercises) and drives every downstream persistence path:
//
//   - online `save_workout` RPC payload (workoutExercises + sets)
//   - offline replay payload (PendingSaveWorkout.exercisesJson + setsJson)
//   - PR detection input (already filtered internally, kept consistent)
//   - PR cache key (exerciseIds)
//
// Analytics intentionally keeps the PRE-filter shape so
// `incompleteSetsSkipped` retains its planned-vs-committed meaning.
//
// This file pins the persistence contract at the notifier boundary:
// behavior-not-wiring per CLAUDE.md Testing rule — we assert on the SHAPE
// that lands at the repo (online path) and on the queued PendingAction
// (offline path), not on "the filter was called".
//
// Cluster: planned-shape-persisted-as-actual.

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

supabase.User _fakeUser({String id = 'user-bug-b-001'}) {
  return supabase.User(
    id: id,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
    isAnonymous: false,
  );
}

/// Mirror of the production fixture: a 3-exercise routine where each exercise
/// is pre-populated with planned sets (`isCompleted: false`) — that's what
/// `startFromRoutine` does. The test then mutates individual sets to
/// `isCompleted: true` to model the user tapping through their actual lifts.
///
/// Returns the [ActiveWorkoutState] for direct injection into the notifier
/// via `mockStorage.loadActiveWorkout()`.
ActiveWorkoutState _makeRoutineState({
  required List<int> completedSetsPerExercise,
  required int totalSetsPerExercise,
}) {
  final exerciseCount = completedSetsPerExercise.length;
  final exercises = List.generate(exerciseCount, (i) {
    final weId = 'we-${i + 1}';
    final completedCount = completedSetsPerExercise[i];
    final sets = List.generate(totalSetsPerExercise, (j) {
      // First `completedCount` sets are completed; the rest are the
      // planned-but-not-yet-tapped slots that `startFromRoutine`
      // pre-populates.
      return TestSetFactory.create(
        id: 'set-$weId-${j + 1}',
        workoutExerciseId: weId,
        setNumber: j + 1,
        isCompleted: j < completedCount,
      );
    });
    return {
      'workout_exercise': TestWorkoutExerciseFactory.create(
        id: weId,
        exerciseId: 'exercise-${i + 1}',
        order: i + 1,
      ),
      'sets': sets,
    };
  });

  return ActiveWorkoutState.fromJson({
    'workout': TestWorkoutFactory.create(isActive: true),
    'exercises': exercises,
  });
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

  group('finishWorkout — save-site filter (Bug B)', () {
    test('online save: persists only completed sets and drops exercises with '
        'zero completed sets', () async {
      // Fixture: 3-exercise routine, 4 planned sets each = 12 planned sets.
      //   - Bench Press (we-1): 2 of 4 completed
      //   - OHP         (we-2): 0 of 4 completed → must be dropped entirely
      //   - Triceps     (we-3): 1 of 4 completed
      // Expected persisted shape:
      //   - 2 exercises (Bench Press + Triceps), OHP excluded
      //   - 3 sets total (all isCompleted == true)
      final state = _makeRoutineState(
        completedSetsPerExercise: const [2, 0, 1],
        totalSetsPerExercise: 4,
      );
      final bundle = _makeBundle(state);
      addTearDown(bundle.container.dispose);

      // Capture the args the notifier passes to the repo. `captureAny` is
      // the canonical mocktail pattern for asserting on the shape of a
      // call's payload.
      late List<WorkoutExercise> capturedExercises;
      late List<ExerciseSet> capturedSets;
      when(
        () => bundle.mockRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
          routineId: any(named: 'routineId'),
        ),
      ).thenAnswer((invocation) async {
        capturedExercises =
            invocation.namedArguments[#exercises] as List<WorkoutExercise>;
        capturedSets = invocation.namedArguments[#sets] as List<ExerciseSet>;
        return invocation.namedArguments[#workout] as Workout;
      });

      await bundle.container.read(activeWorkoutProvider.future);
      await bundle.container
          .read(activeWorkoutProvider.notifier)
          .finishWorkout();

      // 2 exercises survived; OHP (zero completed sets) was dropped.
      expect(
        capturedExercises.map((e) => e.id).toList(),
        equals(['we-1', 'we-3']),
        reason: 'OHP (we-2) had zero completed sets → must be dropped',
      );

      // 3 sets persisted (2 + 1); the 9 planned-but-incomplete slots are
      // not persisted.
      expect(
        capturedSets.length,
        3,
        reason:
            'Only 3 sets were actually completed across the routine; '
            'the 9 planned slots must NOT land in the workouts table.',
      );
      expect(
        capturedSets.every((s) => s.isCompleted),
        isTrue,
        reason: 'Every persisted set must carry isCompleted=true',
      );

      // Belt + braces: every persisted set belongs to one of the surviving
      // exercises — no orphan sets from the dropped exercise.
      final survivingWeIds = capturedExercises.map((e) => e.id).toSet();
      expect(
        capturedSets.every((s) => survivingWeIds.contains(s.workoutExerciseId)),
        isTrue,
        reason: 'No persisted set may reference a dropped exercise',
      );
    });

    test('offline replay payload mirrors the online filter '
        '(no online/offline drift)', () async {
      // Same fixture as above — modeled by forcing the repo to throw a
      // transient error so the notifier's catch site enqueues a
      // PendingSaveWorkout. The queued JSON payload must match the
      // online persisted shape exactly, otherwise the drain replays a
      // different workout than what was attempted online (BUG-001
      // adjacent — async-caller-broke-snackbar cluster).
      final state = _makeRoutineState(
        completedSetsPerExercise: const [2, 0, 1],
        totalSetsPerExercise: 4,
      );
      final bundle = _makeBundle(state);
      addTearDown(bundle.container.dispose);

      when(
        () => bundle.mockRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
          routineId: any(named: 'routineId'),
        ),
      ).thenThrow(const app.NetworkException('No connection'));

      await bundle.container.read(activeWorkoutProvider.future);
      await bundle.container
          .read(activeWorkoutProvider.notifier)
          .finishWorkout();

      expect(bundle.capturedNotifier.enqueued, hasLength(1));
      final pending = bundle.capturedNotifier.enqueued.single;
      expect(pending, isA<PendingSaveWorkout>());

      final saveAction = pending as PendingSaveWorkout;

      // 2 exercises in the queued payload (OHP dropped).
      expect(
        saveAction.exercisesJson.map((e) => e['id']).toList(),
        equals(['we-1', 'we-3']),
        reason:
            'Offline replay must persist the same shape as online — OHP '
            'must be dropped in BOTH paths or the drain produces a '
            'different workout than the user finished.',
      );

      // 3 sets, all isCompleted == true.
      expect(saveAction.setsJson.length, 3);
      expect(
        saveAction.setsJson.every((s) => s['is_completed'] == true),
        isTrue,
        reason: 'Offline payload must carry only completed sets',
      );

      // Same orphan-set guard as the online assertion.
      final survivingWeIds = saveAction.exercisesJson
          .map((e) => e['id'] as String)
          .toSet();
      expect(
        saveAction.setsJson.every(
          (s) => survivingWeIds.contains(s['workout_exercise_id'] as String),
        ),
        isTrue,
      );
    });

    test('partial completion across all exercises: every exercise survives, '
        'only completed sets persist', () async {
      // Counter-fixture: 2 exercises, both partially completed. Nothing
      // should be dropped at the exercise level — only the incomplete sets
      // are filtered out within each exercise.
      final state = _makeRoutineState(
        completedSetsPerExercise: const [3, 2],
        totalSetsPerExercise: 4,
      );
      final bundle = _makeBundle(state);
      addTearDown(bundle.container.dispose);

      late List<WorkoutExercise> capturedExercises;
      late List<ExerciseSet> capturedSets;
      when(
        () => bundle.mockRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
          routineId: any(named: 'routineId'),
        ),
      ).thenAnswer((invocation) async {
        capturedExercises =
            invocation.namedArguments[#exercises] as List<WorkoutExercise>;
        capturedSets = invocation.namedArguments[#sets] as List<ExerciseSet>;
        return invocation.namedArguments[#workout] as Workout;
      });

      await bundle.container.read(activeWorkoutProvider.future);
      await bundle.container
          .read(activeWorkoutProvider.notifier)
          .finishWorkout();

      expect(capturedExercises, hasLength(2));
      expect(capturedSets, hasLength(5));
      expect(capturedSets.every((s) => s.isCompleted), isTrue);

      // 3 sets under we-1, 2 sets under we-2 — preserves per-exercise
      // completion counts.
      expect(
        capturedSets.where((s) => s.workoutExerciseId == 'we-1').length,
        3,
      );
      expect(
        capturedSets.where((s) => s.workoutExerciseId == 'we-2').length,
        2,
      );
    });
  });
}
