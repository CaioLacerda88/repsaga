import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:repsaga/core/data/base_repository.dart';
import 'package:repsaga/core/exceptions/app_exception.dart' as app;
import 'package:repsaga/core/l10n/locale_provider.dart';
import 'package:repsaga/core/local_storage/cache_service.dart';
import 'package:repsaga/core/observability/sentry_report.dart';
import 'package:repsaga/core/offline/offline_queue_service.dart';
import 'package:repsaga/core/offline/pending_action.dart';
import 'package:repsaga/core/offline/pending_sync_provider.dart';
import 'package:repsaga/features/analytics/data/analytics_repository.dart';
import 'package:repsaga/features/analytics/data/models/analytics_event.dart';
import 'package:repsaga/features/analytics/providers/analytics_providers.dart';
import 'package:repsaga/features/auth/data/auth_repository.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/personal_records/data/pr_repository.dart';
import 'package:repsaga/features/personal_records/domain/pr_detection_service.dart';
import 'package:repsaga/features/personal_records/models/personal_record.dart';
import 'package:repsaga/features/personal_records/models/record_type.dart';
import 'package:repsaga/features/personal_records/providers/pr_providers.dart';
import 'package:repsaga/features/workouts/data/workout_local_storage.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/exercise_set.dart';
import 'package:repsaga/features/workouts/models/routine_start_config.dart';
import 'package:repsaga/features/workouts/models/set_type.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/models/workout_exercise.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/exercises/providers/exercise_progress_provider.dart';
import 'package:repsaga/features/rpg/data/peak_loads_repository.dart';
import 'package:repsaga/features/rpg/data/rpg_repository.dart';
import 'package:repsaga/features/rpg/models/body_part_progress.dart';
import 'package:repsaga/features/rpg/providers/rpg_progress_provider.dart';
import 'package:repsaga/features/weekly_plan/data/models/weekly_plan.dart';
import 'package:repsaga/features/weekly_plan/providers/weekly_plan_provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show SentryId;
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../../../fixtures/test_factories.dart';
import '../../../../helpers/stub_locale_notifier.dart';

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

class MockWorkoutLocalStorage extends Mock implements WorkoutLocalStorage {}

class MockAuthRepository extends Mock implements AuthRepository {}

class MockOfflineQueueService extends Mock implements OfflineQueueService {}

class MockPRRepository extends Mock implements PRRepository {}

class MockCacheService extends Mock implements CacheService {}

class MockRpgRepository extends Mock implements RpgRepository {}

class MockPeakLoadsRepository extends Mock implements PeakLoadsRepository {}

class FakeActiveWorkoutState extends Fake implements ActiveWorkoutState {}

class FakeWorkout extends Fake implements Workout {}

/// No-op analytics repo used in unit tests — avoids hitting
/// `Supabase.instance` while still letting the notifier call `insertEvent`.
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

/// Recording analytics repo — captures every event so tests can assert on
/// the event content (e.g. `source` value) that the notifier fires.
/// Not `const` so it can accumulate state.
class _RecordingAnalyticsRepository extends BaseRepository
    implements AnalyticsRepository {
  final List<AnalyticsEvent> events = [];

  @override
  Future<void> insertEvent({
    required String userId,
    required AnalyticsEvent event,
    required String? platform,
    required String? appVersion,
  }) async {
    events.add(event);
  }
}

/// Creates a minimal [User] that satisfies the `_userId` getter in the notifier.
User fakeUser({String id = 'user-test-001'}) {
  return User(
    id: id,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
    isAnonymous: false,
  );
}

/// Builds a [Workout] model from the test factory JSON.
Workout makeWorkout({String? id, bool isActive = true}) {
  return Workout.fromJson(
    TestWorkoutFactory.create(id: id, isActive: isActive),
  );
}

/// Builds a typed [ActiveWorkoutState] from the test factories.
ActiveWorkoutState makeState({int exerciseCount = 0, int setsPerExercise = 0}) {
  final json = exerciseCount > 0
      ? TestActiveWorkoutStateFactory.createWithExercises(
          exerciseCount: exerciseCount,
          setsPerExercise: setsPerExercise,
        )
      : TestActiveWorkoutStateFactory.create();
  return ActiveWorkoutState.fromJson(json);
}

Exercise makeExercise({String id = 'exercise-new', String name = 'Squat'}) {
  return Exercise.fromJson(TestExerciseFactory.create(id: id, name: name));
}

/// Creates a container with mocked dependencies and a pre-seeded notifier state.
ProviderContainer makeContainer(ActiveWorkoutState? initialState) {
  final mockRepo = MockWorkoutRepository();
  final mockStorage = MockWorkoutLocalStorage();

  when(() => mockStorage.loadActiveWorkout()).thenReturn(initialState);
  when(() => mockStorage.saveActiveWorkout(any())).thenAnswer((_) async {});

  return ProviderContainer(
    overrides: [
      workoutRepositoryProvider.overrideWithValue(mockRepo),
      workoutLocalStorageProvider.overrideWithValue(mockStorage),
      analyticsRepositoryProvider.overrideWithValue(
        const _FakeAnalyticsRepository(),
      ),
    ],
  );
}

/// Creates a container suitable for testing async methods (startWorkout,
/// finishWorkout, discardWorkout) — includes [MockAuthRepository] so the
/// `_userId` getter can be controlled without touching the Supabase singleton.
({
  ProviderContainer container,
  MockWorkoutRepository mockRepo,
  MockWorkoutLocalStorage mockStorage,
  MockAuthRepository mockAuth,
})
makeAsyncContainer(ActiveWorkoutState? initialState, {Locale? locale}) {
  final mockRepo = MockWorkoutRepository();
  final mockStorage = MockWorkoutLocalStorage();
  final mockAuth = MockAuthRepository();

  when(() => mockStorage.loadActiveWorkout()).thenReturn(initialState);
  when(() => mockStorage.saveActiveWorkout(any())).thenAnswer((_) async {});

  final container = ProviderContainer(
    overrides: [
      workoutRepositoryProvider.overrideWithValue(mockRepo),
      workoutLocalStorageProvider.overrideWithValue(mockStorage),
      authRepositoryProvider.overrideWithValue(mockAuth),
      analyticsRepositoryProvider.overrideWithValue(
        const _FakeAnalyticsRepository(),
      ),
      // Family 6 — `_generateWorkoutName` reads localeProvider. In unit
      // tests Hive isn't initialised, so callers that exercise the
      // start-workout path must pass an explicit `locale:` to install a
      // StubLocaleNotifier override. Other tests skip startWorkout.
      if (locale != null)
        localeProvider.overrideWith(() => StubLocaleNotifier(locale)),
    ],
  );
  return (
    container: container,
    mockRepo: mockRepo,
    mockStorage: mockStorage,
    mockAuth: mockAuth,
  );
}

/// A fake [PendingSyncNotifier] that records enqueued actions in-memory.
/// Used by the offline path tests so no real Hive box is needed.
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

/// Stub [WeeklyPlanNotifier] for the offline H7 finishWorkout test.
///
/// build() returns the seeded plan synchronously so
/// `ref.read(weeklyPlanProvider).value` is non-null. [markRoutineComplete]
/// throws when [throwOnMark] is true, exercising the catch-and-enqueue
/// branch in the production notifier.
class _StubWeeklyPlanNotifier extends WeeklyPlanNotifier {
  _StubWeeklyPlanNotifier({required this.plan, this.throwOnMark = false});

  final WeeklyPlan plan;
  final bool throwOnMark;

  @override
  FutureOr<WeeklyPlan?> build() => plan;

  @override
  Future<void> markRoutineComplete({
    required String routineId,
    required String workoutId,
  }) async {
    if (throwOnMark) {
      throw Exception('Network error from weekly-plan markRoutineComplete');
    }
  }
}

