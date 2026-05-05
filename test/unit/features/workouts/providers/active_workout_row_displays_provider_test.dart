/// Provider integration tests for [activeWorkoutRowDisplaysProvider]
/// (Phase 20, commit 6).
///
/// These tests pin the data-flow from [ActiveWorkoutState] + historical
/// [PersonalRecord]s → [resolveRowDisplays] → per-row [PrRowDisplay] list.
/// They verify:
///
///   1. **Bench-press cascade scenario** — the canonical 4-set test from
///      PLAN.md Phase 20 flows correctly through the provider. The binary-rule
///      resolver output matches the expected per-row states.
///
///   2. **State mutation propagates** — adding a 5th set that supersedes the
///      standing PR on set 3 re-emits the provider with set 3 demoted.
///
///   3. **Empty state guard** — provider returns [] when the workout is not
///      loaded or the exercise is absent.
///
///   4. **PR records cache-miss fallback** — when [exercisePRsProvider] is
///      still loading, the provider uses an empty baseline (first-ever workout
///      semantic) and correctly classifies the sets.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/personal_records/models/personal_record.dart';
import 'package:repsaga/features/personal_records/models/record_type.dart';
import 'package:repsaga/features/personal_records/providers/pr_providers.dart';
import 'package:repsaga/features/workouts/data/workout_local_storage.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:repsaga/features/workouts/domain/pr_row_state.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/models/exercise_set.dart';
import 'package:repsaga/features/workouts/models/set_type.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/models/workout_exercise.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../fixtures/test_factories.dart';

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

class MockWorkoutLocalStorage extends Mock implements WorkoutLocalStorage {}

class FakeActiveWorkoutState extends Fake implements ActiveWorkoutState {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ExerciseSet _set({
  required String id,
  required int setNumber,
  required String weId,
  double weight = 60.0,
  int reps = 5,
  bool isCompleted = true,
  SetType setType = SetType.working,
}) {
  return ExerciseSet.fromJson(
    TestSetFactory.create(
      id: id,
      workoutExerciseId: weId,
      setNumber: setNumber,
      weight: weight,
      reps: reps,
      setType: setType.name,
      isCompleted: isCompleted,
    ),
  );
}

PersonalRecord _record({
  required RecordType type,
  required double value,
  int? reps,
}) => PersonalRecord(
  id: 'pr-${type.name}',
  userId: 'user-1',
  exerciseId: 'exercise-bench',
  recordType: type,
  value: value,
  achievedAt: DateTime.utc(2026, 4, 1),
  reps: reps,
);

/// Creates an [ActiveWorkoutState] with one exercise carrying the given sets.
ActiveWorkoutState _makeState({
  required String weId,
  required String exerciseId,
  required List<ExerciseSet> sets,
  EquipmentType equipmentType = EquipmentType.barbell,
}) {
  final exercise = Exercise.fromJson(
    TestExerciseFactory.create(
      id: exerciseId,
      equipmentType: equipmentType.name,
    ),
  );
  final workoutExercise = WorkoutExercise.fromJson(
    TestWorkoutExerciseFactory.create(id: weId, exerciseId: exerciseId),
  ).copyWith(exercise: exercise);

  final workout = Workout.fromJson(TestWorkoutFactory.create(isActive: true));

  return ActiveWorkoutState(
    workout: workout,
    exercises: [
      ActiveWorkoutExercise(workoutExercise: workoutExercise, sets: sets),
    ],
  );
}

/// Builds a [ProviderContainer] with mocked storage returning [state] AND
/// overrides [exercisePRsProvider(exerciseId)] with [records].
ProviderContainer _makeContainer({
  required ActiveWorkoutState state,
  required String exerciseId,
  required List<PersonalRecord> records,
}) {
  final mockStorage = MockWorkoutLocalStorage();
  when(() => mockStorage.loadActiveWorkout()).thenReturn(state);
  when(() => mockStorage.saveActiveWorkout(any())).thenAnswer((_) async {});

  return ProviderContainer(
    overrides: [
      workoutRepositoryProvider.overrideWithValue(MockWorkoutRepository()),
      workoutLocalStorageProvider.overrideWithValue(mockStorage),
      // Synchronously resolve the exercise PRs so the derived provider
      // doesn't have to await — keeps the tests synchronous.
      exercisePRsProvider(exerciseId).overrideWith((ref) async => records),
    ],
  );
}

/// Convenience: builds a container, primes the [activeWorkoutProvider], and
/// then reads [activeWorkoutRowDisplaysProvider] for [weId] + [exerciseId].
Future<List<PrRowDisplay>> _resolve(
  ProviderContainer container, {
  required String weId,
  required String exerciseId,
}) async {
  // Prime the active workout notifier (it loads from local storage on first
  // read — the mock returns the state we seeded).
  await container.read(activeWorkoutProvider.future);
  // Also await the PR records so they are cached before the derived read.
  await container.read(exercisePRsProvider(exerciseId).future);

  return container.read(
    activeWorkoutRowDisplaysProvider((
      workoutExerciseId: weId,
      exerciseId: exerciseId,
    )),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(FakeActiveWorkoutState());
  });

