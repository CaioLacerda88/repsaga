// Never-done seed contract for startFromRoutine.
//
// Weight precedence is target → last-lifted → 0. When there is NO target and
// NO previous session data, a brand-new lift seeds weight = 0 (NOT an
// equipment-type smart default). The 0 is deliberate: it kills the "nebulous"
// equipment-default weight and forces a conscious entry for a lift the user
// has never performed (user-approved 2026-06-20). This intentionally reverses
// the old BUG-004 weight smart-default.
//
// REPS keep the equipment-type default (target → last-lifted → equipDefaults):
// a 0-rep set is a non-set, so reps still fall back to a sensible starting
// count (barbell 5, dumbbell 10, machine 12, etc.).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/data/base_repository.dart';
import 'package:repsaga/features/analytics/data/analytics_repository.dart';
import 'package:repsaga/features/analytics/data/models/analytics_event.dart';
import 'package:repsaga/features/analytics/providers/analytics_providers.dart';
import 'package:repsaga/features/auth/data/auth_repository.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/workouts/data/workout_local_storage.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/exercise_set.dart';
import 'package:repsaga/features/workouts/models/routine_start_config.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/models/weight_unit.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/features/workouts/utils/set_defaults.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../../../fixtures/test_factories.dart';

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

class MockWorkoutLocalStorage extends Mock implements WorkoutLocalStorage {}

class MockAuthRepository extends Mock implements AuthRepository {}

class FakeActiveWorkoutState extends Fake implements ActiveWorkoutState {}

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

User _fakeUser() => const User(
  id: 'user-001',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
  isAnonymous: false,
);

Workout _makeWorkout() =>
    Workout.fromJson(TestWorkoutFactory.create(isActive: true));

Exercise _makeExercise(String equipmentType, {String id = 'ex-001'}) {
  return Exercise.fromJson(
    TestExerciseFactory.create(id: id, equipmentType: equipmentType),
  );
}