/// Creates a container for offline-path tests. Includes MockAuthRepository
/// and a [_CapturingPendingSyncNotifier] that records all enqueued actions.
({
  ProviderContainer container,
  MockWorkoutRepository mockRepo,
  MockWorkoutLocalStorage mockStorage,
  MockAuthRepository mockAuth,
  _CapturingPendingSyncNotifier capturedNotifier,
})
makeOfflineContainer(ActiveWorkoutState? initialState) {
  final mockRepo = MockWorkoutRepository();
  final mockStorage = MockWorkoutLocalStorage();
  final mockAuth = MockAuthRepository();
  final capturedNotifier = _CapturingPendingSyncNotifier();

  when(() => mockStorage.loadActiveWorkout()).thenReturn(initialState);
  when(() => mockStorage.saveActiveWorkout(any())).thenAnswer((_) async {});
  when(() => mockStorage.clearActiveWorkout()).thenAnswer((_) async {});

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
  setUpAll(() async {
    registerFallbackValue(FakeActiveWorkoutState());
    registerFallbackValue(FakeWorkout());
    // `_generateWorkoutName` uses `DateFormat('EEE MMM d', languageCode)`
    // which requires intl locale data. Initialise it once for the whole
    // suite so tests that exercise startWorkout don't blow up on the
    // first DateFormat call.
    await initializeDateFormatting();
  });

  group('ActiveWorkoutNotifier — local mutations', () {
    // ------------------------------------------------------------------ setup
    group('build', () {
      test('initialises to null when localStorage returns null', () async {
        final container = makeContainer(null);
        addTearDown(container.dispose);

        final state = await container.read(activeWorkoutProvider.future);

        expect(state, isNull);
      });

      test(
        'initialises from persisted state when localStorage has data',
        () async {
          final persisted = makeState(exerciseCount: 1, setsPerExercise: 2);
          final container = makeContainer(persisted);
          addTearDown(container.dispose);

          final state = await container.read(activeWorkoutProvider.future);

          expect(state, isNotNull);
          expect(state!.workout.id, persisted.workout.id);
          expect(state.exercises, hasLength(1));
        },
      );
    });

    // ---------------------------------------------------------------- addExercise
    group('addExercise', () {
      test('adds exercise to an empty workout', () async {
        final container = makeContainer(makeState());
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        container
            .read(activeWorkoutProvider.notifier)
            .addExercise(makeExercise());

        final result = container.read(activeWorkoutProvider).value!;
        expect(result.exercises, hasLength(1));
      });

      test('new exercise has order equal to its index position', () async {
        final container = makeContainer(makeState());
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        final notifier = container.read(activeWorkoutProvider.notifier);
        notifier.addExercise(makeExercise(id: 'ex-a', name: 'Squat'));
        notifier.addExercise(makeExercise(id: 'ex-b', name: 'Deadlift'));

        final result = container.read(activeWorkoutProvider).value!;
        expect(result.exercises[0].workoutExercise.order, 0);
        expect(result.exercises[1].workoutExercise.order, 1);
      });

      test('new exercise starts with no sets', () async {
        final container = makeContainer(makeState());
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        container
            .read(activeWorkoutProvider.notifier)
            .addExercise(makeExercise());

        final result = container.read(activeWorkoutProvider).value!;
        expect(result.exercises.first.sets, isEmpty);
      });

      test('new exercise workoutExercise links to correct workoutId', () async {
        final initial = makeState();
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        container
            .read(activeWorkoutProvider.notifier)
            .addExercise(makeExercise());

        final result = container.read(activeWorkoutProvider).value!;
        expect(
          result.exercises.first.workoutExercise.workoutId,
          initial.workout.id,
        );
      });

      test('does nothing when state is null', () {
        final container = makeContainer(null);
        addTearDown(container.dispose);

        // Should not throw.
        container
            .read(activeWorkoutProvider.notifier)
            .addExercise(makeExercise());

        expect(container.read(activeWorkoutProvider).value, isNull);
      });
    });

    // -------------------------------------------------------------- removeExercise
    group('removeExercise', () {
      test('removes the target exercise from the list', () async {
        final initial = makeState(exerciseCount: 2, setsPerExercise: 1);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        final targetId = initial.exercises.first.workoutExercise.id;
        container.read(activeWorkoutProvider.notifier).removeExercise(targetId);

        final result = container.read(activeWorkoutProvider).value!;
        expect(result.exercises, hasLength(1));
        expect(
          result.exercises.any((e) => e.workoutExercise.id == targetId),
          isFalse,
        );
      });

      test('reorders remaining exercises starting from 0', () async {
        final initial = makeState(exerciseCount: 3, setsPerExercise: 0);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        // Remove the first exercise.
        final firstId = initial.exercises.first.workoutExercise.id;
        container.read(activeWorkoutProvider.notifier).removeExercise(firstId);

        final result = container.read(activeWorkoutProvider).value!;
        expect(result.exercises[0].workoutExercise.order, 0);
        expect(result.exercises[1].workoutExercise.order, 1);
      });

      test('does nothing when workoutExerciseId does not exist', () async {
        final initial = makeState(exerciseCount: 1, setsPerExercise: 0);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        container
            .read(activeWorkoutProvider.notifier)
            .removeExercise('nonexistent-id');

        final result = container.read(activeWorkoutProvider).value!;
        expect(result.exercises, hasLength(1));
      });
    });

    // ------------------------------------------------------------------ addSet
    group('addSet', () {
      test(
        'appends a set with setNumber 1 to an exercise that has no sets',
        () async {
          final initial = makeState(exerciseCount: 1, setsPerExercise: 0);
          final container = makeContainer(initial);
          addTearDown(container.dispose);
          await container.read(activeWorkoutProvider.future);

          final weId = initial.exercises.first.workoutExercise.id;
          container.read(activeWorkoutProvider.notifier).addSet(weId);

          final result = container.read(activeWorkoutProvider).value!;
          final sets = result.exercises.first.sets;
          expect(sets, hasLength(1));
          expect(sets.first.setNumber, 1);
        },
      );

      test('new set number equals existing set count plus one', () async {
        final initial = makeState(exerciseCount: 1, setsPerExercise: 2);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        final weId = initial.exercises.first.workoutExercise.id;
        container.read(activeWorkoutProvider.notifier).addSet(weId);

        final result = container.read(activeWorkoutProvider).value!;
        expect(result.exercises.first.sets, hasLength(3));
        expect(result.exercises.first.sets.last.setNumber, 3);
      });

      test(
        'new set defaults to working type, not completed, zero weight/reps',
        () async {
          final initial = makeState(exerciseCount: 1, setsPerExercise: 0);
          final container = makeContainer(initial);
          addTearDown(container.dispose);
          await container.read(activeWorkoutProvider.future);

          final weId = initial.exercises.first.workoutExercise.id;
          container.read(activeWorkoutProvider.notifier).addSet(weId);

          final newSet = container
              .read(activeWorkoutProvider)
              .value!
              .exercises
              .first
              .sets
              .first;
          expect(newSet.setType, SetType.working);
          expect(newSet.isCompleted, isFalse);
          expect(newSet.weight, 0);
          expect(newSet.reps, 0);
        },
      );

      test('only affects the targeted exercise', () async {
        final initial = makeState(exerciseCount: 2, setsPerExercise: 1);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        final firstWeId = initial.exercises.first.workoutExercise.id;
        container.read(activeWorkoutProvider.notifier).addSet(firstWeId);

        final result = container.read(activeWorkoutProvider).value!;
        expect(result.exercises.first.sets, hasLength(2));
        expect(result.exercises.last.sets, hasLength(1));
      });
    });

    // --------------------------------------------------------------- updateSet
    group('updateSet', () {
      test('updates weight on a specific set', () async {
        final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        final weId = initial.exercises.first.workoutExercise.id;
        final setId = initial.exercises.first.sets.first.id;
        container
            .read(activeWorkoutProvider.notifier)
            .updateSet(weId, setId, weight: 100.0);

        final updatedSet = container
            .read(activeWorkoutProvider)
            .value!
            .exercises
            .first
            .sets
            .first;
        expect(updatedSet.weight, 100.0);
      });

      test('updates reps on a specific set', () async {
        final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        final weId = initial.exercises.first.workoutExercise.id;
        final setId = initial.exercises.first.sets.first.id;
        container
            .read(activeWorkoutProvider.notifier)
            .updateSet(weId, setId, reps: 12);

        final updatedSet = container
            .read(activeWorkoutProvider)
            .value!
            .exercises
            .first
            .sets
            .first;
        expect(updatedSet.reps, 12);
      });

      test('updates setType on a specific set', () async {
        final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        final weId = initial.exercises.first.workoutExercise.id;
        final setId = initial.exercises.first.sets.first.id;
        container
            .read(activeWorkoutProvider.notifier)
            .updateSet(weId, setId, setType: SetType.warmup);

        final updatedSet = container
            .read(activeWorkoutProvider)
            .value!
            .exercises
            .first
            .sets
            .first;
        expect(updatedSet.setType, SetType.warmup);
      });

      test(
        'preserves unspecified fields when doing a partial update',
        () async {
          final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
          final container = makeContainer(initial);
          addTearDown(container.dispose);
          await container.read(activeWorkoutProvider.future);

          final weId = initial.exercises.first.workoutExercise.id;
          final originalSet = initial.exercises.first.sets.first;
          // Update only weight; reps should stay at their factory default.
          container
              .read(activeWorkoutProvider.notifier)
              .updateSet(weId, originalSet.id, weight: 80.0);

          final updatedSet = container
              .read(activeWorkoutProvider)
              .value!
              .exercises
              .first
              .sets
              .first;
          expect(updatedSet.weight, 80.0);
          expect(updatedSet.reps, originalSet.reps);
          expect(updatedSet.setType, originalSet.setType);
        },
      );

      test('does not affect other sets in the same exercise', () async {
        final initial = makeState(exerciseCount: 1, setsPerExercise: 3);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        final weId = initial.exercises.first.workoutExercise.id;
        final secondSetId = initial.exercises.first.sets[1].id;
        container
            .read(activeWorkoutProvider.notifier)
            .updateSet(weId, secondSetId, weight: 999.0);

        final sets = container
            .read(activeWorkoutProvider)
            .value!
            .exercises
            .first
            .sets;
        expect(sets[0].weight, isNot(999.0));
        expect(sets[1].weight, 999.0);
        expect(sets[2].weight, isNot(999.0));
      });
    });

    // ------------------------------------------------------------- completeSet
    group('completeSet', () {
      test('toggles isCompleted from false to true', () async {
        // Factory default has isCompleted: true, so use addSet to get a fresh one.
        final initial = makeState(exerciseCount: 1, setsPerExercise: 0);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        final weId = initial.exercises.first.workoutExercise.id;
        container.read(activeWorkoutProvider.notifier).addSet(weId);

        final addedSetId = container
            .read(activeWorkoutProvider)
            .value!
            .exercises
            .first
            .sets
            .first
            .id;
        expect(
          container
              .read(activeWorkoutProvider)
              .value!
              .exercises
              .first
              .sets
              .first
              .isCompleted,
          isFalse,
        );

        container
            .read(activeWorkoutProvider.notifier)
            .completeSet(weId, addedSetId);

        expect(
          container
              .read(activeWorkoutProvider)
              .value!
              .exercises
              .first
              .sets
              .first
              .isCompleted,
          isTrue,
        );
      });

      test('toggles isCompleted from true back to false', () async {
        final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
        // Factory creates sets with isCompleted: true.
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        final weId = initial.exercises.first.workoutExercise.id;
        final setId = initial.exercises.first.sets.first.id;

        container.read(activeWorkoutProvider.notifier).completeSet(weId, setId);

        expect(
          container
              .read(activeWorkoutProvider)
              .value!
              .exercises
              .first
              .sets
              .first
              .isCompleted,
          isFalse,
        );
      });

      test('only toggles the targeted set', () async {
        final initial = makeState(exerciseCount: 1, setsPerExercise: 2);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        final weId = initial.exercises.first.workoutExercise.id;
        final firstSetId = initial.exercises.first.sets.first.id;
        final secondSetInitialCompleted =
            initial.exercises.first.sets[1].isCompleted;

        container
            .read(activeWorkoutProvider.notifier)
            .completeSet(weId, firstSetId);

        final sets = container
            .read(activeWorkoutProvider)
            .value!
            .exercises
            .first
            .sets;
        expect(sets[1].isCompleted, secondSetInitialCompleted);
      });
    });

    // --------------------------------------------------------------- deleteSet
    group('deleteSet', () {
      test('removes the set from the exercise', () async {
        final initial = makeState(exerciseCount: 1, setsPerExercise: 3);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        final weId = initial.exercises.first.workoutExercise.id;
        final middleSetId = initial.exercises.first.sets[1].id;
        container
            .read(activeWorkoutProvider.notifier)
            .deleteSet(weId, middleSetId);

        final result = container.read(activeWorkoutProvider).value!;
        expect(result.exercises.first.sets, hasLength(2));
        expect(
          result.exercises.first.sets.any((s) => s.id == middleSetId),
          isFalse,
        );
      });

      test('renumbers remaining sets consecutively from 1', () async {
        final initial = makeState(exerciseCount: 1, setsPerExercise: 3);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        final weId = initial.exercises.first.workoutExercise.id;
        // Delete the first set; the remaining two should become 1 and 2.
        final firstSetId = initial.exercises.first.sets.first.id;
        container
            .read(activeWorkoutProvider.notifier)
            .deleteSet(weId, firstSetId);

        final remaining = container
            .read(activeWorkoutProvider)
            .value!
            .exercises
            .first
            .sets;
        expect(remaining[0].setNumber, 1);
        expect(remaining[1].setNumber, 2);
      });

      test('only affects the targeted exercise', () async {
        final initial = makeState(exerciseCount: 2, setsPerExercise: 2);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        final firstWeId = initial.exercises.first.workoutExercise.id;
        final setId = initial.exercises.first.sets.first.id;
        container
            .read(activeWorkoutProvider.notifier)
            .deleteSet(firstWeId, setId);

        final result = container.read(activeWorkoutProvider).value!;
        expect(result.exercises.first.sets, hasLength(1));
        expect(result.exercises.last.sets, hasLength(2));
      });

      test('results in empty sets list when last set is deleted', () async {
        final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        final weId = initial.exercises.first.workoutExercise.id;
        final setId = initial.exercises.first.sets.first.id;
        container.read(activeWorkoutProvider.notifier).deleteSet(weId, setId);

        expect(
          container.read(activeWorkoutProvider).value!.exercises.first.sets,
          isEmpty,
        );
      });
    });

    // ----------------------------------------------- Hive persistence (side effects)
    group('Hive persistence', () {
      test('saveActiveWorkout is called after addExercise', () async {
        final mockStorage = MockWorkoutLocalStorage();
        when(() => mockStorage.loadActiveWorkout()).thenReturn(makeState());
        when(
          () => mockStorage.saveActiveWorkout(any()),
        ).thenAnswer((_) async {});

        final container = ProviderContainer(
          overrides: [
            workoutRepositoryProvider.overrideWithValue(
              MockWorkoutRepository(),
            ),
            workoutLocalStorageProvider.overrideWithValue(mockStorage),
          ],
        );
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        container
            .read(activeWorkoutProvider.notifier)
            .addExercise(makeExercise());

        // Give the unawaited save a chance to run.
        await Future<void>.delayed(Duration.zero);
        verify(
          () => mockStorage.saveActiveWorkout(any()),
        ).called(greaterThan(0));
      });

      test('saveActiveWorkout is called after deleteSet', () async {
        final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
        final mockStorage = MockWorkoutLocalStorage();
        when(() => mockStorage.loadActiveWorkout()).thenReturn(initial);
        when(
          () => mockStorage.saveActiveWorkout(any()),
        ).thenAnswer((_) async {});

        final container = ProviderContainer(
          overrides: [
            workoutRepositoryProvider.overrideWithValue(
              MockWorkoutRepository(),
            ),
            workoutLocalStorageProvider.overrideWithValue(mockStorage),
          ],
        );
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        final weId = initial.exercises.first.workoutExercise.id;
        final setId = initial.exercises.first.sets.first.id;
        container.read(activeWorkoutProvider.notifier).deleteSet(weId, setId);

        await Future<void>.delayed(Duration.zero);
        verify(
          () => mockStorage.saveActiveWorkout(any()),
        ).called(greaterThan(0));
      });
    });
  });

  // ================================================================
  // Async network methods — startWorkout / finishWorkout / discardWorkout
  // ================================================================
  //
  // The `_userId` getter previously called Supabase.instance directly, making
  // it impossible to test without a real Supabase singleton. It has been
  // refactored to use `ref.read(authRepositoryProvider)`, which is overridable
  // in tests via ProviderContainer. All tests in this group use
  // `makeAsyncContainer`, which injects MockAuthRepository.

  group('ActiveWorkoutNotifier — startWorkout', () {
    test(
      'success: calls createActiveWorkout, saves to Hive, state is AsyncData',
      () async {
        final (:container, :mockRepo, :mockStorage, :mockAuth) =
            makeAsyncContainer(null);
        addTearDown(container.dispose);

        final createdWorkout = makeWorkout(id: 'workout-new');
        when(() => mockAuth.currentUser).thenReturn(fakeUser());
        when(
          () => mockRepo.createActiveWorkout(
            userId: any(named: 'userId'),
            name: any(named: 'name'),
          ),
        ).thenAnswer((_) async => createdWorkout);

        await container.read(activeWorkoutProvider.future);
        await container
            .read(activeWorkoutProvider.notifier)
            .startWorkout('Leg Day');

        final result = container.read(activeWorkoutProvider);
        expect(result, isA<AsyncData<ActiveWorkoutState?>>());
        expect(result.value, isNotNull);
        expect(result.value!.workout.id, 'workout-new');
        expect(result.value!.exercises, isEmpty);

        verify(
          () => mockRepo.createActiveWorkout(
            userId: 'user-test-001',
            name: 'Leg Day',
          ),
        ).called(1);

        // Give the unawaited Hive save a chance to run.
        await Future<void>.delayed(Duration.zero);
        verify(
          () => mockStorage.saveActiveWorkout(any()),
        ).called(greaterThan(0));
      },
    );

    test(
      'unauthenticated: state becomes AsyncError with AuthException',
      () async {
        final (:container, :mockRepo, :mockStorage, :mockAuth) =
            makeAsyncContainer(null);
        addTearDown(container.dispose);

        when(() => mockAuth.currentUser).thenReturn(null);

        await container.read(activeWorkoutProvider.future);
        await container
            .read(activeWorkoutProvider.notifier)
            .startWorkout('Push Day');

        final result = container.read(activeWorkoutProvider);
        expect(result, isA<AsyncError<ActiveWorkoutState?>>());
        verifyNever(
          () => mockRepo.createActiveWorkout(
            userId: any(named: 'userId'),
            name: any(named: 'name'),
          ),
        );
      },
    );

    test('repo error: state becomes AsyncError', () async {
      final (:container, :mockRepo, :mockStorage, :mockAuth) =
          makeAsyncContainer(null);
      addTearDown(container.dispose);

      when(() => mockAuth.currentUser).thenReturn(fakeUser());
      when(
        () => mockRepo.createActiveWorkout(
          userId: any(named: 'userId'),
          name: any(named: 'name'),
        ),
      ).thenThrow(Exception('Network failure'));

      await container.read(activeWorkoutProvider.future);
      await container
          .read(activeWorkoutProvider.notifier)
          .startWorkout('Push Day');

      expect(
        container.read(activeWorkoutProvider),
        isA<AsyncError<ActiveWorkoutState?>>(),
      );
    });
  });

  group('ActiveWorkoutNotifier — finishWorkout', () {
    test('success: calls saveWorkout with correct data, clears Hive, '
        'state is AsyncData(null)', () async {
      final initial = makeState(exerciseCount: 1, setsPerExercise: 2);
      final (:container, :mockRepo, :mockStorage, :mockAuth) =
          makeAsyncContainer(initial);
      addTearDown(container.dispose);

      final savedWorkout = makeWorkout(isActive: false);
      when(() => mockAuth.currentUser).thenReturn(fakeUser());
      when(
        () => mockRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
        ),
      ).thenAnswer((_) async => savedWorkout);
      when(() => mockStorage.clearActiveWorkout()).thenAnswer((_) async {});

      await container.read(activeWorkoutProvider.future);
      await container
          .read(activeWorkoutProvider.notifier)
          .finishWorkout(notes: 'Great session');

      final result = container.read(activeWorkoutProvider);
      expect(result, isA<AsyncData<ActiveWorkoutState?>>());
      expect(result.value, isNull);

      // Verify saveWorkout received the right shapes.
      final captured = verify(
        () => mockRepo.saveWorkout(
          workout: captureAny(named: 'workout'),
          exercises: captureAny(named: 'exercises'),
          sets: captureAny(named: 'sets'),
        ),
      ).captured;
      final capturedWorkout = captured[0] as Workout;
      expect(capturedWorkout.isActive, isFalse);
      expect(capturedWorkout.finishedAt, isNotNull);
      expect(capturedWorkout.notes, 'Great session');
      expect(capturedWorkout.durationSeconds, isNotNull);

      final capturedExercises = captured[1] as List;
      expect(capturedExercises, hasLength(1));

      final capturedSets = captured[2] as List;
      expect(capturedSets, hasLength(2));

      verify(() => mockStorage.clearActiveWorkout()).called(1);
    });

    test('success: invalidates exerciseProgressProvider family so chart '
        'refreshes after save (P1 review Important 1)', () async {
      // Regression for PR #??? reviewer finding: `exerciseProgressProvider`
      // is `keepAlive`-guarded, so without an explicit invalidate a user
      // who finishes a workout and re-opens the exercise detail sheet in
      // the same session sees stale chart data. Verify here that a keyed
      // read before `finishWorkout` triggers a second repo hit after the
      // save completes.
      final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
      final (:container, :mockRepo, :mockStorage, :mockAuth) =
          makeAsyncContainer(initial);
      addTearDown(container.dispose);

      when(() => mockAuth.currentUser).thenReturn(fakeUser());
      when(
        () => mockRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
        ),
      ).thenAnswer((_) async => makeWorkout(isActive: false));
      when(() => mockStorage.clearActiveWorkout()).thenAnswer((_) async {});
      when(
        () => mockRepo.getExerciseHistory(
          any(),
          userId: any(named: 'userId'),
          since: any(named: 'since'),
        ),
      ).thenAnswer((_) async => const []);

      // Prime the state and prime the chart provider for a specific
      // exercise — simulates a user viewing the chart before finishing
      // the workout.
      await container.read(activeWorkoutProvider.future);
      const key = ExerciseProgressKey(
        exerciseId: 'ex-1',
        window: TimeWindow.last90Days,
      );
      // Subscribe so `keepAlive` actually takes effect and the cached
      // value persists across the save.
      final sub = container.listen(exerciseProgressProvider(key), (_, _) {});
      addTearDown(sub.close);
      await container.read(exerciseProgressProvider(key).future);

      verify(
        () => mockRepo.getExerciseHistory(
          'ex-1',
          userId: any(named: 'userId'),
          since: any(named: 'since'),
        ),
      ).called(1);

      // Act: finish the workout successfully.
      await container.read(activeWorkoutProvider.notifier).finishWorkout();

      // Re-read the provider — if the notifier invalidated correctly,
      // the repo is hit a second time. Without the invalidate this would
      // fail (call count stays at 1).
      await container.read(exerciseProgressProvider(key).future);

      verify(
        () => mockRepo.getExerciseHistory(
          'ex-1',
          userId: any(named: 'userId'),
          since: any(named: 'since'),
        ),
      ).called(1);
    });

    test('success: invalidates rpgProgressProvider so the Saga tab refreshes '
        'after save (PR #113 review Blocker)', () async {
      // Regression for PR #113 reviewer finding (Stage 8 Blocker):
      // `save_workout` calls `record_set_xp` server-side in the same
      // transaction, so by the time finishWorkout() returns, lifetime_xp
      // and per-body-part rows are durable. Without an explicit
      // invalidate, `rpgProgressProvider` keeps the pre-save snapshot —
      // the character sheet shows lifetime_xp == 0 and the
      // first-set-awakens banner never disappears until app restart.
      //
      // Mirror the exerciseProgressProvider regression test pattern: subscribe
      // to rpgProgressProvider before the save, prime its repo calls, finish
      // the workout, then re-read the provider and assert the repo is hit a
      // second time.
      final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
      final mockRepo = MockWorkoutRepository();
      final mockStorage = MockWorkoutLocalStorage();
      final mockAuth = MockAuthRepository();
      final mockRpgRepo = MockRpgRepository();
      final mockPeakLoadsRepo = MockPeakLoadsRepository();

      when(() => mockStorage.loadActiveWorkout()).thenReturn(initial);
      when(() => mockStorage.saveActiveWorkout(any())).thenAnswer((_) async {});
      when(() => mockStorage.clearActiveWorkout()).thenAnswer((_) async {});
      when(() => mockAuth.currentUser).thenReturn(fakeUser());
      when(
        () => mockRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
        ),
      ).thenAnswer((_) async => makeWorkout(isActive: false));
      when(
        () => mockRpgRepo.getAllBodyPartProgress(),
      ).thenAnswer((_) async => const <BodyPartProgress>[]);
      when(
        () => mockRpgRepo.getCharacterState(),
      ).thenAnswer((_) async => CharacterState.empty);

      final container = ProviderContainer(
        overrides: [
          workoutRepositoryProvider.overrideWithValue(mockRepo),
          workoutLocalStorageProvider.overrideWithValue(mockStorage),
          authRepositoryProvider.overrideWithValue(mockAuth),
          analyticsRepositoryProvider.overrideWithValue(
            const _FakeAnalyticsRepository(),
          ),
          rpgRepositoryProvider.overrideWithValue(mockRpgRepo),
          peakLoadsRepositoryProvider.overrideWithValue(mockPeakLoadsRepo),
        ],
      );
      addTearDown(container.dispose);

      // Prime the active workout state and the rpg snapshot — simulates a
      // user who's seen their character sheet before the save.
      await container.read(activeWorkoutProvider.future);
      final sub = container.listen(rpgProgressProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(rpgProgressProvider.future);

      // Pre-save: each repo method is hit exactly once.
      verify(() => mockRpgRepo.getAllBodyPartProgress()).called(1);
      verify(() => mockRpgRepo.getCharacterState()).called(1);

      // Act: finish the workout successfully.
      await container.read(activeWorkoutProvider.notifier).finishWorkout();

      // Re-read the provider — if the notifier invalidated correctly,
      // the rpg repo is hit a second time. Without the invalidate this
      // would fail (call count stays at 1).
      await container.read(rpgProgressProvider.future);

      verify(() => mockRpgRepo.getAllBodyPartProgress()).called(1);
      verify(() => mockRpgRepo.getCharacterState()).called(1);
    });

    test('does nothing when state is null', () async {
      final (:container, :mockRepo, :mockStorage, :mockAuth) =
          makeAsyncContainer(null);
      addTearDown(container.dispose);

      when(() => mockAuth.currentUser).thenReturn(fakeUser());

      await container.read(activeWorkoutProvider.future);
      await container.read(activeWorkoutProvider.notifier).finishWorkout();

      // State remains null — no network call, no Hive clear.
      expect(container.read(activeWorkoutProvider).value, isNull);
      verifyNever(
        () => mockRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
        ),
      );
      verifyNever(() => mockStorage.clearActiveWorkout());
    });

    // Phase 14b: when saveWorkout fails the notifier enqueues offline and
    // still returns AsyncData(null) — the workout is considered locally finished.
    test(
      'offline path: saveWorkout fails → enqueues PendingSaveWorkout, '
      'savedOffline flag is true, state is AsyncData(null), Hive cleared',
      () async {
        final initial = makeState(exerciseCount: 1, setsPerExercise: 2);
        final bundle = makeOfflineContainer(initial);
        addTearDown(bundle.container.dispose);

        when(() => bundle.mockAuth.currentUser).thenReturn(fakeUser());
        when(
          () => bundle.mockRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).thenThrow(Exception('Network error'));
        // Stub getFinishedWorkoutCount so the fallback to cached count works.
        when(
          () => bundle.mockRepo.getFinishedWorkoutCount(any()),
        ).thenThrow(Exception('Offline'));
        when(() => bundle.mockRepo.getCachedWorkoutCount(any())).thenReturn(1);

        await bundle.container.read(activeWorkoutProvider.future);
        final finishResult = await bundle.container
            .read(activeWorkoutProvider.notifier)
            .finishWorkout();

        // State must be AsyncData(null) — workout is considered done locally.
        final result = bundle.container.read(activeWorkoutProvider);
        expect(result, isA<AsyncData<ActiveWorkoutState?>>());
        expect(result.value, isNull);

        // BUG-039: savedOffline is exposed via the explicit return record,
        // not as a notifier field — pin the new contract.
        expect(finishResult, isNotNull);
        expect(finishResult!.savedOffline, isTrue);

        // Hive must be cleared (local state flushed even on offline finish).
        verify(() => bundle.mockStorage.clearActiveWorkout()).called(1);

        // Exactly one PendingSaveWorkout must have been enqueued.
        expect(bundle.capturedNotifier.enqueued, hasLength(1));
        expect(
          bundle.capturedNotifier.enqueued.first,
          isA<PendingSaveWorkout>(),
        );
      },
    );

    test(
      'offline path: enqueued PendingSaveWorkout carries correct workout data',
      () async {
        final initial = makeState(exerciseCount: 1, setsPerExercise: 2);
        final bundle = makeOfflineContainer(initial);
        addTearDown(bundle.container.dispose);

        when(() => bundle.mockAuth.currentUser).thenReturn(fakeUser());
        when(
          () => bundle.mockRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).thenThrow(Exception('Network error'));
        when(
          () => bundle.mockRepo.getFinishedWorkoutCount(any()),
        ).thenThrow(Exception('Offline'));
        when(() => bundle.mockRepo.getCachedWorkoutCount(any())).thenReturn(1);

        await bundle.container.read(activeWorkoutProvider.future);
        await bundle.container
            .read(activeWorkoutProvider.notifier)
            .finishWorkout(notes: 'Offline session');

        final queued =
            bundle.capturedNotifier.enqueued.first as PendingSaveWorkout;
        // workout JSON must include the notes and mark it finished.
        expect(queued.workoutJson['notes'], 'Offline session');
        expect(queued.workoutJson['finished_at'], isNotNull);
        // exercisesJson and setsJson shapes must be present.
        expect(queued.exercisesJson, hasLength(1));
        expect(queued.setsJson, hasLength(2));
        // userId comes from the workout model built from the test factory
        // (user-001), NOT the auth user ID (user-test-001).
        expect(queued.userId, 'user-001');
        // retryCount starts at 0.
        expect(queued.retryCount, 0);
      },
    );

    // BUG-001 round-trip pin: the JSON map enqueued for offline replay must
    // deserialize cleanly through ExerciseSet.fromJson without throwing. The
    // production crash was a null-cast on `created_at` because the map
    // omitted that key — _$ExerciseSetFromJson does an unguarded
    // `DateTime.parse(json['created_at'] as String)`.
    test(
      'BUG-001: offline setsJson round-trips through ExerciseSet.fromJson',
      () async {
        final initial = makeState(exerciseCount: 1, setsPerExercise: 2);
        final bundle = makeOfflineContainer(initial);
        addTearDown(bundle.container.dispose);

        when(() => bundle.mockAuth.currentUser).thenReturn(fakeUser());
        when(
          () => bundle.mockRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).thenThrow(Exception('Network error'));
        when(
          () => bundle.mockRepo.getFinishedWorkoutCount(any()),
        ).thenThrow(Exception('Offline'));
        when(() => bundle.mockRepo.getCachedWorkoutCount(any())).thenReturn(1);

        await bundle.container.read(activeWorkoutProvider.future);
        await bundle.container
            .read(activeWorkoutProvider.notifier)
            .finishWorkout();

        final queued =
            bundle.capturedNotifier.enqueued.first as PendingSaveWorkout;

        // Round-trip every set through fromJson: this would throw the
        // production cast error before the BUG-001 fix added `created_at`.
        for (final json in queued.setsJson) {
          expect(json['created_at'], isNotNull);
          // No throw == pass — explicit asserts on a couple of fields too.
          final round = ExerciseSet.fromJson(json);
          expect(round.id, json['id']);
          expect(round.workoutExerciseId, json['workout_exercise_id']);
          expect(round.setType, isA<SetType>());
        }
      },
    );

    // BUG-002 wiring pin: when the workout is saved offline, the resulting
    // PendingUpsertRecords must declare its dependency on the parent
    // PendingSaveWorkout so the drain holds it back until the FK target
    // exists server-side. PR detection requires (a) a populated
    // `WorkoutExercise.exercise` field, (b) at least one completed working
    // set with a positive weight, and (c) an empty existingRecords map so
    // every set produces a fresh record.
    test(
      'BUG-002: offline upsertRecords carries dependsOn = [parent workout id]',
      () async {
        final exercise = Exercise.fromJson(
          TestExerciseFactory.create(
            id: 'exercise-1',
            name: 'Bench Press',
            equipmentType: 'barbell',
          ),
        );
        final we = WorkoutExercise(
          id: 'we-1',
          workoutId: 'workout-001',
          exerciseId: 'exercise-1',
          order: 0,
          exercise: exercise,
        );
        final sets = [
          ExerciseSet.fromJson(
            TestSetFactory.create(
              id: 'set-1',
              workoutExerciseId: 'we-1',
              setNumber: 1,
              weight: 100.0,
              reps: 8,
              isCompleted: true,
            ),
          ),
          ExerciseSet.fromJson(
            TestSetFactory.create(
              id: 'set-2',
              workoutExerciseId: 'we-1',
              setNumber: 2,
              weight: 110.0,
              reps: 6,
              isCompleted: true,
            ),
          ),
        ];
        final initial = ActiveWorkoutState(
          workout: Workout.fromJson(TestWorkoutFactory.create(isActive: true)),
          exercises: [ActiveWorkoutExercise(workoutExercise: we, sets: sets)],
        );

        final mockRepo = MockWorkoutRepository();
        final mockStorage = MockWorkoutLocalStorage();
        final mockAuth = MockAuthRepository();
        final mockCache = MockCacheService();
        final mockPRRepo = MockPRRepository();
        final capturedNotifier = _CapturingPendingSyncNotifier();

        when(() => mockStorage.loadActiveWorkout()).thenReturn(initial);
        when(
          () => mockStorage.saveActiveWorkout(any()),
        ).thenAnswer((_) async {});
        when(() => mockStorage.clearActiveWorkout()).thenAnswer((_) async {});
        when(() => mockAuth.currentUser).thenReturn(fakeUser());
        when(() => mockRepo.getCachedWorkoutCount(any())).thenReturn(5);
        when(
          () => mockCache.write(any(), any(), any()),
        ).thenAnswer((_) async {});

        // Offline path: saveWorkout throws so the workout enqueues offline.
        when(
          () => mockRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).thenThrow(Exception('Network error'));
        when(
          () => mockRepo.getFinishedWorkoutCount(any()),
        ).thenThrow(Exception('Offline'));

        // Empty cache → all sets are fresh PRs.
        when(
          () => mockCache.read<Map<String, List<PersonalRecord>>>(
            any(),
            any(),
            any(),
          ),
        ).thenReturn(<String, List<PersonalRecord>>{});

        final container = ProviderContainer(
          overrides: [
            workoutRepositoryProvider.overrideWithValue(mockRepo),
            workoutLocalStorageProvider.overrideWithValue(mockStorage),
            authRepositoryProvider.overrideWithValue(mockAuth),
            analyticsRepositoryProvider.overrideWithValue(
              const _FakeAnalyticsRepository(),
            ),
            pendingSyncProvider.overrideWith(() => capturedNotifier),
            cacheServiceProvider.overrideWithValue(mockCache),
            prRepositoryProvider.overrideWithValue(mockPRRepo),
            prDetectionServiceProvider.overrideWithValue(PRDetectionService()),
          ],
        );
        addTearDown(container.dispose);

        await container.read(activeWorkoutProvider.future);
        await container.read(activeWorkoutProvider.notifier).finishWorkout();

        // Both actions must be enqueued: the parent PendingSaveWorkout (the
        // offline-path fallback for the failed RPC) and the child
        // PendingUpsertRecords (the PR upsert).
        final saves = capturedNotifier.enqueued
            .whereType<PendingSaveWorkout>()
            .toList();
        final upserts = capturedNotifier.enqueued
            .whereType<PendingUpsertRecords>()
            .toList();
        expect(saves, hasLength(1));
        expect(upserts, hasLength(1));

        // The wiring under test: the upsert must list the parent workout
        // id in dependsOn so SyncService holds it back until the parent
        // commits server-side.
        final parentId = saves.single.id;
        expect(upserts.single.dependsOn, [parentId]);
      },
    );

    // BUG-003 wiring pin (notifier-level): when an offline-finished workout
    // references an exercise the user created offline (still queued as
    // PendingCreateExercise), the new PendingSaveWorkout must declare
    // `dependsOn: [createExerciseAction.id]`. SyncService's drain test
    // asserts that the gate behaves correctly given seeded `dependsOn`,
    // but doesn't cover the wiring — i.e. that the notifier actually
    // scans the queue and stamps the dependency. Without this pin a
    // refactor of `_enqueueOfflineWorkout` could silently drop the scan
    // and the SyncService test would still pass.
    test('BUG-003: offline saveWorkout carries dependsOn = [createExercise id] '
        'when an exercise is queued', () async {
      // Build a workout whose single exercise's id matches a queued
      // PendingCreateExercise stub. The notifier must scan the queue,
      // find the match, and stamp the dependency on the new save.
      const offlineExerciseId = 'ex-offline-123';
      final exercise = Exercise.fromJson(
        TestExerciseFactory.create(
          id: offlineExerciseId,
          name: 'Custom Bench',
          equipmentType: 'barbell',
        ),
      );
      final we = WorkoutExercise(
        id: 'we-1',
        workoutId: 'workout-001',
        exerciseId: offlineExerciseId,
        order: 0,
        exercise: exercise,
      );
      final sets = [
        ExerciseSet.fromJson(
          TestSetFactory.create(
            id: 'set-1',
            workoutExerciseId: 'we-1',
            setNumber: 1,
            weight: 100.0,
            reps: 8,
            isCompleted: true,
          ),
        ),
      ];
      final initial = ActiveWorkoutState(
        workout: Workout.fromJson(
          TestWorkoutFactory.create(id: 'workout-001', isActive: true),
        ),
        exercises: [ActiveWorkoutExercise(workoutExercise: we, sets: sets)],
      );

      final mockRepo = MockWorkoutRepository();
      final mockStorage = MockWorkoutLocalStorage();
      final mockAuth = MockAuthRepository();
      final capturedNotifier = _CapturingPendingSyncNotifier();

      // Pre-seed the queue with the PendingCreateExercise the workout
      // depends on. This mirrors the production sequence: user creates an
      // exercise offline (NetworkException → enqueue), then logs a
      // workout against it (saveWorkout throws → enqueue with dependsOn).
      capturedNotifier.enqueued.add(
        PendingAction.createExercise(
          id: 'create-ex-action-id',
          exerciseId: offlineExerciseId,
          userId: 'user-test-001',
          locale: 'en',
          name: 'Custom Bench',
          muscleGroup: 'chest',
          equipmentType: 'barbell',
          queuedAt: DateTime.utc(2026, 4, 17, 9, 0, 0),
        ),
      );

      when(() => mockStorage.loadActiveWorkout()).thenReturn(initial);
      when(() => mockStorage.saveActiveWorkout(any())).thenAnswer((_) async {});
      when(() => mockStorage.clearActiveWorkout()).thenAnswer((_) async {});
      when(() => mockAuth.currentUser).thenReturn(fakeUser());
      when(() => mockRepo.getCachedWorkoutCount(any())).thenReturn(5);

      // Offline path: saveWorkout throws so the workout enqueues offline.
      when(
        () => mockRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
        ),
      ).thenThrow(Exception('Network error'));
      when(
        () => mockRepo.getFinishedWorkoutCount(any()),
      ).thenThrow(Exception('Offline'));

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
      addTearDown(container.dispose);

      await container.read(activeWorkoutProvider.future);
      await container.read(activeWorkoutProvider.notifier).finishWorkout();

      // The newly-enqueued PendingSaveWorkout must declare its dependency
      // on the queued create action so the SyncService drain holds the
      // workout back until the exercise row commits server-side.
      final saves = capturedNotifier.enqueued
          .whereType<PendingSaveWorkout>()
          .toList();
      expect(saves, hasLength(1));
      expect(saves.single.dependsOn, ['create-ex-action-id']);
    });

    // BUG-003 negative pin: when no PendingCreateExercise references the
    // workout's exercise IDs, the new PendingSaveWorkout must NOT carry any
    // dependsOn entries. Spurious dependencies would hold the save back
    // forever waiting for a parent that doesn't exist.
    test('BUG-003: offline saveWorkout has empty dependsOn when no '
        'createExercise is queued', () async {
      final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
      final bundle = makeOfflineContainer(initial);
      addTearDown(bundle.container.dispose);

      when(() => bundle.mockAuth.currentUser).thenReturn(fakeUser());
      when(
        () => bundle.mockRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
        ),
      ).thenThrow(Exception('Network error'));
      when(
        () => bundle.mockRepo.getFinishedWorkoutCount(any()),
      ).thenThrow(Exception('Offline'));
      when(() => bundle.mockRepo.getCachedWorkoutCount(any())).thenReturn(5);

      await bundle.container.read(activeWorkoutProvider.future);
      await bundle.container
          .read(activeWorkoutProvider.notifier)
          .finishWorkout();

      final saves = bundle.capturedNotifier.enqueued
          .whereType<PendingSaveWorkout>()
          .toList();
      expect(saves, hasLength(1));
      expect(saves.single.dependsOn, isEmpty);
    });

    test(
      'offline path: incrementCachedWorkoutCount is called when saveWorkout fails',
      () async {
        final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
        final bundle = makeOfflineContainer(initial);
        addTearDown(bundle.container.dispose);

        when(() => bundle.mockAuth.currentUser).thenReturn(fakeUser());
        when(
          () => bundle.mockRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).thenThrow(Exception('Network error'));
        when(
          () => bundle.mockRepo.getFinishedWorkoutCount(any()),
        ).thenThrow(Exception('Offline'));
        when(() => bundle.mockRepo.getCachedWorkoutCount(any())).thenReturn(5);

        await bundle.container.read(activeWorkoutProvider.future);
        await bundle.container
            .read(activeWorkoutProvider.notifier)
            .finishWorkout();

        // userId comes from workout.userId (factory: 'user-001'), not auth user.
        verify(
          () => bundle.mockRepo.incrementCachedWorkoutCount('user-001'),
        ).called(1);
      },
    );

    test('savedOffline is false after a successful finish', () async {
      final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
      final bundle = makeOfflineContainer(initial);
      addTearDown(bundle.container.dispose);

      when(() => bundle.mockAuth.currentUser).thenReturn(fakeUser());
      when(
        () => bundle.mockRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
        ),
      ).thenAnswer((_) async => makeWorkout(isActive: false));

      await bundle.container.read(activeWorkoutProvider.future);
      final finishResult = await bundle.container
          .read(activeWorkoutProvider.notifier)
          .finishWorkout();

      // BUG-039: savedOffline is on the return record, not the notifier.
      expect(finishResult, isNotNull);
      expect(finishResult!.savedOffline, isFalse);
      // Nothing enqueued on success.
      expect(bundle.capturedNotifier.enqueued, isEmpty);
    });

    // BUG-039 contract pin: `savedOffline` must be returned via the
    // `FinishWorkoutResult` record, NOT exposed as a public field on the
    // notifier. Pin both arms (online + offline) at the API surface so any
    // future refactor that re-introduces a notifier-side field fails this
    // test.
    test(
      'BUG-039: savedOffline lives on FinishWorkoutResult, not the notifier',
      () async {
        final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
        final bundle = makeOfflineContainer(initial);
        addTearDown(bundle.container.dispose);

        when(() => bundle.mockAuth.currentUser).thenReturn(fakeUser());
        when(
          () => bundle.mockRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).thenThrow(Exception('Network error'));
        when(
          () => bundle.mockRepo.getFinishedWorkoutCount(any()),
        ).thenThrow(Exception('Offline'));
        when(() => bundle.mockRepo.getCachedWorkoutCount(any())).thenReturn(0);

        await bundle.container.read(activeWorkoutProvider.future);
        final finishResult = await bundle.container
            .read(activeWorkoutProvider.notifier)
            .finishWorkout();

        // Result record exists and carries the offline flag.
        expect(finishResult, isNotNull);
        expect(finishResult!.savedOffline, isTrue);

        // The notifier object itself must not expose a `savedOffline`
        // member — restoring unidirectional Riverpod data flow. We assert
        // this by reading the notifier through its concrete type and
        // confirming the dynamic dispatch returns the record's flag (the
        // *only* surface that should expose it).
        final notifier = bundle.container.read(activeWorkoutProvider.notifier);
        // Sanity: instance is the concrete notifier type (not a mock).
        expect(notifier, isA<ActiveWorkoutNotifier>());
        // Pin: any callsite trying `(notifier as dynamic).savedOffline`
        // must throw NoSuchMethodError — the notifier no longer carries
        // that field. Reading via dynamic dispatch is the only way to
        // assert the absence of a member at compile time without breaking
        // the test compile.
        expect(
          () => (notifier as dynamic).savedOffline,
          throwsNoSuchMethodError,
        );
      },
    );

    test('double-enqueue is prevented: same workout ID enqueued twice writes '
        'only one action (last-write-wins via identical ID key)', () async {
      // If finishWorkout is retried manually while a queue item already
      // exists, the notifier should not be able to create a second entry
      // with the same workout ID — the Hive-keyed enqueue uses the workout
      // ID as the key, so the second write silently overwrites the first.
      // We verify here that the capturing notifier receives two enqueue
      // calls, but only the last one matters (same ID).
      final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
      final bundle = makeOfflineContainer(initial);
      addTearDown(bundle.container.dispose);

      when(() => bundle.mockAuth.currentUser).thenReturn(fakeUser());
      when(
        () => bundle.mockRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
        ),
      ).thenThrow(Exception('Network error'));
      when(
        () => bundle.mockRepo.getFinishedWorkoutCount(any()),
      ).thenThrow(Exception('Offline'));
      when(() => bundle.mockRepo.getCachedWorkoutCount(any())).thenReturn(0);

      await bundle.container.read(activeWorkoutProvider.future);
      // First finish attempt — queues the item.
      await bundle.container
          .read(activeWorkoutProvider.notifier)
          .finishWorkout();

      // Only one item was queued.
      expect(bundle.capturedNotifier.enqueued, hasLength(1));
      final firstId =
          (bundle.capturedNotifier.enqueued.first as PendingSaveWorkout).id;

      // Confirm the enqueued workout ID matches the workout in state.
      expect(firstId, initial.workout.id);
    });

    test('PR1 — H7: offline weekly-plan markRoutineComplete enqueue carries '
        'dependsOn = [workout.id]', () async {
      // Audit H7: when finishWorkout fires the weekly-plan update against
      // a routine that is in this week's bucket, and the network call
      // throws, the fallback enqueue used to omit `dependsOn`. The
      // resulting `PendingMarkRoutineComplete` could drain BEFORE the
      // sibling `PendingSaveWorkout` committed — at which point the RPC
      // silently inserted an unknown UUID into `weekly_plans.routines`
      // (JSONB column with no FK) and the bucket displayed a phantom
      // completion that pointed at a workout id the server had never
      // seen.
      //
      // Fix: stamp `dependsOn: [workout.id]` so the FIFO drain holds the
      // weekly-plan update until the parent save commits. Same pattern
      // that BUG-002 already uses for offline PR upserts.
      const workoutId = 'workout-h7-001';
      const routineId = 'routine-h7-bench';

      // Build an active workout state pre-populated with the routineId
      // — the factory doesn't expose routineId, so construct it directly.
      final exercise = Exercise.fromJson(
        TestExerciseFactory.create(id: 'exercise-h7', equipmentType: 'barbell'),
      );
      final we = WorkoutExercise(
        id: 'we-h7',
        workoutId: workoutId,
        exerciseId: 'exercise-h7',
        order: 0,
        exercise: exercise,
      );
      final sets = [
        ExerciseSet.fromJson(
          TestSetFactory.create(
            id: 'set-h7',
            workoutExerciseId: 'we-h7',
            setNumber: 1,
            weight: 100.0,
            reps: 5,
            isCompleted: true,
          ),
        ),
      ];
      final initial = ActiveWorkoutState(
        workout: Workout.fromJson(
          TestWorkoutFactory.create(id: workoutId, isActive: true),
        ),
        exercises: [ActiveWorkoutExercise(workoutExercise: we, sets: sets)],
        routineId: routineId,
      );

      final mockRepo = MockWorkoutRepository();
      final mockStorage = MockWorkoutLocalStorage();
      final mockAuth = MockAuthRepository();
      final capturedNotifier = _CapturingPendingSyncNotifier();

      when(() => mockStorage.loadActiveWorkout()).thenReturn(initial);
      when(() => mockStorage.saveActiveWorkout(any())).thenAnswer((_) async {});
      when(() => mockStorage.clearActiveWorkout()).thenAnswer((_) async {});
      when(() => mockAuth.currentUser).thenReturn(fakeUser());
      // Save throws → PendingSaveWorkout enqueued; downstream
      // weekly-plan branch still runs because that catch is independent.
      when(
        () => mockRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
        ),
      ).thenThrow(Exception('Network error'));
      when(() => mockRepo.getCachedWorkoutCount(any())).thenReturn(1);

      // Pre-populate the weekly plan provider with a plan containing the
      // routine, then make markRoutineComplete throw so the offline
      // enqueue path runs.
      final plan = WeeklyPlan(
        id: 'plan-h7',
        userId: 'user-test-001',
        weekStart: DateTime.utc(2026, 5, 4),
        routines: const [BucketRoutine(routineId: routineId, order: 0)],
        createdAt: DateTime.utc(2026, 5, 4),
        updatedAt: DateTime.utc(2026, 5, 4),
      );
      final stubWeeklyNotifier = _StubWeeklyPlanNotifier(
        plan: plan,
        throwOnMark: true,
      );

      final container = ProviderContainer(
        overrides: [
          workoutRepositoryProvider.overrideWithValue(mockRepo),
          workoutLocalStorageProvider.overrideWithValue(mockStorage),
          authRepositoryProvider.overrideWithValue(mockAuth),
          analyticsRepositoryProvider.overrideWithValue(
            const _FakeAnalyticsRepository(),
          ),
          pendingSyncProvider.overrideWith(() => capturedNotifier),
          weeklyPlanProvider.overrideWith(() => stubWeeklyNotifier),
        ],
      );
      addTearDown(container.dispose);

      await container.read(activeWorkoutProvider.future);
      await container.read(activeWorkoutProvider.notifier).finishWorkout();

      // PendingSaveWorkout (parent) and PendingMarkRoutineComplete
      // (weekly-plan child) must both be enqueued.
      final marks = capturedNotifier.enqueued
          .whereType<PendingMarkRoutineComplete>()
          .toList();
      expect(marks, hasLength(1));
      expect(
        marks.single.dependsOn,
        [workoutId],
        reason:
            'The weekly-plan completion must wait for the parent save to '
            'commit, otherwise the RPC silently writes a phantom workout '
            'id into weekly_plans.routines (JSONB, no FK).',
      );
      expect(marks.single.routineId, routineId);
      expect(marks.single.workoutId, workoutId);
      expect(marks.single.planId, plan.id);
    });
  });

  group('ActiveWorkoutNotifier — discardWorkout', () {
    test(
      'success: calls discardWorkout, clears Hive, state is AsyncData(null)',
      () async {
        final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
        final (:container, :mockRepo, :mockStorage, :mockAuth) =
            makeAsyncContainer(initial);
        addTearDown(container.dispose);

        when(() => mockAuth.currentUser).thenReturn(fakeUser());
        when(
          () => mockRepo.discardWorkout(any(), userId: any(named: 'userId')),
        ).thenAnswer((_) async {});
        when(() => mockStorage.clearActiveWorkout()).thenAnswer((_) async {});

        await container.read(activeWorkoutProvider.future);
        await container.read(activeWorkoutProvider.notifier).discardWorkout();

        final result = container.read(activeWorkoutProvider);
        expect(result, isA<AsyncData<ActiveWorkoutState?>>());
        expect(result.value, isNull);

        verify(
          () => mockRepo.discardWorkout(
            initial.workout.id,
            userId: 'user-test-001',
          ),
        ).called(1);
        verify(() => mockStorage.clearActiveWorkout()).called(1);
      },
    );

    test('does nothing when state is null', () async {
      final (:container, :mockRepo, :mockStorage, :mockAuth) =
          makeAsyncContainer(null);
      addTearDown(container.dispose);

      when(() => mockAuth.currentUser).thenReturn(fakeUser());

      await container.read(activeWorkoutProvider.future);
      await container.read(activeWorkoutProvider.notifier).discardWorkout();

      // State remains null — no network call, no Hive clear.
      expect(container.read(activeWorkoutProvider).value, isNull);
      verifyNever(
        () => mockRepo.discardWorkout(any(), userId: any(named: 'userId')),
      );
      verifyNever(() => mockStorage.clearActiveWorkout());
    });

    test('repo error: state becomes AsyncError AND Hive is left intact so the '
        'user can retry (PR1 — C2)', () async {
      // Audit C2: previously discardWorkout cleared Hive first, then
      // attempted the server delete — a network failure left the user
      // with an empty Hive box and a server-side workout still alive.
      // Reload (or any later read) would surface the stale server row
      // and the user would believe they had lost data.
      //
      // New contract: server first; Hive is cleared ONLY on success.
      // Terminal error path keeps Hive populated so the workout
      // re-hydrates on the next read and the user can retry the discard.
      final initial = makeState(exerciseCount: 0, setsPerExercise: 0);
      final (:container, :mockRepo, :mockStorage, :mockAuth) =
          makeAsyncContainer(initial);
      addTearDown(container.dispose);

      when(() => mockAuth.currentUser).thenReturn(fakeUser());
      when(() => mockStorage.clearActiveWorkout()).thenAnswer((_) async {});
      when(
        () => mockRepo.discardWorkout(any(), userId: any(named: 'userId')),
      ).thenThrow(Exception('Delete failed'));

      await container.read(activeWorkoutProvider.future);
      await container.read(activeWorkoutProvider.notifier).discardWorkout();

      expect(
        container.read(activeWorkoutProvider),
        isA<AsyncError<ActiveWorkoutState?>>(),
      );
      // Server call must have been attempted exactly once.
      verify(
        () => mockRepo.discardWorkout(any(), userId: any(named: 'userId')),
      ).called(1);
      // Hive must NOT have been cleared — the workout is still recoverable.
      verifyNever(() => mockStorage.clearActiveWorkout());
    });

    test(
      'success: server delete fires BEFORE Hive clear (PR1 — C2 ordering)',
      () async {
        // Pin the order of side-effects so a future refactor can't silently
        // re-introduce the C2 bug. The repo call is gated on a Completer the
        // test controls — at the moment the repo is invoked we assert that
        // Hive has not yet been touched. Then we let the repo complete and
        // assert Hive is cleared exactly once.
        final initial = makeState(exerciseCount: 0, setsPerExercise: 0);
        final (:container, :mockRepo, :mockStorage, :mockAuth) =
            makeAsyncContainer(initial);
        addTearDown(container.dispose);

        when(() => mockAuth.currentUser).thenReturn(fakeUser());
        final discardCompleter = Completer<void>();
        when(
          () => mockRepo.discardWorkout(any(), userId: any(named: 'userId')),
        ).thenAnswer((_) => discardCompleter.future);
        when(() => mockStorage.clearActiveWorkout()).thenAnswer((_) async {});

        await container.read(activeWorkoutProvider.future);

        // Kick off the discard — it will hang on the completer.
        final future = container
            .read(activeWorkoutProvider.notifier)
            .discardWorkout();

        // Yield so the guard advances into the repo call.
        await Future<void>.delayed(Duration.zero);

        // Repo call has been issued, Hive has NOT been cleared yet.
        verify(
          () => mockRepo.discardWorkout(any(), userId: any(named: 'userId')),
        ).called(1);
        verifyNever(() => mockStorage.clearActiveWorkout());

        // Resolve the server delete; Hive clear must run after.
        discardCompleter.complete();
        await future;

        verify(() => mockStorage.clearActiveWorkout()).called(1);
      },
    );

    test('PR1 review — Fix B: cancel AFTER discardWorkout server call returns '
        'success — commit wins, state ends AsyncData(null), Hive cleared, no '
        'restoration', () async {
      // Reviewer finding (mirrors C1 saveCommitted): the discard cancel
      // guard at `discardWorkout:782` has no `discardCommitted` equivalent.
      // If `cancelLoading()` fires AFTER `_repo.discardWorkout()` succeeds
      // but BEFORE `_localStorage.clearActiveWorkout()` runs, the cancel
      // check intercepts `state = result`, restores the workout visually,
      // but the server row is already soft-deleted. The user now sees a
      // "recoverable" workout that the server considers gone.
      //
      // Fix: introduce `var discardCommitted = false;` flipped immediately
      // after the server call returns success. The post-guard cancel check
      // becomes `if (_cancelRequested && !discardCommitted)`. When cancel
      // fires post-commit, fall through to `state = result` (which is
      // `AsyncData(null)`) and let the screen redirect home as it would
      // on a normal discard.
      final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
      final (:container, :mockRepo, :mockStorage, :mockAuth) =
          makeAsyncContainer(initial);
      addTearDown(container.dispose);

      when(() => mockAuth.currentUser).thenReturn(fakeUser());

      // Server call resolves on demand so we can interleave the cancel.
      final discardCompleter = Completer<void>();
      when(
        () => mockRepo.discardWorkout(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) => discardCompleter.future);

      // Hive clear hangs until we let it through — this gives us a window
      // between "server committed" and "Hive cleared" to fire the cancel.
      final clearCompleter = Completer<void>();
      when(
        () => mockStorage.clearActiveWorkout(),
      ).thenAnswer((_) => clearCompleter.future);

      await container.read(activeWorkoutProvider.future);

      // 1. Kick off discard — guard advances into the server call.
      final discardFuture = container
          .read(activeWorkoutProvider.notifier)
          .discardWorkout();

      await Future<void>.delayed(Duration.zero);
      expect(container.read(activeWorkoutProvider).isLoading, isTrue);

      // 2. Server call SUCCEEDS — discardCommitted flips true inside the
      //    guard. Hive clear is still pending.
      discardCompleter.complete();
      await Future<void>.delayed(Duration.zero);

      // 3. Cancel fires NOW — post-commit. The cancel guard must be
      //    skipped because the server delete already happened: the
      //    workout is gone server-side and restoring locally would be
      //    a "phantom recovery" pointing at a deleted row.
      container.read(activeWorkoutProvider.notifier).cancelLoading();

      // 4. Let Hive clear complete and the guard resolve.
      clearCompleter.complete();
      await discardFuture;
      await Future<void>.delayed(Duration.zero);

      final afterComplete = container.read(activeWorkoutProvider);
      expect(afterComplete, isA<AsyncData<ActiveWorkoutState?>>());
      expect(
        afterComplete.value,
        isNull,
        reason:
            'Cancel after a successful discard must NOT restore the '
            'workout — the server row is already soft-deleted, and the '
            'screen relies on this null transition to redirect home.',
      );
      // Hive must have been cleared as part of the normal discard path.
      verify(() => mockStorage.clearActiveWorkout()).called(1);
    });

    test(
      'unauthenticated: state becomes AsyncError and no analytics event fires',
      () async {
        // Regression for PR #46 reviewer finding 1: when `_userId` throws from
        // inside `discardWorkout`, the AuthException must be caught by the
        // AsyncValue.guard (state -> AsyncError) instead of propagating
        // uncaught. Analytics must NOT fire because the discard did not
        // actually happen.
        final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
        final mockRepo = MockWorkoutRepository();
        final mockStorage = MockWorkoutLocalStorage();
        final mockAuth = MockAuthRepository();
        final analytics = _RecordingAnalyticsRepository();

        when(() => mockStorage.loadActiveWorkout()).thenReturn(initial);
        when(
          () => mockStorage.saveActiveWorkout(any()),
        ).thenAnswer((_) async {});
        when(() => mockStorage.clearActiveWorkout()).thenAnswer((_) async {});
        // Session missing — _userId will throw AuthException.
        when(() => mockAuth.currentUser).thenReturn(null);

        final container = ProviderContainer(
          overrides: [
            workoutRepositoryProvider.overrideWithValue(mockRepo),
            workoutLocalStorageProvider.overrideWithValue(mockStorage),
            authRepositoryProvider.overrideWithValue(mockAuth),
            analyticsRepositoryProvider.overrideWithValue(analytics),
          ],
        );
        addTearDown(container.dispose);

        await container.read(activeWorkoutProvider.future);
        // Must NOT throw — the guard catches the AuthException.
        await container.read(activeWorkoutProvider.notifier).discardWorkout();

        // Drain any queued microtasks (unawaited analytics calls).
        await Future<void>.microtask(() {});

        expect(
          container.read(activeWorkoutProvider),
          isA<AsyncError<ActiveWorkoutState?>>(),
        );
        // The repo call never ran because _userId threw first.
        verifyNever(
          () => mockRepo.discardWorkout(any(), userId: any(named: 'userId')),
        );
        // Analytics must be empty — tracking is inside the guard and only
        // runs on successful discard.
        expect(analytics.events, isEmpty);
      },
    );
  });

  // ================================================================
  // Step 5c — copyLastSet, fillRemainingSets, reorderExercise, swapExercise
  // ================================================================

  group('ActiveWorkoutNotifier — copyLastSet', () {
    test('copies weight and reps from the previous set', () async {
      final initial = makeState(exerciseCount: 1, setsPerExercise: 2);
      final container = makeContainer(initial);
      addTearDown(container.dispose);
      await container.read(activeWorkoutProvider.future);

      final weId = initial.exercises.first.workoutExercise.id;
      // Prime the first set with known values via updateSet so we can assert.
      final firstSetId = initial.exercises.first.sets[0].id;
      final secondSetId = initial.exercises.first.sets[1].id;

      container
          .read(activeWorkoutProvider.notifier)
          .updateSet(weId, firstSetId, weight: 80.0, reps: 8);

      container
          .read(activeWorkoutProvider.notifier)
          .copyLastSet(weId, secondSetId);

      final sets = container
          .read(activeWorkoutProvider)
          .value!
          .exercises
          .first
          .sets;
      expect(sets[1].weight, 80.0);
      expect(sets[1].reps, 8);
    });

    test('is a no-op when target set is the first set (index 0)', () async {
      final initial = makeState(exerciseCount: 1, setsPerExercise: 2);
      final container = makeContainer(initial);
      addTearDown(container.dispose);
      await container.read(activeWorkoutProvider.future);

      final weId = initial.exercises.first.workoutExercise.id;
      final firstSetId = initial.exercises.first.sets[0].id;
      final originalWeight = initial.exercises.first.sets[0].weight;
      final originalReps = initial.exercises.first.sets[0].reps;

      container
          .read(activeWorkoutProvider.notifier)
          .copyLastSet(weId, firstSetId);

      final sets = container
          .read(activeWorkoutProvider)
          .value!
          .exercises
          .first
          .sets;
      // First set should be unchanged because there is no previous set.
      expect(sets[0].weight, originalWeight);
      expect(sets[0].reps, originalReps);
    });

    test('is a no-op when setId does not exist', () async {
      final initial = makeState(exerciseCount: 1, setsPerExercise: 2);
      final container = makeContainer(initial);
      addTearDown(container.dispose);
      await container.read(activeWorkoutProvider.future);

      final weId = initial.exercises.first.workoutExercise.id;
      final before = container
          .read(activeWorkoutProvider)
          .value!
          .exercises
          .first
          .sets;

      container
          .read(activeWorkoutProvider.notifier)
          .copyLastSet(weId, 'nonexistent-set-id');

      final after = container
          .read(activeWorkoutProvider)
          .value!
          .exercises
          .first
          .sets;
      // Sets are unchanged.
      for (var i = 0; i < before.length; i++) {
        expect(after[i].weight, before[i].weight);
        expect(after[i].reps, before[i].reps);
      }
    });

    test('only modifies weight and reps, not setType or isCompleted', () async {
      final initial = makeState(exerciseCount: 1, setsPerExercise: 2);
      final container = makeContainer(initial);
      addTearDown(container.dispose);
      await container.read(activeWorkoutProvider.future);

      final weId = initial.exercises.first.workoutExercise.id;
      final secondSetId = initial.exercises.first.sets[1].id;
      final originalSetType = initial.exercises.first.sets[1].setType;
      final originalIsCompleted = initial.exercises.first.sets[1].isCompleted;

      container
          .read(activeWorkoutProvider.notifier)
          .copyLastSet(weId, secondSetId);

      final second = container
          .read(activeWorkoutProvider)
          .value!
          .exercises
          .first
          .sets[1];
      expect(second.setType, originalSetType);
      expect(second.isCompleted, originalIsCompleted);
    });
  });

  group('ActiveWorkoutNotifier — fillRemainingSets', () {
    test('fills incomplete sets after the last completed set', () async {
      // Build: 3 sets where set 1 is completed (factory default), sets 2 & 3
      // are added fresh (isCompleted: false).
      final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
      final container = makeContainer(initial);
      addTearDown(container.dispose);
      await container.read(activeWorkoutProvider.future);

      final weId = initial.exercises.first.workoutExercise.id;

      // Give the completed set known weight/reps.
      final completedSetId = initial.exercises.first.sets[0].id;
      container
          .read(activeWorkoutProvider.notifier)
          .updateSet(weId, completedSetId, weight: 100.0, reps: 5);

      // Add two more sets (isCompleted: false by default from addSet).
      container.read(activeWorkoutProvider.notifier).addSet(weId);
      container.read(activeWorkoutProvider.notifier).addSet(weId);

      container.read(activeWorkoutProvider.notifier).fillRemainingSets(weId);

      final sets = container
          .read(activeWorkoutProvider)
          .value!
          .exercises
          .first
          .sets;
      expect(sets[1].weight, 100.0);
      expect(sets[1].reps, 5);
      expect(sets[1].isCompleted, isTrue);
      expect(sets[2].weight, 100.0);
      expect(sets[2].reps, 5);
      expect(sets[2].isCompleted, isTrue);
    });

    test('is a no-op when no sets are completed', () async {
      // Start with an empty exercise, add two sets (both isCompleted: false).
      final initial = makeState(exerciseCount: 1, setsPerExercise: 0);
      final container = makeContainer(initial);
      addTearDown(container.dispose);
      await container.read(activeWorkoutProvider.future);

      final weId = initial.exercises.first.workoutExercise.id;
      container.read(activeWorkoutProvider.notifier).addSet(weId);
      container.read(activeWorkoutProvider.notifier).addSet(weId);

      final before = container
          .read(activeWorkoutProvider)
          .value!
          .exercises
          .first
          .sets;

      container.read(activeWorkoutProvider.notifier).fillRemainingSets(weId);

      final after = container
          .read(activeWorkoutProvider)
          .value!
          .exercises
          .first
          .sets;
      for (var i = 0; i < before.length; i++) {
        expect(after[i].weight, before[i].weight);
        expect(after[i].reps, before[i].reps);
      }
    });

    test('does not modify already-completed sets', () async {
      // Two completed sets followed by one incomplete set.
      final initial = makeState(exerciseCount: 1, setsPerExercise: 2);
      final container = makeContainer(initial);
      addTearDown(container.dispose);
      await container.read(activeWorkoutProvider.future);

      final weId = initial.exercises.first.workoutExercise.id;
      // Give each completed set distinct weight so we can tell them apart.
      container
          .read(activeWorkoutProvider.notifier)
          .updateSet(weId, initial.exercises.first.sets[0].id, weight: 50.0);
      container
          .read(activeWorkoutProvider.notifier)
          .updateSet(weId, initial.exercises.first.sets[1].id, weight: 70.0);

      // Add one incomplete set.
      container.read(activeWorkoutProvider.notifier).addSet(weId);

      container.read(activeWorkoutProvider.notifier).fillRemainingSets(weId);

      final sets = container
          .read(activeWorkoutProvider)
          .value!
          .exercises
          .first
          .sets;
      // Completed sets must retain their own weights.
      expect(sets[0].weight, 50.0);
      expect(sets[1].weight, 70.0);
    });

    test('does not fill incomplete sets before the last completed set', () async {
      // set 1: completed, set 2: incomplete, set 3: completed
      // fillRemainingSets should NOT fill set 2 (setNumber < lastCompleted)
      final initial = makeState(exerciseCount: 1, setsPerExercise: 3);
      final container = makeContainer(initial);
      addTearDown(container.dispose);
      await container.read(activeWorkoutProvider.future);

      final weId = initial.exercises.first.workoutExercise.id;
      final sets = initial.exercises.first.sets;

      // Set 1: completed with weight 50
      container
          .read(activeWorkoutProvider.notifier)
          .updateSet(weId, sets[0].id, weight: 50.0);

      // Set 2: mark incomplete (toggle off)
      container
          .read(activeWorkoutProvider.notifier)
          .completeSet(weId, sets[1].id);
      // sets from factory start isCompleted: true, so toggle makes it false

      // Set 3: completed with weight 80 (remains completed from factory)
      container
          .read(activeWorkoutProvider.notifier)
          .updateSet(weId, sets[2].id, weight: 80.0);

      container.read(activeWorkoutProvider.notifier).fillRemainingSets(weId);

      final result = container
          .read(activeWorkoutProvider)
          .value!
          .exercises
          .first
          .sets;
      // Set 2 should NOT be filled — its setNumber (2) < lastCompleted setNumber (3)
      expect(result[1].weight, isNot(80.0));
      // Set 2's weight should remain whatever it was before (factory default 60.0)
      expect(result[1].weight, 60.0);
      // Set 2 must remain incomplete — if the setNumber guard is removed, this
      // assertion catches the regression.
      expect(result[1].isCompleted, isFalse);
    });
  });

  group('ActiveWorkoutNotifier — reorderExercise', () {
    test(
      'moves an exercise up (direction -1) and swaps order fields',
      () async {
        final initial = makeState(exerciseCount: 3, setsPerExercise: 0);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        // Move the second exercise (index 1) up to index 0.
        final secondWeId = initial.exercises[1].workoutExercise.id;
        container
            .read(activeWorkoutProvider.notifier)
            .reorderExercise(secondWeId, -1);

        final exercises = container
            .read(activeWorkoutProvider)
            .value!
            .exercises;
        expect(exercises[0].workoutExercise.id, secondWeId);
        expect(exercises[0].workoutExercise.order, 0);
        expect(exercises[1].workoutExercise.order, 1);
      },
    );

    test(
      'moves an exercise down (direction +1) and swaps order fields',
      () async {
        final initial = makeState(exerciseCount: 3, setsPerExercise: 0);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        // Move the second exercise (index 1) down to index 2.
        final secondWeId = initial.exercises[1].workoutExercise.id;
        container
            .read(activeWorkoutProvider.notifier)
            .reorderExercise(secondWeId, 1);

        final exercises = container
            .read(activeWorkoutProvider)
            .value!
            .exercises;
        expect(exercises[2].workoutExercise.id, secondWeId);
        expect(exercises[2].workoutExercise.order, 2);
        expect(exercises[1].workoutExercise.order, 1);
      },
    );

    test(
      'is a no-op when first exercise is moved up (at upper bound)',
      () async {
        final initial = makeState(exerciseCount: 2, setsPerExercise: 0);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        final firstWeId = initial.exercises[0].workoutExercise.id;
        container
            .read(activeWorkoutProvider.notifier)
            .reorderExercise(firstWeId, -1);

        final exercises = container
            .read(activeWorkoutProvider)
            .value!
            .exercises;
        // Order must be unchanged.
        expect(exercises[0].workoutExercise.id, firstWeId);
      },
    );

    test(
      'is a no-op when last exercise is moved down (at lower bound)',
      () async {
        final initial = makeState(exerciseCount: 2, setsPerExercise: 0);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        final lastWeId = initial.exercises.last.workoutExercise.id;
        container
            .read(activeWorkoutProvider.notifier)
            .reorderExercise(lastWeId, 1);

        final exercises = container
            .read(activeWorkoutProvider)
            .value!
            .exercises;
        expect(exercises.last.workoutExercise.id, lastWeId);
      },
    );

    test('preserves sets on both swapped exercises', () async {
      final initial = makeState(exerciseCount: 2, setsPerExercise: 3);
      final container = makeContainer(initial);
      addTearDown(container.dispose);
      await container.read(activeWorkoutProvider.future);

      final firstWeId = initial.exercises[0].workoutExercise.id;
      final secondWeId = initial.exercises[1].workoutExercise.id;

      container
          .read(activeWorkoutProvider.notifier)
          .reorderExercise(firstWeId, 1);

      final exercises = container.read(activeWorkoutProvider).value!.exercises;
      // After swap: first slot holds what was the second exercise.
      expect(exercises[0].workoutExercise.id, secondWeId);
      expect(exercises[0].sets, hasLength(3));
      // Second slot holds what was the first exercise.
      expect(exercises[1].workoutExercise.id, firstWeId);
      expect(exercises[1].sets, hasLength(3));
    });
  });

  // ---------------------------------------------------------- propagateWeight
  //
  // Fix 2 — "follow the leader while still in formation". When the user
  // dials in working weight on set 1 (e.g. 0 → 20kg), subsequent
  // not-yet-completed sets that match the OLD weight should follow.
  // Customized sets (different from the leader's old weight) drop out of
  // formation; completed sets are immutable.
  //
  // Contract requirements:
  //   * leader set's weight is updated by this method (callers should NOT
  //     also call updateSet — that would double-emit).
  //   * single atomic state emission for the whole exercise mutation.
  //   * weight only — `reps` is sourced from routine prescription and must
  //     never propagate.
  //   * sets BEFORE the leader are untouched (we only walk forward).
  group('ActiveWorkoutNotifier — propagateWeight', () {
    /// Builds a state with one exercise containing N incomplete working sets
    /// at the given starting weight. Used to drive the propagation tests.
    ActiveWorkoutState buildIncompleteState({
      required int setCount,
      required double weight,
      int reps = 10,
    }) {
      final json = TestActiveWorkoutStateFactory.create(
        workout: TestWorkoutFactory.create(isActive: true),
        exercises: [
          {
            'workout_exercise': TestWorkoutExerciseFactory.create(
              id: 'we-001',
              exerciseId: 'exercise-001',
              order: 1,
            ),
            'sets': List.generate(setCount, (i) {
              return TestSetFactory.create(
                id: 'set-${i + 1}',
                workoutExerciseId: 'we-001',
                setNumber: i + 1,
                weight: weight,
                reps: reps,
                isCompleted: false,
              );
            }),
          },
        ],
      );
      return ActiveWorkoutState.fromJson(json);
    }

    test(
      'happy path: 3 sets all at 0kg, leader → 20kg, all 3 follow',
      () async {
        final initial = buildIncompleteState(setCount: 3, weight: 0);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        final weId = initial.exercises.first.workoutExercise.id;
        final leaderId = initial.exercises.first.sets.first.id;

        await container
            .read(activeWorkoutProvider.notifier)
            .propagateWeight(weId, leaderId, 0, 20);

        final sets = container
            .read(activeWorkoutProvider)
            .value!
            .exercises
            .first
            .sets;
        expect(sets[0].weight, 20.0, reason: 'leader set updated');
        expect(sets[1].weight, 20.0, reason: 'follower 1 follows');
        expect(sets[2].weight, 20.0, reason: 'follower 2 follows');
      },
    );

    test('customized follower (different weight) stops propagation', () async {
      final initial = buildIncompleteState(setCount: 3, weight: 0);
      // Customize set 2 to 22.5kg before propagating.
      final customized = initial.copyWith(
        exercises: [
          initial.exercises.first.copyWith(
            sets: [
              initial.exercises.first.sets[0],
              initial.exercises.first.sets[1].copyWith(weight: 22.5),
              initial.exercises.first.sets[2],
            ],
          ),
        ],
      );
      final container = makeContainer(customized);
      addTearDown(container.dispose);
      await container.read(activeWorkoutProvider.future);

      final weId = customized.exercises.first.workoutExercise.id;
      final leaderId = customized.exercises.first.sets.first.id;

      await container
          .read(activeWorkoutProvider.notifier)
          .propagateWeight(weId, leaderId, 0, 20);

      final sets = container
          .read(activeWorkoutProvider)
          .value!
          .exercises
          .first
          .sets;
      expect(sets[0].weight, 20.0, reason: 'leader updated');
      expect(
        sets[1].weight,
        22.5,
        reason: 'customized set 2 stays at its custom value',
      );
      expect(
        sets[2].weight,
        0.0,
        reason: 'set 3 does NOT follow because set 2 dropped out of formation',
      );
    });

    test('completed follower stops propagation (immutable)', () async {
      final initial = buildIncompleteState(setCount: 3, weight: 0);
      // Mark set 2 as completed at 0kg.
      final withCompletedSecond = initial.copyWith(
        exercises: [
          initial.exercises.first.copyWith(
            sets: [
              initial.exercises.first.sets[0],
              initial.exercises.first.sets[1].copyWith(isCompleted: true),
              initial.exercises.first.sets[2],
            ],
          ),
        ],
      );
      final container = makeContainer(withCompletedSecond);
      addTearDown(container.dispose);
      await container.read(activeWorkoutProvider.future);

      final weId = withCompletedSecond.exercises.first.workoutExercise.id;
      final leaderId = withCompletedSecond.exercises.first.sets.first.id;

      await container
          .read(activeWorkoutProvider.notifier)
          .propagateWeight(weId, leaderId, 0, 20);

      final sets = container
          .read(activeWorkoutProvider)
          .value!
          .exercises
          .first
          .sets;
      expect(sets[0].weight, 20.0);
      expect(
        sets[1].weight,
        0.0,
        reason: 'completed sets are immutable — never retroactively rewritten',
      );
      expect(sets[1].isCompleted, isTrue);
      // Set 3: contract says completed sets stop propagation; subsequent sets
      // are not retroactively followed when a completed set is reached.
      expect(
        sets[2].weight,
        0.0,
        reason: 'completed set short-circuits the walk forward',
      );
    });

    test('reps remain unchanged — weight-only propagation', () async {
      final initial = buildIncompleteState(setCount: 3, weight: 0, reps: 8);
      final container = makeContainer(initial);
      addTearDown(container.dispose);
      await container.read(activeWorkoutProvider.future);

      final weId = initial.exercises.first.workoutExercise.id;
      final leaderId = initial.exercises.first.sets.first.id;

      await container
          .read(activeWorkoutProvider.notifier)
          .propagateWeight(weId, leaderId, 0, 20);

      final sets = container
          .read(activeWorkoutProvider)
          .value!
          .exercises
          .first
          .sets;
      for (final s in sets) {
        expect(s.reps, 8, reason: 'reps must not propagate');
      }
    });

    test('sets BEFORE the leader are untouched', () async {
      final initial = buildIncompleteState(setCount: 3, weight: 0);
      final container = makeContainer(initial);
      addTearDown(container.dispose);
      await container.read(activeWorkoutProvider.future);

      final weId = initial.exercises.first.workoutExercise.id;
      // Leader is set 2 (middle).
      final leaderId = initial.exercises.first.sets[1].id;

      await container
          .read(activeWorkoutProvider.notifier)
          .propagateWeight(weId, leaderId, 0, 20);

      final sets = container
          .read(activeWorkoutProvider)
          .value!
          .exercises
          .first
          .sets;
      expect(sets[0].weight, 0.0, reason: 'set BEFORE leader not propagated');
      expect(sets[1].weight, 20.0, reason: 'leader updated');
      expect(sets[2].weight, 20.0, reason: 'set AFTER leader follows');
    });

    test('emits exactly ONE state update for the whole propagation', () async {
      final initial = buildIncompleteState(setCount: 3, weight: 0);
      final container = makeContainer(initial);
      addTearDown(container.dispose);
      await container.read(activeWorkoutProvider.future);

      // Spy on state updates by listening to the provider. The initial
      // listener fires once with the seeded state (skip that). Each
      // subsequent emission counts.
      final emittedStates = <ActiveWorkoutState>[];
      final removeListener = container.listen(activeWorkoutProvider, (
        previous,
        next,
      ) {
        final v = next.value;
        if (v != null) emittedStates.add(v);
      });
      addTearDown(removeListener.close);

      final weId = initial.exercises.first.workoutExercise.id;
      final leaderId = initial.exercises.first.sets.first.id;

      await container
          .read(activeWorkoutProvider.notifier)
          .propagateWeight(weId, leaderId, 0, 20);

      // Exactly one new emission for the propagation (the listener does NOT
      // fire on the initial seed because we attach AFTER the future
      // resolved).
      expect(
        emittedStates,
        hasLength(1),
        reason:
            'propagateWeight must emit a single AsyncData; multiple emissions '
            'cause N sequential rebuilds of every set row.',
      );
      expect(emittedStates.single.exercises.first.sets[2].weight, 20.0);
    });

    test('does nothing when state is null', () async {
      final container = makeContainer(null);
      addTearDown(container.dispose);

      // Should not throw.
      await container
          .read(activeWorkoutProvider.notifier)
          .propagateWeight('we-x', 'set-x', 0, 20);

      expect(container.read(activeWorkoutProvider).value, isNull);
    });

    test(
      'no-op when leader id is unknown — exercise state unchanged',
      () async {
        final initial = buildIncompleteState(setCount: 3, weight: 5);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        final weId = initial.exercises.first.workoutExercise.id;

        await container
            .read(activeWorkoutProvider.notifier)
            .propagateWeight(weId, 'unknown-set-id', 5, 20);

        final sets = container
            .read(activeWorkoutProvider)
            .value!
            .exercises
            .first
            .sets;
        for (final s in sets) {
          expect(s.weight, 5.0, reason: 'no leader found → no propagation');
        }
      },
    );
  });

  group('ActiveWorkoutNotifier — swapExercise', () {
    test(
      'replaces exerciseId and exercise reference while keeping sets',
      () async {
        final initial = makeState(exerciseCount: 1, setsPerExercise: 2);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        final weId = initial.exercises.first.workoutExercise.id;
        final newExercise = makeExercise(id: 'exercise-new', name: 'Deadlift');

        container
            .read(activeWorkoutProvider.notifier)
            .swapExercise(weId, newExercise);

        final result = container.read(activeWorkoutProvider).value!;
        final updated = result.exercises.first;
        expect(updated.workoutExercise.exerciseId, 'exercise-new');
        expect(updated.workoutExercise.exercise?.name, 'Deadlift');
        // Sets must survive the swap.
        expect(updated.sets, hasLength(2));
      },
    );

    test('is a no-op when workoutExerciseId does not exist', () async {
      final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
      final container = makeContainer(initial);
      addTearDown(container.dispose);
      await container.read(activeWorkoutProvider.future);

      final originalExerciseId =
          initial.exercises.first.workoutExercise.exerciseId;

      container
          .read(activeWorkoutProvider.notifier)
          .swapExercise('nonexistent-we-id', makeExercise(id: 'exercise-new'));

      final result = container.read(activeWorkoutProvider).value!;
      expect(
        result.exercises.first.workoutExercise.exerciseId,
        originalExerciseId,
      );
    });
  });

  // ----------------------------------------------- startWorkout auto-name
  group('ActiveWorkoutNotifier — startWorkout auto-name', () {
    test('auto-generates a date-based name when no arg is provided', () async {
      // **Family 6 follow-up:** `_generateWorkoutName` now reads
      // `localeProvider`, which in production reads from Hive. In unit
      // tests Hive isn't initialised, so we override `localeProvider`
      // with a StubLocaleNotifier. Locale-specific contracts are pinned
      // in `active_workout_notifier_workout_name_test.dart`; this test
      // only pins that the en path still produces a date-suffixed name.
      final (:container, :mockRepo, :mockStorage, :mockAuth) =
          makeAsyncContainer(null, locale: const Locale('en'));
      addTearDown(container.dispose);

      final createdWorkout = makeWorkout(id: 'workout-auto');
      when(() => mockAuth.currentUser).thenReturn(fakeUser());
      when(
        () => mockRepo.createActiveWorkout(
          userId: any(named: 'userId'),
          name: any(named: 'name'),
        ),
      ).thenAnswer((_) async => createdWorkout);

      await container.read(activeWorkoutProvider.future);
      await container.read(activeWorkoutProvider.notifier).startWorkout();

      final captured = verify(
        () => mockRepo.createActiveWorkout(
          userId: any(named: 'userId'),
          name: captureAny(named: 'name'),
        ),
      ).captured;
      final name = captured.first as String;
      // e.g. "Workout — Wed Apr 2"
      expect(name, startsWith('Workout \u2014 '));
      expect(name.length, greaterThan('Workout \u2014 '.length));
    });

    test('uses provided name when arg is given', () async {
      final (:container, :mockRepo, :mockStorage, :mockAuth) =
          makeAsyncContainer(null);
      addTearDown(container.dispose);

      final createdWorkout = makeWorkout(id: 'workout-named');
      when(() => mockAuth.currentUser).thenReturn(fakeUser());
      when(
        () => mockRepo.createActiveWorkout(
          userId: any(named: 'userId'),
          name: any(named: 'name'),
        ),
      ).thenAnswer((_) async => createdWorkout);

      await container.read(activeWorkoutProvider.future);
      await container
          .read(activeWorkoutProvider.notifier)
          .startWorkout('Push Day');

      verify(
        () => mockRepo.createActiveWorkout(
          userId: any(named: 'userId'),
          name: 'Push Day',
        ),
      ).called(1);
    });
  });

  // ----------------------------------------------- renameWorkout
  group('ActiveWorkoutNotifier — renameWorkout', () {
    test('updates the workout name in state', () async {
      final initial = makeState();
      final container = makeContainer(initial);
      addTearDown(container.dispose);
      await container.read(activeWorkoutProvider.future);

      container.read(activeWorkoutProvider.notifier).renameWorkout('New Name');

      final result = container.read(activeWorkoutProvider).value!;
      expect(result.workout.name, 'New Name');
    });

    test('persists to Hive after rename', () async {
      final initial = makeState();
      final mockStorage = MockWorkoutLocalStorage();
      when(() => mockStorage.loadActiveWorkout()).thenReturn(initial);
      when(() => mockStorage.saveActiveWorkout(any())).thenAnswer((_) async {});

      final container = ProviderContainer(
        overrides: [
          workoutRepositoryProvider.overrideWithValue(MockWorkoutRepository()),
          workoutLocalStorageProvider.overrideWithValue(mockStorage),
        ],
      );
      addTearDown(container.dispose);
      await container.read(activeWorkoutProvider.future);

      container.read(activeWorkoutProvider.notifier).renameWorkout('Leg Day');

      await Future<void>.delayed(Duration.zero);
      verify(() => mockStorage.saveActiveWorkout(any())).called(greaterThan(0));
    });

    test('does nothing when state is null', () {
      final container = makeContainer(null);
      addTearDown(container.dispose);

      // Should not throw.
      container.read(activeWorkoutProvider.notifier).renameWorkout('Name');

      expect(container.read(activeWorkoutProvider).value, isNull);
    });
  });

  // --------------------------------------------------------- incompleteSetsCount
  group('incompleteSetsCount', () {
    test('returns 0 when state is null (no active workout)', () async {
      final container = makeContainer(null);
      addTearDown(container.dispose);
      await container.read(activeWorkoutProvider.future);

      expect(
        container.read(activeWorkoutProvider.notifier).incompleteSetsCount,
        0,
      );
    });

    test('returns 0 when there are no exercises', () async {
      final container = makeContainer(makeState());
      addTearDown(container.dispose);
      await container.read(activeWorkoutProvider.future);

      expect(
        container.read(activeWorkoutProvider.notifier).incompleteSetsCount,
        0,
      );
    });

    test('returns 0 when all sets are completed', () async {
      // Factory default creates sets with isCompleted: true.
      final container = makeContainer(
        makeState(exerciseCount: 2, setsPerExercise: 3),
      );
      addTearDown(container.dispose);
      await container.read(activeWorkoutProvider.future);

      expect(
        container.read(activeWorkoutProvider.notifier).incompleteSetsCount,
        0,
      );
    });

    test('returns correct count of incomplete sets across exercises', () async {
      final initial = makeState(exerciseCount: 2, setsPerExercise: 0);
      final container = makeContainer(initial);
      addTearDown(container.dispose);
      await container.read(activeWorkoutProvider.future);

      final notifier = container.read(activeWorkoutProvider.notifier);

      // Add sets via addSet — they start incomplete.
      final we1Id = initial.exercises[0].workoutExercise.id;
      final we2Id = initial.exercises[1].workoutExercise.id;

      notifier.addSet(we1Id); // incomplete
      notifier.addSet(we1Id); // incomplete
      notifier.addSet(we2Id); // incomplete

      expect(notifier.incompleteSetsCount, 3);
    });

    test('excludes completed sets from the count', () async {
      final initial = makeState(exerciseCount: 1, setsPerExercise: 0);
      final container = makeContainer(initial);
      addTearDown(container.dispose);
      await container.read(activeWorkoutProvider.future);

      final notifier = container.read(activeWorkoutProvider.notifier);
      final weId = initial.exercises.first.workoutExercise.id;

      notifier.addSet(weId); // incomplete
      notifier.addSet(weId); // incomplete

      // Complete the first set.
      final setId = container
          .read(activeWorkoutProvider)
          .value!
          .exercises
          .first
          .sets
          .first
          .id;
      notifier.completeSet(weId, setId);

      expect(notifier.incompleteSetsCount, 1);
    });
  });

  // ----------------------------------------------------------------- addSet with defaults
  group('ActiveWorkoutNotifier — addSet with pre-fill defaults', () {
    test('new set uses defaultWeight and defaultReps when provided', () async {
      final initial = makeState(exerciseCount: 1, setsPerExercise: 0);
      final container = makeContainer(initial);
      addTearDown(container.dispose);
      await container.read(activeWorkoutProvider.future);

      final weId = initial.exercises.first.workoutExercise.id;
      container
          .read(activeWorkoutProvider.notifier)
          .addSet(weId, defaultWeight: 80.0, defaultReps: 6);

      final newSet = container
          .read(activeWorkoutProvider)
          .value!
          .exercises
          .first
          .sets
          .first;
      expect(newSet.weight, 80.0);
      expect(newSet.reps, 6);
    });

    test(
      'new set weight defaults to 0 when defaultWeight is not provided',
      () async {
        final initial = makeState(exerciseCount: 1, setsPerExercise: 0);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        final weId = initial.exercises.first.workoutExercise.id;
        container.read(activeWorkoutProvider.notifier).addSet(weId);

        final newSet = container
            .read(activeWorkoutProvider)
            .value!
            .exercises
            .first
            .sets
            .first;
        expect(newSet.weight, 0);
        expect(newSet.reps, 0);
      },
    );

    test(
      'new set uses only defaultWeight when defaultReps is omitted',
      () async {
        final initial = makeState(exerciseCount: 1, setsPerExercise: 0);
        final container = makeContainer(initial);
        addTearDown(container.dispose);
        await container.read(activeWorkoutProvider.future);

        final weId = initial.exercises.first.workoutExercise.id;
        container
            .read(activeWorkoutProvider.notifier)
            .addSet(weId, defaultWeight: 60.0);

        final newSet = container
            .read(activeWorkoutProvider)
            .value!
            .exercises
            .first
            .sets
            .first;
        expect(newSet.weight, 60.0);
        expect(newSet.reps, 0);
      },
    );
  });

  // ================================================================
  // Analytics event source values — PR 5 observability
  //
  // _trackWorkoutEvent is fire-and-forget (unawaited). We drain the
  // microtask queue with Future.microtask so the recording repo
  // captures the event before we assert.
  // ================================================================

  group('ActiveWorkoutNotifier — analytics source values', () {
    /// Helper that creates a container whose analytics repo records events.
    ({
      ProviderContainer container,
      MockWorkoutRepository mockRepo,
      MockWorkoutLocalStorage mockStorage,
      MockAuthRepository mockAuth,
      _RecordingAnalyticsRepository analytics,
    })
    makeRecordingContainer(ActiveWorkoutState? initialState) {
      final mockRepo = MockWorkoutRepository();
      final mockStorage = MockWorkoutLocalStorage();
      final mockAuth = MockAuthRepository();
      final analytics = _RecordingAnalyticsRepository();

      when(() => mockStorage.loadActiveWorkout()).thenReturn(initialState);
      when(() => mockStorage.saveActiveWorkout(any())).thenAnswer((_) async {});

      final container = ProviderContainer(
        overrides: [
          workoutRepositoryProvider.overrideWithValue(mockRepo),
          workoutLocalStorageProvider.overrideWithValue(mockStorage),
          authRepositoryProvider.overrideWithValue(mockAuth),
          analyticsRepositoryProvider.overrideWithValue(analytics),
        ],
      );
      return (
        container: container,
        mockRepo: mockRepo,
        mockStorage: mockStorage,
        mockAuth: mockAuth,
        analytics: analytics,
      );
    }

    test('startWorkout fires workout_started with source="empty"', () async {
      final bundle = makeRecordingContainer(null);
      addTearDown(bundle.container.dispose);

      when(() => bundle.mockAuth.currentUser).thenReturn(fakeUser());
      when(
        () => bundle.mockRepo.createActiveWorkout(
          userId: any(named: 'userId'),
          name: any(named: 'name'),
        ),
      ).thenAnswer((_) async => makeWorkout(id: 'workout-new'));

      await bundle.container.read(activeWorkoutProvider.future);
      await bundle.container
          .read(activeWorkoutProvider.notifier)
          .startWorkout('Leg Day');

      // Let the unawaited analytics call resolve.
      await Future<void>.microtask(() {});

      expect(bundle.analytics.events, hasLength(1));
      expect(bundle.analytics.events.first.name, 'workout_started');
      expect(bundle.analytics.events.first.props['source'], 'empty');
      expect(bundle.analytics.events.first.props['routine_id'], isNull);
    });

    test(
      'discardWorkout fires workout_discarded with source="empty" when no routineId',
      () async {
        // Use an initial state with no routineId (plain empty workout).
        final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
        // Confirm the factory produces a state without a routineId.
        expect(initial.routineId, isNull);

        final bundle = makeRecordingContainer(initial);
        addTearDown(bundle.container.dispose);

        when(() => bundle.mockAuth.currentUser).thenReturn(fakeUser());
        when(
          () => bundle.mockRepo.discardWorkout(
            any(),
            userId: any(named: 'userId'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => bundle.mockStorage.clearActiveWorkout(),
        ).thenAnswer((_) async {});

        await bundle.container.read(activeWorkoutProvider.future);
        await bundle.container
            .read(activeWorkoutProvider.notifier)
            .discardWorkout();

        await Future<void>.microtask(() {});

        expect(bundle.analytics.events, hasLength(1));
        expect(bundle.analytics.events.first.name, 'workout_discarded');
        expect(bundle.analytics.events.first.props['source'], 'empty');
      },
    );
  });

  // ================================================================
  // Concurrency guards — C1/C2 stability fixes
  // ================================================================

  group('ActiveWorkoutNotifier — finishWorkout concurrency guard', () {
    test(
      'second concurrent finishWorkout call returns null immediately',
      () async {
        final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
        final (:container, :mockRepo, :mockStorage, :mockAuth) =
            makeAsyncContainer(initial);
        addTearDown(container.dispose);

        when(() => mockAuth.currentUser).thenReturn(fakeUser());
        // Use a completer so we can control when the repo call completes.
        final completer = Completer<Workout>();
        when(
          () => mockRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).thenAnswer((_) => completer.future);
        when(() => mockStorage.clearActiveWorkout()).thenAnswer((_) async {});

        await container.read(activeWorkoutProvider.future);

        // Fire two concurrent finishWorkout calls.
        final first = container
            .read(activeWorkoutProvider.notifier)
            .finishWorkout(notes: 'test');
        final second = container
            .read(activeWorkoutProvider.notifier)
            .finishWorkout(notes: 'test');

        // Second call should return null immediately (guarded).
        final secondResult = await second;
        expect(secondResult, isNull);

        // Complete the first call.
        completer.complete(makeWorkout(isActive: false));
        await first;

        // saveWorkout should have been called exactly once.
        verify(
          () => mockRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).called(1);
      },
    );
  });

  group('ActiveWorkoutNotifier — discardWorkout concurrency guard', () {
    test('second concurrent discardWorkout call is ignored', () async {
      final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
      final (:container, :mockRepo, :mockStorage, :mockAuth) =
          makeAsyncContainer(initial);
      addTearDown(container.dispose);

      when(() => mockAuth.currentUser).thenReturn(fakeUser());
      final completer = Completer<void>();
      when(
        () => mockRepo.discardWorkout(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) => completer.future);
      when(() => mockStorage.clearActiveWorkout()).thenAnswer((_) async {});

      await container.read(activeWorkoutProvider.future);

      // Fire two concurrent discardWorkout calls.
      final first = container
          .read(activeWorkoutProvider.notifier)
          .discardWorkout();
      final second = container
          .read(activeWorkoutProvider.notifier)
          .discardWorkout();

      // Second call completes immediately (guarded).
      await second;

      // Complete the first call.
      completer.complete();
      await first;

      // discardWorkout should have been called exactly once.
      verify(
        () => mockRepo.discardWorkout(any(), userId: any(named: 'userId')),
      ).called(1);
    });
  });

  group('ActiveWorkoutNotifier — cancelLoading', () {
    test('restores last valid state and resets guards', () async {
      final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
      final (:container, :mockRepo, :mockStorage, :mockAuth) =
          makeAsyncContainer(initial);
      addTearDown(container.dispose);

      when(() => mockAuth.currentUser).thenReturn(fakeUser());
      // Never-completing future simulates a stalled network request.
      when(
        () => mockRepo.discardWorkout(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) => Completer<void>().future);
      when(() => mockStorage.clearActiveWorkout()).thenAnswer((_) async {});

      await container.read(activeWorkoutProvider.future);

      // Start a discard that will stall.
      unawaited(
        container.read(activeWorkoutProvider.notifier).discardWorkout(),
      );

      // Give the async guard time to set loading state.
      await Future<void>.delayed(Duration.zero);

      // State should be loading.
      expect(container.read(activeWorkoutProvider).isLoading, isTrue);

      // Cancel loading.
      container.read(activeWorkoutProvider.notifier).cancelLoading();

      // State should be restored to the previous valid state.
      final restored = container.read(activeWorkoutProvider);
      expect(restored, isA<AsyncData<ActiveWorkoutState?>>());
      expect(restored.value, isNotNull);
      expect(restored.value!.workout.id, initial.workout.id);

      // Guards should be reset — a second discard should proceed.
      // (We just verify it doesn't immediately return.)
      when(
        () => mockRepo.discardWorkout(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) async {});
      await container.read(activeWorkoutProvider.notifier).discardWorkout();
      verify(
        () => mockRepo.discardWorkout(any(), userId: any(named: 'userId')),
      ).called(greaterThan(0));
    });

    test('PR1 — C1: cancel BEFORE saveWorkout returns AND save then fails — '
        'state stays restored (cancel wins pre-commit)', () async {
      // Pre-commit cancel semantic: when cancelLoading() runs while the
      // network save is in-flight AND the save subsequently throws (so
      // nothing committed server-side), the user's local state must be
      // preserved exactly as cancelLoading() restored it. The guard's
      // AsyncError result must NOT overwrite the restored AsyncData.
      final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
      final (:container, :mockRepo, :mockStorage, :mockAuth) =
          makeAsyncContainer(initial);
      addTearDown(container.dispose);

      when(() => mockAuth.currentUser).thenReturn(fakeUser());

      final saveCompleter = Completer<Workout>();
      when(
        () => mockRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
        ),
      ).thenAnswer((_) => saveCompleter.future);
      when(() => mockStorage.clearActiveWorkout()).thenAnswer((_) async {});

      await container.read(activeWorkoutProvider.future);

      // 1. Start finishWorkout (hangs on the completer).
      final finishFuture = container
          .read(activeWorkoutProvider.notifier)
          .finishWorkout(notes: 'test');

      await Future<void>.delayed(Duration.zero);
      expect(container.read(activeWorkoutProvider).isLoading, isTrue);

      // 2. Cancel loading — state restores to the prior workout.
      container.read(activeWorkoutProvider.notifier).cancelLoading();
      final afterCancel = container.read(activeWorkoutProvider);
      expect(afterCancel, isA<AsyncData<ActiveWorkoutState?>>());
      expect(afterCancel.value!.workout.id, initial.workout.id);

      // 3. Save then FAILS terminally (HTTP 403 → terminal in
      // SyncErrorClassifier) — saveCommitted stays false, so the
      // cancel-after-guard branch is taken and state isn't clobbered.
      saveCompleter.completeError(
        const app.DatabaseException('rls denied', code: '403'),
      );
      await finishFuture;
      await Future<void>.delayed(Duration.zero);

      final afterComplete = container.read(activeWorkoutProvider);
      expect(afterComplete, isA<AsyncData<ActiveWorkoutState?>>());
      expect(afterComplete.value, isNotNull);
      expect(afterComplete.value!.workout.id, initial.workout.id);
    });

    test('PR1 — C1: cancel AFTER saveWorkout returns success — commit wins, '
        'state ends AsyncData(null)', () async {
      // Audit C1 semantic: once save committed server-side, cancel is a
      // no-op. The user's tap to cancel cannot reverse a committed save.
      // The finish flows through normally — state lands AsyncData(null)
      // and the screen falls through to /home navigation. This is the
      // only safe behavior: a save that already wrote sets + xp_events
      // server-side cannot be made to "un-happen" client-side.
      final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
      final (:container, :mockRepo, :mockStorage, :mockAuth) =
          makeAsyncContainer(initial);
      addTearDown(container.dispose);

      when(() => mockAuth.currentUser).thenReturn(fakeUser());

      final saveCompleter = Completer<Workout>();
      when(
        () => mockRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
        ),
      ).thenAnswer((_) => saveCompleter.future);
      when(() => mockStorage.clearActiveWorkout()).thenAnswer((_) async {});

      await container.read(activeWorkoutProvider.future);

      final finishFuture = container
          .read(activeWorkoutProvider.notifier)
          .finishWorkout(notes: 'test');

      await Future<void>.delayed(Duration.zero);
      expect(container.read(activeWorkoutProvider).isLoading, isTrue);

      // Cancel during save — restores state momentarily.
      container.read(activeWorkoutProvider.notifier).cancelLoading();
      expect(
        container.read(activeWorkoutProvider).value!.workout.id,
        initial.workout.id,
      );

      // Save then SUCCEEDS — saveCommitted flips true, so the
      // cancel-after-guard branch is skipped and state lands AsyncData(null).
      saveCompleter.complete(makeWorkout(isActive: false));
      final result = await finishFuture;
      await Future<void>.delayed(Duration.zero);

      // Result record must be returned (not null) so the coordinator
      // plays celebration + navigates as it would on a normal finish.
      expect(result, isNotNull);
      expect(result!.savedOffline, isFalse);

      final afterComplete = container.read(activeWorkoutProvider);
      expect(afterComplete, isA<AsyncData<ActiveWorkoutState?>>());
      expect(
        afterComplete.value,
        isNull,
        reason:
            'Cancel after a successful save must NOT block the state from '
            'reaching null — the screen relies on this transition to '
            'navigate to /home and the celebration overlay needs the '
            'finish to settle.',
      );
      // Hive was cleared as part of the normal finish path.
      verify(() => mockStorage.clearActiveWorkout()).called(1);
    });

    test('PR1 review — Fix B: cancel BEFORE discardWorkout server call returns '
        'AND the server then FAILS — state stays restored (cancel wins '
        'pre-commit, discard analogue of C1 pre-commit-fail)', () async {
      // Pre-commit cancel semantic for discard: when cancelLoading() runs
      // while the server delete is in-flight AND the delete subsequently
      // throws (so nothing committed server-side), the user's local
      // workout must be preserved exactly as cancelLoading() restored it.
      // The guard's AsyncError result must NOT overwrite the restored
      // AsyncData. Symmetric to the C1 pre-commit-fail test for finish.
      //
      // Pre-Fix-B this test asserted that ANY in-flight cancel preserved
      // state, even when the server eventually succeeded — which produced
      // a "phantom recovery" of a workout the server had already
      // soft-deleted. Fix B narrowed the contract: cancel only wins when
      // the server delete did NOT commit. The success path is covered by
      // the dedicated Fix B post-commit test in the discardWorkout group.
      final initial = makeState(exerciseCount: 1, setsPerExercise: 1);
      final (:container, :mockRepo, :mockStorage, :mockAuth) =
          makeAsyncContainer(initial);
      addTearDown(container.dispose);

      when(() => mockAuth.currentUser).thenReturn(fakeUser());

      final discardCompleter = Completer<void>();
      when(
        () => mockRepo.discardWorkout(any(), userId: any(named: 'userId')),
      ).thenAnswer((_) => discardCompleter.future);
      when(() => mockStorage.clearActiveWorkout()).thenAnswer((_) async {});

      await container.read(activeWorkoutProvider.future);

      // 1. Start discardWorkout (don't await).
      final discardFuture = container
          .read(activeWorkoutProvider.notifier)
          .discardWorkout();

      await Future<void>.delayed(Duration.zero);
      expect(container.read(activeWorkoutProvider).isLoading, isTrue);

      // 2. Cancel loading — restores state to the prior workout.
      container.read(activeWorkoutProvider.notifier).cancelLoading();
      final afterCancel = container.read(activeWorkoutProvider);
      expect(afterCancel, isA<AsyncData<ActiveWorkoutState?>>());
      expect(afterCancel.value, isNotNull);
      expect(afterCancel.value!.workout.id, initial.workout.id);

      // 3. Server delete then FAILS — discardCommitted stays false, so
      //    the cancel-after-guard branch is taken and state isn't
      //    clobbered. Hive must NOT have been cleared either (C2 ordering).
      discardCompleter.completeError(
        const app.DatabaseException('rls denied', code: '403'),
      );
      await discardFuture;
      await Future<void>.delayed(Duration.zero);

      // 4. State must STILL be restored, not AsyncError or AsyncData(null).
      final afterComplete = container.read(activeWorkoutProvider);
      expect(afterComplete, isA<AsyncData<ActiveWorkoutState?>>());
      expect(afterComplete.value, isNotNull);
      expect(afterComplete.value!.workout.id, initial.workout.id);
      verifyNever(() => mockStorage.clearActiveWorkout());
    });

    test('PR1 — C4: cancelLoading during startWorkout (no prior state) emits '
        'AsyncData(null) so the screen falls through to /home', () async {
      // Audit C4: when the user taps Cancel during the very first
      // start-workout (no prior valid state to restore), the overlay used
      // to be a dead-end — `cancelLoading()` did nothing because the
      // `_lastValidState != null` guard skipped the state assignment.
      // The notifier remained in AsyncLoading forever, the screen kept
      // showing the spinner, and the `displayState == null &&
      // !asyncState.isLoading` redirect at active_workout_screen.dart:68
      // never fired.
      //
      // Fix: cancelLoading() emits `AsyncData(null)` so the screen's
      // postFrameCallback navigates back to /home.
      //
      // Repro: drive the notifier into AsyncLoading via a stalled
      // startWorkout, then cancel.
      final (:container, :mockRepo, :mockStorage, :mockAuth) =
          makeAsyncContainer(null, locale: const Locale('en'));
      addTearDown(container.dispose);

      when(() => mockAuth.currentUser).thenReturn(fakeUser());
      // Never-completing future — simulates a stalled network on first start.
      when(
        () => mockRepo.createActiveWorkout(
          userId: any(named: 'userId'),
          name: any(named: 'name'),
        ),
      ).thenAnswer((_) => Completer<Workout>().future);

      await container.read(activeWorkoutProvider.future);

      // Kick off start — it hangs in AsyncLoading.
      unawaited(container.read(activeWorkoutProvider.notifier).startWorkout());
      await Future<void>.delayed(Duration.zero);
      expect(container.read(activeWorkoutProvider).isLoading, isTrue);

      // Cancel — must settle into AsyncData(null), not stay in AsyncLoading.
      container.read(activeWorkoutProvider.notifier).cancelLoading();

      final result = container.read(activeWorkoutProvider);
      expect(
        result,
        isA<AsyncData<ActiveWorkoutState?>>(),
        reason:
            'cancelLoading must settle the state so the screen redirect '
            'fires — leaving AsyncLoading traps the user on the spinner.',
      );
      expect(result.value, isNull);
      expect(result.isLoading, isFalse);
    });

    test(
      'PR1 review — Fix A: cancelLoading during startWorkout AND the in-flight '
      'createActiveWorkout subsequently SUCCEEDS — state stays AsyncData(null) '
      'so the screen redirect is not silently suppressed',
      () async {
        // Reviewer finding: the C4 fix only emits `AsyncData(null)` from
        // `cancelLoading`. But `startWorkout` does
        // `state = await AsyncValue.guard(() async { ... return activeState; })`
        // — a direct assignment with no intervening check. If `cancelLoading`
        // fires while the guard future is still in-flight, the guard's
        // resolved `AsyncData(activeState)` will overwrite the cancel's
        // `AsyncData(null)` once the network call completes. The screen's
        // `displayState == null && !asyncState.isLoading` redirect at
        // `active_workout_screen.dart:68` runs in a `postFrameCallback`, so
        // the overwrite can land BEFORE the frame callback executes —
        // silently suppressing the C4 escape-hatch.
        //
        // Fix: add a `_cancelRequested` post-guard check to `startWorkout`
        // mirroring the C1 saveCommitted pattern. When `_cancelRequested`
        // is true at the end of the guard, reset it and force the state
        // back to `AsyncData(null)` so the screen redirect fires.
        final (:container, :mockRepo, :mockStorage, :mockAuth) =
            makeAsyncContainer(null, locale: const Locale('en'));
        addTearDown(container.dispose);

        when(() => mockAuth.currentUser).thenReturn(fakeUser());
        final createCompleter = Completer<Workout>();
        when(
          () => mockRepo.createActiveWorkout(
            userId: any(named: 'userId'),
            name: any(named: 'name'),
          ),
        ).thenAnswer((_) => createCompleter.future);

        await container.read(activeWorkoutProvider.future);

        // 1. Kick off start — the guard hangs on the completer.
        final startFuture = container
            .read(activeWorkoutProvider.notifier)
            .startWorkout('First workout');

        await Future<void>.delayed(Duration.zero);
        expect(container.read(activeWorkoutProvider).isLoading, isTrue);

        // 2. Cancel — emits AsyncData(null) so the screen would redirect.
        container.read(activeWorkoutProvider.notifier).cancelLoading();
        expect(
          container.read(activeWorkoutProvider).value,
          isNull,
          reason: 'cancelLoading null-branch must settle into AsyncData(null)',
        );

        // 3. Server eventually succeeds — without the post-guard check,
        // the guard's `AsyncData(activeState)` clobbers the cancel and
        // the screen never sees the null-and-settled state needed for
        // the postFrameCallback redirect.
        createCompleter.complete(makeWorkout(id: 'workout-late-success'));
        await startFuture;
        await Future<void>.delayed(Duration.zero);

        final afterComplete = container.read(activeWorkoutProvider);
        expect(afterComplete, isA<AsyncData<ActiveWorkoutState?>>());
        expect(
          afterComplete.value,
          isNull,
          reason:
              'When the user cancels during startWorkout, a late-arriving '
              'guard success must NOT resurrect the workout state — that '
              'would silently suppress the C4 redirect to /home.',
        );
      },
    );

    test('PR1 review — Fix A: cancelLoading during startFromRoutine AND the '
        'in-flight createActiveWorkout subsequently SUCCEEDS — state stays '
        'AsyncData(null)', () async {
      // Same reviewer finding as the startWorkout test above, applied to
      // the routine-prefilled start path. `startFromRoutine` has the
      // identical `state = await AsyncValue.guard(...)` shape and is
      // exposed to the same overwrite race.
      final (:container, :mockRepo, :mockStorage, :mockAuth) =
          makeAsyncContainer(null, locale: const Locale('en'));
      addTearDown(container.dispose);

      when(() => mockAuth.currentUser).thenReturn(fakeUser());
      final createCompleter = Completer<Workout>();
      when(
        () => mockRepo.createActiveWorkout(
          userId: any(named: 'userId'),
          name: any(named: 'name'),
        ),
      ).thenAnswer((_) => createCompleter.future);
      when(
        () => mockRepo.getLastWorkoutSets(any()),
      ).thenAnswer((_) async => {});

      await container.read(activeWorkoutProvider.future);

      // 1. Kick off startFromRoutine — hangs on the completer.
      final routineConfig = RoutineStartConfig(
        routineName: 'Push Day',
        routineId: 'routine-push',
        exercises: [
          RoutineStartExercise(
            exerciseId: 'ex-bench',
            exercise: makeExercise(id: 'ex-bench', name: 'Bench Press'),
            setCount: 3,
            targetReps: 10,
            restSeconds: 90,
          ),
        ],
      );
      final startFuture = container
          .read(activeWorkoutProvider.notifier)
          .startFromRoutine(routineConfig);

      await Future<void>.delayed(Duration.zero);
      expect(container.read(activeWorkoutProvider).isLoading, isTrue);

      // 2. Cancel — emits AsyncData(null).
      container.read(activeWorkoutProvider.notifier).cancelLoading();
      expect(container.read(activeWorkoutProvider).value, isNull);

      // 3. Server eventually succeeds — late guard result must NOT
      //    resurrect the workout state.
      createCompleter.complete(makeWorkout(id: 'workout-routine-late'));
      await startFuture;
      await Future<void>.delayed(Duration.zero);

      final afterComplete = container.read(activeWorkoutProvider);
      expect(afterComplete, isA<AsyncData<ActiveWorkoutState?>>());
      expect(
        afterComplete.value,
        isNull,
        reason:
            'startFromRoutine must honor a cancel-during-loading the same '
            'way as startWorkout — late guard success must NOT clobber '
            'the cancel-emitted null state.',
      );
    });
  });

  // --------------------------------------------------------------------------
  // Phase 14d: PR detection reads from cache, always enqueues, updates cache
  // --------------------------------------------------------------------------
  group('ActiveWorkoutNotifier — PR detection (Phase 14d)', () {
    late MockWorkoutRepository mockRepo;
    late MockWorkoutLocalStorage mockStorage;
    late MockAuthRepository mockAuth;
    late MockCacheService mockCache;
    late MockPRRepository mockPRRepo;
    late _CapturingPendingSyncNotifier capturedNotifier;

    /// Builds a container with all PR-related mocks wired up.
    ProviderContainer makePRContainer(ActiveWorkoutState initialState) {
      mockRepo = MockWorkoutRepository();
      mockStorage = MockWorkoutLocalStorage();
      mockAuth = MockAuthRepository();
      mockCache = MockCacheService();
      mockPRRepo = MockPRRepository();
      capturedNotifier = _CapturingPendingSyncNotifier();

      when(() => mockStorage.loadActiveWorkout()).thenReturn(initialState);
      when(() => mockStorage.saveActiveWorkout(any())).thenAnswer((_) async {});
      when(() => mockStorage.clearActiveWorkout()).thenAnswer((_) async {});
      when(() => mockAuth.currentUser).thenReturn(fakeUser());
      when(() => mockRepo.getCachedWorkoutCount(any())).thenReturn(5);

      // Default: cache write is fire-and-forget.
      when(() => mockCache.write(any(), any(), any())).thenAnswer((_) async {});

      return ProviderContainer(
        overrides: [
          workoutRepositoryProvider.overrideWithValue(mockRepo),
          workoutLocalStorageProvider.overrideWithValue(mockStorage),
          authRepositoryProvider.overrideWithValue(mockAuth),
          analyticsRepositoryProvider.overrideWithValue(
            const _FakeAnalyticsRepository(),
          ),
          pendingSyncProvider.overrideWith(() => capturedNotifier),
          cacheServiceProvider.overrideWithValue(mockCache),
          prRepositoryProvider.overrideWithValue(mockPRRepo),
          prDetectionServiceProvider.overrideWithValue(PRDetectionService()),
        ],
      );
    }

    /// Returns a state with one exercise (barbell, completed sets) that
    /// will trigger PR detection. The Exercise model is embedded in the
    /// WorkoutExercise so `detectPRs` does not skip it.
    ActiveWorkoutState stateWithCompletedSets() {
      final exercise = Exercise.fromJson(
        TestExerciseFactory.create(
          id: 'exercise-1',
          name: 'Bench Press',
          equipmentType: 'barbell',
        ),
      );
      final we = WorkoutExercise(
        id: 'we-1',
        workoutId: 'workout-001',
        exerciseId: 'exercise-1',
        order: 0,
        exercise: exercise,
      );
      final sets = [
        ExerciseSet.fromJson(
          TestSetFactory.create(
            id: 'set-1',
            workoutExerciseId: 'we-1',
            setNumber: 1,
            weight: 100.0,
            reps: 8,
            isCompleted: true,
          ),
        ),
        ExerciseSet.fromJson(
          TestSetFactory.create(
            id: 'set-2',
            workoutExerciseId: 'we-1',
            setNumber: 2,
            weight: 110.0,
            reps: 6,
            isCompleted: true,
          ),
        ),
      ];
      return ActiveWorkoutState(
        workout: Workout.fromJson(TestWorkoutFactory.create(isActive: true)),
        exercises: [ActiveWorkoutExercise(workoutExercise: we, sets: sets)],
      );
    }

    test(
      'finishWorkout reads existing records from pr_cache, not PRRepository',
      () async {
        final initial = stateWithCompletedSets();
        final container = makePRContainer(initial);
        addTearDown(container.dispose);

        // Stub saveWorkout to succeed.
        when(
          () => mockRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).thenAnswer(
          (_) async => Workout.fromJson(TestWorkoutFactory.create()),
        );

        // Cache returns empty records (no existing PRs).
        when(
          () => mockCache.read<Map<String, List<PersonalRecord>>>(
            any(),
            any(),
            any(),
          ),
        ).thenReturn(<String, List<PersonalRecord>>{});

        await container.read(activeWorkoutProvider.future);
        await container.read(activeWorkoutProvider.notifier).finishWorkout();

        // CacheService.read must have been called for the pr_cache.
        verify(
          () => mockCache.read<Map<String, List<PersonalRecord>>>(
            'pr_cache',
            any(),
            any(),
          ),
        ).called(1);

        // PRRepository.getRecordsForExercises must NOT be called (cache hit).
        verifyNever(() => mockPRRepo.getRecordsForExercises(any()));
      },
    );

    test(
      'finishWorkout falls back to PRRepository when cache misses',
      () async {
        final initial = stateWithCompletedSets();
        final container = makePRContainer(initial);
        addTearDown(container.dispose);

        when(
          () => mockRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).thenAnswer(
          (_) async => Workout.fromJson(TestWorkoutFactory.create()),
        );

        // Cache returns null (miss).
        when(
          () => mockCache.read<Map<String, List<PersonalRecord>>>(
            any(),
            any(),
            any(),
          ),
        ).thenReturn(null);

        // PRRepository fallback returns empty records.
        when(
          () => mockPRRepo.getRecordsForExercises(any()),
        ).thenAnswer((_) async => <String, List<PersonalRecord>>{});

        await container.read(activeWorkoutProvider.future);
        await container.read(activeWorkoutProvider.notifier).finishWorkout();

        // PRRepository must be called as fallback.
        verify(() => mockPRRepo.getRecordsForExercises(any())).called(1);
      },
    );

    test(
      'finishWorkout fires upsertRecords (detached) when parent saved online',
      () async {
        final initial = stateWithCompletedSets();
        final container = makePRContainer(initial);
        addTearDown(container.dispose);

        when(
          () => mockRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).thenAnswer(
          (_) async => Workout.fromJson(TestWorkoutFactory.create()),
        );

        // Cache returns empty records so all sets produce new PRs.
        when(
          () => mockCache.read<Map<String, List<PersonalRecord>>>(
            any(),
            any(),
            any(),
          ),
        ).thenReturn(<String, List<PersonalRecord>>{});

        // Stub the direct upsert so the new "online → detached upsert"
        // path succeeds without falling back to the queue.
        when(() => mockPRRepo.upsertRecords(any())).thenAnswer((_) async {});

        await container.read(activeWorkoutProvider.future);
        await container.read(activeWorkoutProvider.notifier).finishWorkout();

        // Detached upsert is kicked off inside an unawaited async closure
        // — let microtasks drain so the inner `await prRepo.upsertRecords`
        // registers on the mock.
        await Future<void>.delayed(Duration.zero);

        // Online + parent committed: direct upsert is preferred. PRs must
        // NOT sit in the offline queue waiting for a connectivity blip.
        verify(() => mockPRRepo.upsertRecords(any())).called(1);

        // No PendingUpsertRecords should have been enqueued.
        expect(
          capturedNotifier.enqueued.whereType<PendingUpsertRecords>(),
          isEmpty,
        );
      },
    );

    test(
      'finishWorkout falls back to PendingUpsertRecords when direct upsert '
      'throws (online but server rejects / network drops mid-call)',
      () async {
        final initial = stateWithCompletedSets();
        final container = makePRContainer(initial);
        addTearDown(container.dispose);

        when(
          () => mockRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).thenAnswer(
          (_) async => Workout.fromJson(TestWorkoutFactory.create()),
        );
        when(
          () => mockCache.read<Map<String, List<PersonalRecord>>>(
            any(),
            any(),
            any(),
          ),
        ).thenReturn(<String, List<PersonalRecord>>{});

        // Direct upsert returns a failed Future → finishWorkout's detached
        // closure must fall back to queue. We use `thenAnswer((_) async =>
        // throw …)` rather than `thenThrow` so the failure surfaces as an
        // async-completed Future, matching what `mapException` emits in
        // production (mapException always returns Future.error, never a
        // synchronous throw — but the detached closure handles both via
        // try/catch around `await`).
        when(() => mockPRRepo.upsertRecords(any())).thenAnswer(
          (_) async => throw const app.DatabaseException(
            'connection lost mid-upsert',
            code: 'network_error',
          ),
        );

        await container.read(activeWorkoutProvider.future);
        await container.read(activeWorkoutProvider.notifier).finishWorkout();

        // Detached closure: upsertRecords + the fallback enqueue both run
        // as microtasks. Drain twice — once for the upsertRecords await,
        // once for the enqueue await.
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        // Direct attempt fired …
        verify(() => mockPRRepo.upsertRecords(any())).called(1);

        // … and on its failure we fell back to the queue with empty
        // dependsOn (parent saveWorkout already committed).
        final upsertActions = capturedNotifier.enqueued
            .whereType<PendingUpsertRecords>()
            .toList();
        expect(upsertActions, hasLength(1));
        expect(upsertActions.first.dependsOn, isEmpty);
        expect(upsertActions.first.userId, 'user-test-001');
      },
    );

    test(
      'finishWorkout updates pr_cache optimistically after detecting new PRs',
      () async {
        final initial = stateWithCompletedSets();
        final container = makePRContainer(initial);
        addTearDown(container.dispose);

        when(
          () => mockRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).thenAnswer(
          (_) async => Workout.fromJson(TestWorkoutFactory.create()),
        );

        // Cache returns empty records — all sets should trigger new PRs.
        when(
          () => mockCache.read<Map<String, List<PersonalRecord>>>(
            any(),
            any(),
            any(),
          ),
        ).thenReturn(<String, List<PersonalRecord>>{});

        await container.read(activeWorkoutProvider.future);
        await container.read(activeWorkoutProvider.notifier).finishWorkout();

        // Cache must have been written with the merged records.
        verify(() => mockCache.write('pr_cache', any(), any())).called(1);
      },
    );

    test('finishWorkout uses getCachedWorkoutCount unconditionally', () async {
      final initial = stateWithCompletedSets();
      final container = makePRContainer(initial);
      addTearDown(container.dispose);

      when(
        () => mockRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
        ),
      ).thenAnswer((_) async => Workout.fromJson(TestWorkoutFactory.create()));

      when(
        () => mockCache.read<Map<String, List<PersonalRecord>>>(
          any(),
          any(),
          any(),
        ),
      ).thenReturn(<String, List<PersonalRecord>>{});

      await container.read(activeWorkoutProvider.future);
      await container.read(activeWorkoutProvider.notifier).finishWorkout();

      // getCachedWorkoutCount must be called.
      verify(() => mockRepo.getCachedWorkoutCount(any())).called(1);

      // getFinishedWorkoutCount must NOT be called (no network).
      verifyNever(() => mockRepo.getFinishedWorkoutCount(any()));
    });

    // Edge case: workout with no exercises (or no completed sets) produces
    // no new PRs — cache.write must NOT be called.
    test(
      'finishWorkout does not write pr_cache when no new PRs are detected',
      () async {
        // Build a state with no exercises at all.
        final emptyState = ActiveWorkoutState(
          workout: Workout.fromJson(TestWorkoutFactory.create(isActive: true)),
          exercises: const [],
        );
        final container = makePRContainer(emptyState);
        addTearDown(container.dispose);

        when(
          () => mockRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).thenAnswer(
          (_) async => Workout.fromJson(TestWorkoutFactory.create()),
        );

        // Cache returns empty map — but no exercises means no detection.
        when(
          () => mockCache.read<Map<String, List<PersonalRecord>>>(
            any(),
            any(),
            any(),
          ),
        ).thenReturn(<String, List<PersonalRecord>>{});

        await container.read(activeWorkoutProvider.future);
        final finishResult = await container
            .read(activeWorkoutProvider.notifier)
            .finishWorkout();

        // No new records → no cache write.
        verifyNever(() => mockCache.write(any(), any(), any()));

        // No PendingUpsertRecords enqueued.
        expect(
          capturedNotifier.enqueued.whereType<PendingUpsertRecords>(),
          isEmpty,
        );

        // finishWorkout still succeeds; inner prResult has no new records.
        expect(finishResult, isNotNull);
        expect(finishResult!.prResult?.hasNewRecords ?? false, isFalse);
      },
    );

    // Edge case: cache misses AND prRepo.getRecordsForExercises throws.
    // PR detection error must be swallowed — workout save must still succeed.
    test(
      'finishWorkout swallows error when both cache and prRepo fail',
      () async {
        final initial = stateWithCompletedSets();
        final container = makePRContainer(initial);
        addTearDown(container.dispose);

        when(
          () => mockRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).thenAnswer(
          (_) async => Workout.fromJson(TestWorkoutFactory.create()),
        );

        // Cache misses.
        when(
          () => mockCache.read<Map<String, List<PersonalRecord>>>(
            any(),
            any(),
            any(),
          ),
        ).thenReturn(null);

        // Fallback prRepo also throws.
        when(
          () => mockPRRepo.getRecordsForExercises(any()),
        ).thenThrow(Exception('Network unreachable'));

        await container.read(activeWorkoutProvider.future);

        // Must not throw — workout finishes even when PR detection is broken.
        final finishResult = await container
            .read(activeWorkoutProvider.notifier)
            .finishWorkout();

        // State is null (workout cleared).
        expect(container.read(activeWorkoutProvider).value, isNull);

        // The finish itself succeeded (record returned); inner prResult is
        // null because detection threw and the catch block left prResult
        // unset.
        expect(finishResult, isNotNull);
        expect(finishResult!.prResult, isNull);

        // upsertRecords must NOT be enqueued (detection never produced records).
        expect(
          capturedNotifier.enqueued.whereType<PendingUpsertRecords>(),
          isEmpty,
        );
      },
    );

    // BUG-009: PR-detection failures must be Sentry-captured in addition
    // to logged. Historically the catch silently swallowed errors which
    // masked BUG-001 — null casts inside detectPRs hid for weeks because
    // production never saw the exception rate.
    test(
      'BUG-009: PR-detection error is captured to Sentry while workout still saves',
      () async {
        var captureCount = 0;
        Object? lastCaptured;
        SentryReport.debugSetCaptureFn((error, {stackTrace}) async {
          captureCount++;
          lastCaptured = error;
          return const SentryId.empty();
        });
        addTearDown(() => SentryReport.debugSetCaptureFn(null));

        final initial = stateWithCompletedSets();
        final container = makePRContainer(initial);
        addTearDown(container.dispose);

        when(
          () => mockRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).thenAnswer(
          (_) async => Workout.fromJson(TestWorkoutFactory.create()),
        );

        // Cache misses → falls back to prRepo, which throws a TypeError-like
        // failure. The notifier's try/catch around detection must swallow
        // it for the workout save AND forward to Sentry.
        when(
          () => mockCache.read<Map<String, List<PersonalRecord>>>(
            any(),
            any(),
            any(),
          ),
        ).thenReturn(null);
        when(
          () => mockPRRepo.getRecordsForExercises(any()),
        ).thenThrow(TypeError());

        await container.read(activeWorkoutProvider.future);

        // Workout finishes without throwing.
        final finishResult = await container
            .read(activeWorkoutProvider.notifier)
            .finishWorkout();

        // State cleared (workout committed).
        expect(container.read(activeWorkoutProvider).value, isNull);
        // Finish itself returned a record; inner prResult is null because
        // detection threw — pin both for clarity.
        expect(finishResult, isNotNull);
        expect(finishResult!.prResult, isNull);

        // Sentry must have received the detection failure exactly once.
        expect(captureCount, 1);
        expect(lastCaptured, isA<TypeError>());
      },
    );

    test(
      'optimistic cache merge replaces existing record with same recordType',
      () async {
        final initial = stateWithCompletedSets();
        final container = makePRContainer(initial);
        addTearDown(container.dispose);

        when(
          () => mockRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).thenAnswer(
          (_) async => Workout.fromJson(TestWorkoutFactory.create()),
        );

        // Cache already contains a lower-value maxWeight record for exercise-1.
        // The new workout has weight=110 which beats 90 → new PR detected.
        final existingRecord = PersonalRecord(
          id: 'pr-old',
          userId: 'user-test-001',
          exerciseId: 'exercise-1',
          recordType: RecordType.maxWeight,
          value: 90.0,
          achievedAt: DateTime.utc(2026, 1, 1),
        );
        when(
          () => mockCache.read<Map<String, List<PersonalRecord>>>(
            any(),
            any(),
            any(),
          ),
        ).thenReturn({
          'exercise-1': [existingRecord],
        });

        // Capture what gets written to the cache.
        Map<String, dynamic>? writtenValue;
        when(() => mockCache.write(any(), any(), any())).thenAnswer((
          invocation,
        ) async {
          writtenValue =
              invocation.positionalArguments[2] as Map<String, dynamic>;
        });

        await container.read(activeWorkoutProvider.future);
        await container.read(activeWorkoutProvider.notifier).finishWorkout();

        // Cache write must have occurred.
        verify(() => mockCache.write('pr_cache', any(), any())).called(1);

        expect(writtenValue, isNotNull);
        final mergedList =
            writtenValue!['exercise-1'] as List<Map<String, dynamic>>;
        // PRDetectionService produces 3 records (maxWeight, maxReps,
        // maxVolume). The old maxWeight (90) is replaced by the new one;
        // the other two are new additions → 3 total, not 4.
        expect(mergedList.length, equals(3));
        final maxWeightRecords = mergedList
            .where((r) => r['record_type'] == 'max_weight')
            .toList();
        expect(
          maxWeightRecords.length,
          equals(1),
          reason: 'Old maxWeight should be replaced, not duplicated',
        );
        expect(
          (maxWeightRecords.first['value'] as num) > 90,
          isTrue,
          reason: 'Merged maxWeight should be the new higher-value PR',
        );
      },
    );

    // ------------------------------------------------------------------
    // AW-EX-D-US1-02 — two-workout PR sequence
    //
    // Workout A (50×8, single exercise) finishes online → optimistic
    // cache write seeds the per-exercise key with a 50kg maxWeight.
    // Workout B (70×8, same exercise) finishes online → must read the
    // 50kg baseline back from the cache, detect 70 > 50 as a new PR, and
    // produce `prResult.hasNewRecords == true` so the post-workout
    // navigator sends the user to /pr-celebration.
    //
    // Reproducer-side note: the test uses a stateful in-memory cache that
    // serves what was last written (matches Hive's in-memory semantics
    // — `box.put` is visible to the next synchronous `box.get` even when
    // the flush is unawaited). If the bug is in the unit-level data flow,
    // workout B's `prResult.hasNewRecords` will be `false` here.
    // ------------------------------------------------------------------
    test('AW-EX-D-US1-02: workout B (70×8) detects PR after workout A (50×8) '
        'optimistic cache write — same exercise', () async {
      // Build a state for one finished-equivalent workout with weight
      // chosen by the caller. We rebuild the state for each call so the
      // per-set ids do not collide between workout A and workout B.
      ActiveWorkoutState makeRdlState({
        required String workoutId,
        required String exerciseId,
        required String workoutExerciseId,
        required String setId,
        required double weight,
        required int reps,
      }) {
        final exercise = Exercise.fromJson(
          TestExerciseFactory.create(
            id: exerciseId,
            name: 'Romanian Deadlift',
            equipmentType: 'barbell',
          ),
        );
        final we = WorkoutExercise(
          id: workoutExerciseId,
          workoutId: workoutId,
          exerciseId: exerciseId,
          order: 0,
          exercise: exercise,
        );
        final sets = [
          ExerciseSet.fromJson(
            TestSetFactory.create(
              id: setId,
              workoutExerciseId: workoutExerciseId,
              setNumber: 1,
              weight: weight,
              reps: reps,
              isCompleted: true,
            ),
          ),
        ];
        return ActiveWorkoutState(
          workout: Workout.fromJson(
            TestWorkoutFactory.create(id: workoutId, isActive: true),
          ),
          exercises: [ActiveWorkoutExercise(workoutExercise: we, sets: sets)],
        );
      }

      // Stateful in-memory cache fake. Mirrors Hive's contract: write
      // is async-but-immediately-visible (in-memory map updated before
      // the Future resolves). Read is synchronous.
      final store = <String, dynamic>{};
      final fakeCache = _StatefulFakeCache(store);

      final mockRepo = MockWorkoutRepository();
      final mockStorage = MockWorkoutLocalStorage();
      final mockAuth = MockAuthRepository();
      final mockPRRepo = MockPRRepository();
      final mockRpgRepo = MockRpgRepository();
      final mockPeakLoadsRepo = MockPeakLoadsRepository();
      final capturedNotifier = _CapturingPendingSyncNotifier();

      when(() => mockStorage.saveActiveWorkout(any())).thenAnswer((_) async {});
      when(() => mockStorage.clearActiveWorkout()).thenAnswer((_) async {});
      when(() => mockAuth.currentUser).thenReturn(fakeUser());
      when(() => mockRepo.getCachedWorkoutCount(any())).thenReturn(5);
      when(
        () => mockRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
        ),
      ).thenAnswer((_) async => Workout.fromJson(TestWorkoutFactory.create()));
      // RPG providers: stub so the post-save celebration build doesn't
      // throw and short-circuit the PR detection block via the silent
      // catch around `_buildAndStashCelebration`. PR detection itself
      // does not depend on RPG state — but the catch in the production
      // code is wide enough to swallow either subsystem's failure.
      when(
        () => mockRpgRepo.getAllBodyPartProgress(),
      ).thenAnswer((_) async => const <BodyPartProgress>[]);
      when(
        () => mockRpgRepo.getCharacterState(),
      ).thenAnswer((_) async => CharacterState.empty);
      // Online → detached upsert is preferred. Stub it as a no-op.
      when(() => mockPRRepo.upsertRecords(any())).thenAnswer((_) async {});
      // Cache-miss fallback: PRRepo returns whatever's in the database.
      // For workout A there's no history → empty map. The cache hit
      // for workout B should serve workout A's optimistic write — so
      // this stub should NOT be called for workout B (verified below).
      when(
        () => mockPRRepo.getRecordsForExercises(any()),
      ).thenAnswer((_) async => <String, List<PersonalRecord>>{});

      // Initial state for workout A. We will rebuild via
      // `loadActiveWorkout` between the two finishes so the notifier
      // re-reads the second workout's state when we trigger a refresh.
      var nextState = makeRdlState(
        workoutId: 'workout-A',
        exerciseId: 'rdl-1',
        workoutExerciseId: 'we-A',
        setId: 'set-A',
        weight: 50.0,
        reps: 8,
      );
      when(() => mockStorage.loadActiveWorkout()).thenAnswer((_) => nextState);

      final container = ProviderContainer(
        overrides: [
          workoutRepositoryProvider.overrideWithValue(mockRepo),
          workoutLocalStorageProvider.overrideWithValue(mockStorage),
          authRepositoryProvider.overrideWithValue(mockAuth),
          analyticsRepositoryProvider.overrideWithValue(
            const _FakeAnalyticsRepository(),
          ),
          pendingSyncProvider.overrideWith(() => capturedNotifier),
          cacheServiceProvider.overrideWithValue(fakeCache),
          prRepositoryProvider.overrideWithValue(mockPRRepo),
          prDetectionServiceProvider.overrideWithValue(PRDetectionService()),
          rpgRepositoryProvider.overrideWithValue(mockRpgRepo),
          peakLoadsRepositoryProvider.overrideWithValue(mockPeakLoadsRepo),
        ],
      );
      addTearDown(container.dispose);

      // ─── Workout A ─────────────────────────────────────────────────
      await container.read(activeWorkoutProvider.future);
      final resultA = await container
          .read(activeWorkoutProvider.notifier)
          .finishWorkout();

      expect(resultA, isNotNull);
      expect(
        resultA!.prResult?.hasNewRecords,
        isTrue,
        reason:
            'Workout A is the first-ever RDL set → must be detected as a PR.',
      );

      // The optimistic cache write must have landed under
      // 'exercises:rdl-1' (single-id key matches the per-exercise
      // shape Family 1A reads).
      expect(
        store.containsKey('pr_cache/exercises:rdl-1'),
        isTrue,
        reason: 'Optimistic cache write should land under per-exercise key.',
      );

      // Drain microtasks so the unawaited detached upsert and
      // post-finish housekeeping settle before workout B starts.
      await Future<void>.delayed(Duration.zero);

      // ─── Workout B ─────────────────────────────────────────────────
      // Swap the storage backing so the next `loadActiveWorkout` returns
      // workout B's state. Then invalidate the notifier so it re-runs
      // build() against the new state. This mirrors the production
      // flow: the user finishes A, /pr-celebration → /home, taps
      // "Start workout", which mounts a new ActiveWorkoutNotifier
      // instance that reads from storage.
      nextState = makeRdlState(
        workoutId: 'workout-B',
        exerciseId: 'rdl-1',
        workoutExerciseId: 'we-B',
        setId: 'set-B',
        weight: 70.0,
        reps: 8,
      );
      container.invalidate(activeWorkoutProvider);
      await container.read(activeWorkoutProvider.future);

      final resultB = await container
          .read(activeWorkoutProvider.notifier)
          .finishWorkout();

      expect(resultB, isNotNull);
      // CORE REGRESSION ASSERTION — this is the bug surface:
      expect(
        resultB!.prResult?.hasNewRecords,
        isTrue,
        reason:
            'Workout B (70 kg × 8) beats workout A (50 kg × 8) on weight '
            '— must be detected as a new PR. If this fails, the '
            'in-memory cache fake confirms the bug repros at the '
            'unit level (no Hive/IndexedDB timing involved).',
      );

      // Pin the cache-hit path explicitly. Workout A legitimately calls
      // `getRecordsForExercises` once (cold cache → DB fallback returns
      // empty map → first PR detection runs against empty baseline).
      // Workout B MUST hit the cache that workout A's optimistic write
      // seeded — so the call count stays at 1, not 2. Without this
      // assertion the test would silently pass on a workout-B cache miss
      // because the DB stub also returns empty (workout A's PR would be
      // re-detected against an empty baseline → `hasNewRecords == true`
      // for the wrong reason). This verification keeps that loophole
      // closed.
      verify(() => mockPRRepo.getRecordsForExercises(any())).called(1);
    });
  });
}