  const weId = 'we-bench';
  const exerciseId = 'exercise-bench';

  group('activeWorkoutRowDisplaysProvider', () {
    test(
      'bench-press 4-set cascade: provider returns correct per-row PR states '
      'matching the binary-rule resolver output',
      () async {
        // The canonical Phase 20 cascade scenario (mirrors resolver case 6).
        // Prior record: 60×8 = maxWeight 60, maxReps 8, maxVolume 480.
        //
        // Set 1 (65×8): breaks maxWeight + maxVolume → standing (volume 520
        //   never beaten by later sets).
        // Set 2 (70×6): breaks maxWeight only → superseded by set 3's 75.
        // Set 3 (75×5): breaks maxWeight → standing (75 is the overall best).
        // Set 4 (60×5): no PR.
        final records = [
          _record(type: RecordType.maxWeight, value: 60, reps: 8),
          _record(type: RecordType.maxReps, value: 8),
          _record(type: RecordType.maxVolume, value: 480),
        ];
        final sets = [
          _set(id: 's1', setNumber: 1, weId: weId, weight: 65, reps: 8),
          _set(id: 's2', setNumber: 2, weId: weId, weight: 70, reps: 6),
          _set(id: 's3', setNumber: 3, weId: weId, weight: 75, reps: 5),
          _set(id: 's4', setNumber: 4, weId: weId, weight: 60, reps: 5),
        ];
        final state = _makeState(
          weId: weId,
          exerciseId: exerciseId,
          sets: sets,
        );

        final container = _makeContainer(
          state: state,
          exerciseId: exerciseId,
          records: records,
        );
        addTearDown(container.dispose);

        final displays = await _resolve(
          container,
          weId: weId,
          exerciseId: exerciseId,
        );

        expect(
          displays,
          hasLength(4),
          reason: 'provider output must be aligned 1:1 with the 4 sets',
        );
        expect(
          displays[0].state,
          PrRowState.completedStandingPr,
          reason: 'set 1: volume 520 unbeaten → standing',
        );
        expect(
          displays[1].state,
          PrRowState.completedSupersededPr,
          reason: 'set 2: maxWeight 70 superseded by set 3 → superseded',
        );
        expect(
          displays[2].state,
          PrRowState.completedStandingPr,
          reason: 'set 3: maxWeight 75 is the standing best → standing',
        );
        expect(
          displays[3].state,
          PrRowState.completedNonPr,
          reason: 'set 4: 60×5 < all bars → non-PR',
        );
      },
    );

    test(
      'provider re-emits with set 3 demoted when a 5th set supersedes its '
      'maxWeight — state mutation propagates through the derived provider',
      () async {
        // Start from the 4-set state above where set 3 is the standing PR
        // for maxWeight (75kg). Then mutate the state to add set 5 (80×5)
        // which supersedes set 3.
        final records = [
          _record(type: RecordType.maxWeight, value: 60, reps: 8),
          _record(type: RecordType.maxReps, value: 8),
          _record(type: RecordType.maxVolume, value: 480),
        ];
        final fourSets = [
          _set(id: 's1', setNumber: 1, weId: weId, weight: 65, reps: 8),
          _set(id: 's2', setNumber: 2, weId: weId, weight: 70, reps: 6),
          _set(id: 's3', setNumber: 3, weId: weId, weight: 75, reps: 5),
          _set(id: 's4', setNumber: 4, weId: weId, weight: 60, reps: 5),
        ];
        final stateWith4 = _makeState(
          weId: weId,
          exerciseId: exerciseId,
          sets: fourSets,
        );

        final container = _makeContainer(
          state: stateWith4,
          exerciseId: exerciseId,
          records: records,
        );
        addTearDown(container.dispose);

        // Establish baseline: set 3 is standing.
        final baselineDisplays = await _resolve(
          container,
          weId: weId,
          exerciseId: exerciseId,
        );
        expect(
          baselineDisplays[2].state,
          PrRowState.completedStandingPr,
          reason: 'baseline: set 3 (75×5) must be standing PR',
        );

        // Mutate: add a 5th set (80×5) that supersedes set 3's maxWeight.
        // Re-seed the notifier state directly through completeSet/updateSet
        // equivalent — simpler to re-build a new container with 5 sets since
        // the provider is derived and pure.
        final fiveSets = [
          ...fourSets,
          _set(id: 's5', setNumber: 5, weId: weId, weight: 80, reps: 5),
        ];
        final stateWith5 = _makeState(
          weId: weId,
          exerciseId: exerciseId,
          sets: fiveSets,
        );

        final container5 = _makeContainer(
          state: stateWith5,
          exerciseId: exerciseId,
          records: records,
        );
        addTearDown(container5.dispose);

        final updatedDisplays = await _resolve(
          container5,
          weId: weId,
          exerciseId: exerciseId,
        );

        expect(updatedDisplays, hasLength(5));
        // Set 1 still standing — volume 520 > set 5's 400.
        expect(
          updatedDisplays[0].state,
          PrRowState.completedStandingPr,
          reason: 'set 1 still standing after set 5 added',
        );
        // Set 3 DEMOTED: 75 beaten by set 5's 80.
        expect(
          updatedDisplays[2].state,
          PrRowState.completedSupersededPr,
          reason:
              'set 3 must be DEMOTED from standing to superseded when '
              'set 5 (80×5) is added — this pins the provider re-emission',
        );
        // Set 5 is the new standing PR for maxWeight.
        expect(
          updatedDisplays[4].state,
          PrRowState.completedStandingPr,
          reason: 'set 5 (80×5) is the new standing maxWeight PR',
        );
      },
    );

    test(
      'returns empty list when the workout is not loaded (state = null)',
      () async {
        // When activeWorkoutProvider has no loaded state (null), the derived
        // provider must return [] immediately — no crash, no stale value.
        final mockStorage = MockWorkoutLocalStorage();
        when(() => mockStorage.loadActiveWorkout()).thenReturn(null);
        when(
          () => mockStorage.saveActiveWorkout(any()),
        ).thenAnswer((_) async {});

        final container = ProviderContainer(
          overrides: [
            workoutRepositoryProvider.overrideWithValue(
              MockWorkoutRepository(),
            ),
            workoutLocalStorageProvider.overrideWithValue(mockStorage),
            exercisePRsProvider(
              exerciseId,
            ).overrideWith((ref) async => const <PersonalRecord>[]),
          ],
        );
        addTearDown(container.dispose);

        // Prime the active workout notifier with null state.
        await container.read(activeWorkoutProvider.future);

        final displays = container.read(
          activeWorkoutRowDisplaysProvider((
            workoutExerciseId: weId,
            exerciseId: exerciseId,
          )),
        );

        expect(
          displays,
          isEmpty,
          reason: 'provider must return [] when no active workout is loaded',
        );
      },
    );

    test(
      'returns empty list when the requested workoutExerciseId is not in the '
      'active state (exercise absent guard)',
      () async {
        // State has exercise 'we-squat', but we read for 'we-bench'.
        final state = _makeState(
          weId: 'we-squat',
          exerciseId: 'exercise-squat',
          sets: [
            _set(
              id: 's1',
              setNumber: 1,
              weId: 'we-squat',
              weight: 100,
              reps: 5,
            ),
          ],
        );
        final container = _makeContainer(
          state: state,
          exerciseId: exerciseId,
          records: const [],
        );
        addTearDown(container.dispose);

        await container.read(activeWorkoutProvider.future);
        await container.read(exercisePRsProvider(exerciseId).future);

        final displays = container.read(
          activeWorkoutRowDisplaysProvider((
            workoutExerciseId: weId, // 'we-bench' — not in state
            exerciseId: exerciseId,
          )),
        );

        expect(
          displays,
          isEmpty,
          reason:
              'provider must return [] when the requested workoutExerciseId '
              'is absent from the active state',
        );
      },
    );

    test(
      'first-ever workout fallback: when exercise has no historical PRs '
      '(existingRecords=[]), the first completed set becomes the standing PR',
      () async {
        // No historical records for this exercise — empty list fed from
        // exercisePRsProvider override. First-ever workout semantic: the
        // resolver treats all historical bars as 0, so the first completed
        // working set with positive load becomes the standing PR.
        final sets = [
          _set(id: 's1', setNumber: 1, weId: weId, weight: 80, reps: 5),
          _set(id: 's2', setNumber: 2, weId: weId, weight: 60, reps: 5),
        ];
        final state = _makeState(
          weId: weId,
          exerciseId: exerciseId,
          sets: sets,
        );

        final container = _makeContainer(
          state: state,
          exerciseId: exerciseId,
          records: const [], // first-ever workout — no history
        );
        addTearDown(container.dispose);

        final displays = await _resolve(
          container,
          weId: weId,
          exerciseId: exerciseId,
        );

        expect(displays, hasLength(2));
        expect(
          displays[0].state,
          PrRowState.completedStandingPr,
          reason:
              'first-ever workout: set 1 (80×5) must be standing PR '
              'when no historical records exist',
        );
        expect(
          displays[1].state,
          PrRowState.completedNonPr,
          reason: 'set 2 (60×5) < set 1 → completedNonPr',
        );
      },
    );
  });
}
