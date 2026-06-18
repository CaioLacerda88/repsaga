/// Unit tests for [estimateRoutineDurationMinutes].
///
/// Used by P8's beginner CTA stats line. Must stay deterministic so the
/// rendered "~N min" label matches the seed's Full Body routine (and any
/// other recommended beginner routines we add later).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/routines/models/routine.dart';
import 'package:repsaga/features/weekly_plan/utils/routine_duration_estimator.dart';

import '../../../fixtures/test_factories.dart';

void main() {
  group('estimateRoutineDurationMinutes', () {
    test('returns 0 for a routine with no exercises', () {
      final routine = Routine(
        id: 'r-empty',
        name: 'Empty',
        isDefault: false,
        exercises: const [],
        createdAt: DateTime(2026, 1, 1),
      );
      expect(estimateRoutineDurationMinutes(routine), 0);
    });

    test(
      'matches the seed Full Body routine (~55 min at 30s work/set + 240/180/60s rests)',
      () {
        // Mirrors supabase/seed.sql line 180-185: 6 exercises × 3 sets each.
        // Rest per set: Squat 240, Bench 180, Row 180, OHP 180, Curl 60, Plank 60.
        // Per exercise seconds = 3 × (rest + 30). Sum = 3240s = 54 min → 55 min.
        final routine = Routine(
          id: 'r-fb',
          name: 'Full Body',
          isDefault: true,
          exercises: [
            _exerciseWith(restSeconds: 240, sets: 3),
            _exerciseWith(restSeconds: 180, sets: 3),
            _exerciseWith(restSeconds: 180, sets: 3),
            _exerciseWith(restSeconds: 180, sets: 3),
            _exerciseWith(restSeconds: 60, sets: 3),
            _exerciseWith(restSeconds: 60, sets: 3),
          ],
          createdAt: DateTime(2026, 1, 1),
        );
        expect(estimateRoutineDurationMinutes(routine), 55);
      },
    );

    test(
      'uses the 6 min per-exercise fallback when set_configs are missing',
      () {
        // Two exercises, both with empty set_configs → 2 × 6 = 12 min → 10
        // (nearest 5 to 12 is 10 when using banker-free .round() in Dart).
        final routine = Routine(
          id: 'r-legacy',
          name: 'Legacy',
          isDefault: false,
          exercises: const [
            RoutineExercise(exerciseId: 'e1', setConfigs: []),
            RoutineExercise(exerciseId: 'e2', setConfigs: []),
          ],
          createdAt: DateTime(2026, 1, 1),
        );
        // 2 × 360s = 720s = 12 min, rounded to nearest 5 = 10.
        expect(estimateRoutineDurationMinutes(routine), 10);
      },
    );

    test('rounds to the nearest 5 minutes', () {
      // Single exercise, 2 sets × (rest 90 + work 30) = 240s = 4 min.
      // 4 min is below the 5 min floor so we clamp up to 5.
      final short = Routine(
        id: 'r-short',
        name: 'Short',
        isDefault: false,
        exercises: [_exerciseWith(restSeconds: 90, sets: 2)],
        createdAt: DateTime(2026, 1, 1),
      );
      expect(estimateRoutineDurationMinutes(short), 5);

      // 3 sets × (120 + 30) = 450s = 7.5 min → 10 (.round() is away-from-zero).
      final medium = Routine(
        id: 'r-medium',
        name: 'Medium',
        isDefault: false,
        exercises: [_exerciseWith(restSeconds: 120, sets: 3)],
        createdAt: DateTime(2026, 1, 1),
      );
      expect(estimateRoutineDurationMinutes(medium), 10);
    });

    test('defaults rest_seconds to 90 when null in a set_config', () {
      // One exercise, 3 sets, all null rest → treated as 90s each.
      // 3 × (90 + 30) = 360s = 6 min → nearest 5 = 5.
      final routine = Routine(
        id: 'r-null',
        name: 'Null rests',
        isDefault: false,
        exercises: const [
          RoutineExercise(
            exerciseId: 'e1',
            setConfigs: [
              RoutineSetConfig(targetReps: 10),
              RoutineSetConfig(targetReps: 10),
              RoutineSetConfig(targetReps: 10),
            ],
          ),
        ],
        createdAt: DateTime(2026, 1, 1),
      );
      expect(estimateRoutineDurationMinutes(routine), 5);
    });

    test('a cardio entry contributes its target duration, not rest×sets', () {
      // 28:00 target = 1680s = 28 min → nearest 5 = 30. If the estimator
      // mistakenly used the rest×sets path (one config, rest 90 + work 30 =
      // 120s = 2 min → 5) it would read FAR too low.
      final routine = Routine(
        id: 'r-cardio',
        name: 'Conditioning',
        isDefault: false,
        exercises: [
          RoutineExercise(
            exerciseId: 'treadmill',
            exercise: _cardioExercise(),
            setConfigs: const [RoutineSetConfig(targetDurationSeconds: 1680)],
          ),
        ],
        createdAt: DateTime(2026, 1, 1),
      );
      expect(estimateRoutineDurationMinutes(routine), 30);
    });

    test('a cardio entry with no target falls back to 30 min', () {
      final routine = Routine(
        id: 'r-cardio-empty',
        name: 'Conditioning',
        isDefault: false,
        exercises: [
          RoutineExercise(
            exerciseId: 'treadmill',
            exercise: _cardioExercise(),
            setConfigs: const [RoutineSetConfig()],
          ),
        ],
        createdAt: DateTime(2026, 1, 1),
      );
      expect(estimateRoutineDurationMinutes(routine), 30);
    });
  });
}

Exercise _cardioExercise() {
  return Exercise.fromJson(
    TestExerciseFactory.create(
      id: 'treadmill',
      name: 'Treadmill',
      muscleGroup: 'cardio',
      equipmentType: 'machine',
      slug: 'treadmill',
    ),
  );
}

/// Helper: one exercise with N identical set_configs at the given rest.
RoutineExercise _exerciseWith({required int restSeconds, required int sets}) {
  return RoutineExercise(
    exerciseId: 'e-${restSeconds}x$sets',
    setConfigs: List.generate(
      sets,
      (_) => RoutineSetConfig(targetReps: 5, restSeconds: restSeconds),
    ),
  );
}