/// Stateful in-memory cache fake used by the AW-EX-D-US1-02 reproducer.
///
/// Mirrors the real `CacheService` contract end-to-end: writes
/// `jsonEncode` the value into a String and reads `jsonDecode` it before
/// passing to `fromJson` (matching `lib/core/local_storage/cache_service.dart`).
/// Without the round-trip the reader's type casts
/// (`json as Map`, `(v as List)`, `e as Map`)
/// would not exercise the same code path the production path runs against
/// a Hive-backed string payload.
///
/// `read` and `write` swallow errors silently — same contract as the real
/// `CacheService` — so a deserialization failure surfaces as a cache MISS
/// to the caller, never as a thrown exception. This is critical for the
/// reproducer because production code only logs a cache failure; it does
/// not bubble up.
class _StatefulFakeCache implements CacheService {
  _StatefulFakeCache(this._store);

  final Map<String, dynamic> _store;

  @override
  T? read<T>(String boxName, String key, T Function(dynamic) fromJson) {
    final raw = _store['$boxName/$key'];
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      return fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String boxName, String key, dynamic value) async {
    try {
      _store['$boxName/$key'] = jsonEncode(value);
    } catch (_) {
      // Match the real CacheService: swallow encode failures.
    }
  }

  @override
  Future<void> delete(String boxName, String key) async {
    _store.remove('$boxName/$key');
  }

  @override
  Future<void> clearBox(String boxName) async {
    _store.removeWhere((k, _) => k.startsWith('$boxName/'));
  }
}