({
  ProviderContainer container,
  MockWorkoutRepository mockRepo,
  MockWorkoutLocalStorage mockStorage,
  MockAuthRepository mockAuth,
})
_makeContainer() {
  final mockRepo = MockWorkoutRepository();
  final mockStorage = MockWorkoutLocalStorage();
  final mockAuth = MockAuthRepository();

  when(() => mockStorage.loadActiveWorkout()).thenReturn(null);
  when(() => mockStorage.saveActiveWorkout(any())).thenAnswer((_) async {});

  final container = ProviderContainer(
    overrides: [
      workoutRepositoryProvider.overrideWithValue(mockRepo),
      workoutLocalStorageProvider.overrideWithValue(mockStorage),
      authRepositoryProvider.overrideWithValue(mockAuth),
      analyticsRepositoryProvider.overrideWithValue(
        const _FakeAnalyticsRepository(),
      ),
    ],
  );
  return (
    container: container,
    mockRepo: mockRepo,
    mockStorage: mockStorage,
    mockAuth: mockAuth,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeActiveWorkoutState());
  });

  group('ActiveWorkoutNotifier.startFromRoutine — never-done seed', () {
    test('barbell exercise with no target/no previous data seeds weight 0 and '
        'reps = equipment default (5)', () async {
      final (:container, :mockRepo, :mockStorage, :mockAuth) = _makeContainer();
      addTearDown(container.dispose);

      when(() => mockAuth.currentUser).thenReturn(_fakeUser());
      when(
        () => mockRepo.createActiveWorkout(
          userId: any(named: 'userId'),
          name: any(named: 'name'),
        ),
      ).thenAnswer((_) async => _makeWorkout());
      // No previous session data for this exercise
      when(
        () => mockRepo.getLastWorkoutSets(any()),
      ).thenAnswer((_) async => {});

      final barbellExercise = _makeExercise('barbell');
      final config = RoutineStartConfig(
        routineName: 'Push Day',
        exercises: [
          RoutineStartExercise(
            exerciseId: barbellExercise.id,
            exercise: barbellExercise,
            setCount: 3,
          ),
        ],
      );

      await container.read(activeWorkoutProvider.future);
      await container
          .read(activeWorkoutProvider.notifier)
          .startFromRoutine(config);

      final state = container.read(activeWorkoutProvider).value!;
      final sets = state.exercises[0].sets;

      // Equipment-default reps for barbell (WeightUnit.kg is the default).
      final expected = defaultSetValues(EquipmentType.barbell, WeightUnit.kg);

      // Never-done weight seeds 0 (kill the nebulous equipment default);
      // reps keep the equipment default.
      expect(
        sets[0].weight,
        0.0,
        reason:
            'barbell never-done weight seeds 0 — no target, no history — '
            'forcing a conscious entry, not the 20 kg equipment default.',
      );
      expect(sets[0].reps, expected.reps);
      expect(sets[1].weight, 0.0);
      expect(sets[2].weight, 0.0);
      expect(sets[1].reps, expected.reps);
      expect(sets[2].reps, expected.reps);
    });

    test('dumbbell exercise with no target/no previous data seeds weight 0 and '
        'reps = equipment default (10)', () async {
      final (:container, :mockRepo, :mockStorage, :mockAuth) = _makeContainer();
      addTearDown(container.dispose);

      when(() => mockAuth.currentUser).thenReturn(_fakeUser());
      when(
        () => mockRepo.createActiveWorkout(
          userId: any(named: 'userId'),
          name: any(named: 'name'),
        ),
      ).thenAnswer((_) async => _makeWorkout());
      when(
        () => mockRepo.getLastWorkoutSets(any()),
      ).thenAnswer((_) async => {});

      final dumbbellExercise = _makeExercise('dumbbell');
      final config = RoutineStartConfig(
        routineName: 'Arm Day',
        exercises: [
          RoutineStartExercise(
            exerciseId: dumbbellExercise.id,
            exercise: dumbbellExercise,
            setCount: 2,
          ),
        ],
      );

      await container.read(activeWorkoutProvider.future);
      await container
          .read(activeWorkoutProvider.notifier)
          .startFromRoutine(config);

      final state = container.read(activeWorkoutProvider).value!;
      final sets = state.exercises[0].sets;

      final expected = defaultSetValues(EquipmentType.dumbbell, WeightUnit.kg);

      // Never-done weight seeds 0; reps keep the equipment default (10).
      expect(
        sets[0].weight,
        0.0,
        reason:
            'dumbbell never-done weight seeds 0, not the 10 kg equipment '
            'default.',
      );
      expect(sets[0].reps, expected.reps);
    });

    test(
      'bodyweight exercise with no previous data correctly uses weight 0',
      () async {
        // Bodyweight exercises have weight=0 by design — the never-done seed
        // also returns 0. Verifies the behavior is unchanged for this type.
        final (:container, :mockRepo, :mockStorage, :mockAuth) =
            _makeContainer();
        addTearDown(container.dispose);

        when(() => mockAuth.currentUser).thenReturn(_fakeUser());
        when(
          () => mockRepo.createActiveWorkout(
            userId: any(named: 'userId'),
            name: any(named: 'name'),
          ),
        ).thenAnswer((_) async => _makeWorkout());
        when(
          () => mockRepo.getLastWorkoutSets(any()),
        ).thenAnswer((_) async => {});

        final bwExercise = _makeExercise('bodyweight');
        final config = RoutineStartConfig(
          routineName: 'Calisthenics',
          exercises: [
            RoutineStartExercise(
              exerciseId: bwExercise.id,
              exercise: bwExercise,
              setCount: 2,
              targetReps: 15,
            ),
          ],
        );

        await container.read(activeWorkoutProvider.future);
        await container
            .read(activeWorkoutProvider.notifier)
            .startFromRoutine(config);

        final state = container.read(activeWorkoutProvider).value!;
        final sets = state.exercises[0].sets;

        // Bodyweight: weight=0 is always correct (no change needed for this type).
        expect(sets[0].weight, 0.0);
        expect(sets[0].reps, 15); // targetReps
      },
    );

    test('exercise with previous session data uses last-lifted weight '
        '(regression guard)', () async {
      // Regression guard: when previous data exists, last-lifted weight must
      // still be preferred over the never-done 0 fallback.
      final (:container, :mockRepo, :mockStorage, :mockAuth) = _makeContainer();
      addTearDown(container.dispose);

      when(() => mockAuth.currentUser).thenReturn(_fakeUser());
      when(
        () => mockRepo.createActiveWorkout(
          userId: any(named: 'userId'),
          name: any(named: 'name'),
        ),
      ).thenAnswer((_) async => _makeWorkout());

      // Simulate previous session: 100 kg sets
      final previousSets = [
        ExerciseSet.fromJson(
          TestSetFactory.create(
            id: 'prev-1',
            setNumber: 1,
            weight: 100.0,
            reps: 5,
            workoutExerciseId: 'we-prev',
          ),
        ),
      ];
      when(
        () => mockRepo.getLastWorkoutSets(any()),
      ).thenAnswer((_) async => {'ex-001': previousSets});

      final barbellExercise = _makeExercise('barbell');
      final config = RoutineStartConfig(
        routineName: 'Push Day',
        exercises: [
          RoutineStartExercise(
            exerciseId: barbellExercise.id,
            exercise: barbellExercise,
            setCount: 2,
          ),
        ],
      );

      await container.read(activeWorkoutProvider.future);
      await container
          .read(activeWorkoutProvider.notifier)
          .startFromRoutine(config);

      final state = container.read(activeWorkoutProvider).value!;
      final sets = state.exercises[0].sets;

      // Previous data (100 kg) should take precedence over any default.
      expect(
        sets[0].weight,
        100.0,
        reason:
            'Previous session weight should be preferred over smart defaults.',
      );
    });

    test('machine exercise with no target/no previous data seeds weight 0 and '
        'reps = equipment default (10)', () async {
      final (:container, :mockRepo, :mockStorage, :mockAuth) = _makeContainer();
      addTearDown(container.dispose);

      when(() => mockAuth.currentUser).thenReturn(_fakeUser());
      when(
        () => mockRepo.createActiveWorkout(
          userId: any(named: 'userId'),
          name: any(named: 'name'),
        ),
      ).thenAnswer((_) async => _makeWorkout());
      when(
        () => mockRepo.getLastWorkoutSets(any()),
      ).thenAnswer((_) async => {});

      final machineExercise = _makeExercise('machine');
      final config = RoutineStartConfig(
        routineName: 'Machine Day',
        exercises: [
          RoutineStartExercise(
            exerciseId: machineExercise.id,
            exercise: machineExercise,
            setCount: 1,
          ),
        ],
      );

      await container.read(activeWorkoutProvider.future);
      await container
          .read(activeWorkoutProvider.notifier)
          .startFromRoutine(config);

      final state = container.read(activeWorkoutProvider).value!;
      final sets = state.exercises[0].sets;

      final expected = defaultSetValues(EquipmentType.machine, WeightUnit.kg);

      // Never-done weight seeds 0; reps keep the equipment default (10).
      expect(
        sets[0].weight,
        0.0,
        reason:
            'machine never-done weight seeds 0, not the 20 kg equipment '
            'default.',
      );
      expect(sets[0].reps, expected.reps);
    });
  });
}
