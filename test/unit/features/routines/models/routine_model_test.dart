import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/routines/models/routine.dart';

import '../../../../fixtures/test_factories.dart';

void main() {
  group('RoutineSetConfig', () {
    test('fromJson parses all fields', () {
      final json = TestRoutineSetConfigFactory.create(
        targetReps: 12,
        targetWeight: 80.0,
        restSeconds: 120,
      );

      final config = RoutineSetConfig.fromJson(json);

      expect(config.targetReps, 12);
      expect(config.targetWeight, 80.0);
      expect(config.restSeconds, 120);
    });

    test('fromJson handles null optional fields', () {
      final config = RoutineSetConfig.fromJson({});

      expect(config.targetReps, isNull);
      expect(config.targetWeight, isNull);
      expect(config.restSeconds, isNull);
    });

    test('toJson round-trip preserves data', () {
      final original = RoutineSetConfig.fromJson(
        TestRoutineSetConfigFactory.create(
          targetReps: 8,
          targetWeight: 60.0,
          restSeconds: 90,
        ),
      );
      final roundTripped = RoutineSetConfig.fromJson(original.toJson());

      expect(roundTripped, original);
    });

    test('cardio target round-trips through fromJson/toJson', () {
      final config = RoutineSetConfig.fromJson(
        TestRoutineSetConfigFactory.cardio(
          targetDurationSeconds: 1680,
          targetDistanceM: 5000.0,
        ),
      );

      expect(config.targetDurationSeconds, 1680);
      expect(config.targetDistanceM, 5000.0);
      // A cardio config carries no strength scalars.
      expect(config.targetReps, isNull);
      expect(config.targetWeight, isNull);
      expect(config.restSeconds, isNull);

      final json = config.toJson();
      expect(json['target_duration_seconds'], 1680);
      expect(json['target_distance_m'], 5000.0);

      final roundTripped = RoutineSetConfig.fromJson(json);
      expect(roundTripped, config);
    });

    test(
      'omitting cardio target yields null (back-compat with strength rows)',
      () {
        // A legacy strength row that never carried the new keys must still
        // deserialize with null targets — the JSONB shape is additive.
        final config = RoutineSetConfig.fromJson(
          TestRoutineSetConfigFactory.create(targetReps: 10, restSeconds: 90),
        );

        expect(config.targetDurationSeconds, isNull);
        expect(config.targetDistanceM, isNull);
      },
    );
  });

  group('RoutineExercise', () {
    test('fromJson parses exerciseId and setConfigs', () {
      final json = TestRoutineExerciseFactory.create(
        exerciseId: 'ex-bench',
        setConfigs: [
          TestRoutineSetConfigFactory.create(targetReps: 10, restSeconds: 60),
          TestRoutineSetConfigFactory.create(targetReps: 8, restSeconds: 90),
        ],
      );

      final re = RoutineExercise.fromJson(json);

      expect(re.exerciseId, 'ex-bench');
      expect(re.setConfigs, hasLength(2));
      expect(re.setConfigs[0].targetReps, 10);
      expect(re.setConfigs[1].restSeconds, 90);
      expect(re.exercise, isNull);
    });

    test('fromJson defaults setConfigs to empty list when missing', () {
      final re = RoutineExercise.fromJson({'exercise_id': 'ex-1'});

      expect(re.setConfigs, isEmpty);
    });

    test('toJson excludes exercise field', () {
      final json = TestRoutineExerciseFactory.create();
      final re = RoutineExercise.fromJson(json);
      final output = re.toJson();

      expect(output.containsKey('exercise'), isFalse);
      expect(output['exercise_id'], re.exerciseId);
    });

    test('toJson produces correct keys and values', () {
      final original = RoutineExercise.fromJson(
        TestRoutineExerciseFactory.create(
          exerciseId: 'ex-squat',
          setConfigs: [TestRoutineSetConfigFactory.create(targetReps: 5)],
        ),
      );
      final json = original.toJson();

      expect(json['exercise_id'], 'ex-squat');
      expect(json['set_configs'], isList);
      expect((json['set_configs'] as List).first, isA<Map<String, dynamic>>());
    });
  });

  group('Routine', () {
    test('fromJson parses all fields with nested exercises', () {
      final json = TestRoutineFactory.create(
        id: 'routine-abc',
        userId: 'user-001',
        name: 'Leg Day',
        isDefault: false,
        exercises: [
          TestRoutineExerciseFactory.create(exerciseId: 'ex-squat'),
          TestRoutineExerciseFactory.create(exerciseId: 'ex-lunge'),
        ],
      );

      final routine = Routine.fromJson(json);

      expect(routine.id, 'routine-abc');
      expect(routine.userId, 'user-001');
      expect(routine.name, 'Leg Day');
      expect(routine.isDefault, false);
      expect(routine.exercises, hasLength(2));
      expect(routine.exercises[0].exerciseId, 'ex-squat');
      expect(routine.exercises[1].exerciseId, 'ex-lunge');
    });

    test('fromJson defaults isDefault to false', () {
      final json = TestRoutineFactory.create();
      json.remove('is_default');

      final routine = Routine.fromJson(json);

      expect(routine.isDefault, false);
    });

    test('fromJson defaults exercises to empty list when missing', () {
      final json = {
        'id': 'r-1',
        'name': 'Empty Routine',
        'created_at': '2026-01-01T00:00:00Z',
      };

      final routine = Routine.fromJson(json);

      expect(routine.exercises, isEmpty);
    });

    test('toJson produces correct top-level keys', () {
      final original = Routine.fromJson(
        TestRoutineFactory.create(
          name: 'Full Body',
          isDefault: true,
          exercises: [
            TestRoutineExerciseFactory.create(
              setConfigs: [
                TestRoutineSetConfigFactory.create(
                  targetReps: 12,
                  restSeconds: 60,
                ),
              ],
            ),
          ],
        ),
      );
      final json = original.toJson();

      expect(json['id'], original.id);
      expect(json['name'], 'Full Body');
      expect(json['is_default'], true);
      expect(json['exercises'], isList);
      expect((json['exercises'] as List), hasLength(1));
    });

    test('notes round-trips through fromJson/toJson', () {
      final routine = Routine.fromJson(
        TestRoutineFactory.create(
          notes: 'Program: 5x5. Form: brace before each rep. Deload week 4.',
        ),
      );

      expect(
        routine.notes,
        'Program: 5x5. Form: brace before each rep. Deload week 4.',
      );

      final roundTripped = Routine.fromJson(routine.toJson());
      expect(roundTripped.notes, routine.notes);
      expect(roundTripped, routine);
    });

    test('notes defaults to null when absent', () {
      final json = TestRoutineFactory.create();
      json.remove('notes');

      final routine = Routine.fromJson(json);

      expect(routine.notes, isNull);
      expect(routine.toJson()['notes'], isNull);
    });

    test('fromJson matches realistic seed.sql JSONB structure', () {
      // Simulates what Supabase returns for a workout_templates row
      final json = {
        'id': 'tmpl-push-001',
        'user_id': null,
        'name': 'Push Day (Beginner)',
        'is_default': true,
        'exercises': [
          {
            'exercise_id': 'ex-bench-press',
            'set_configs': [
              {'target_reps': 10, 'rest_seconds': 90},
              {'target_reps': 10, 'rest_seconds': 90},
              {'target_reps': 10, 'rest_seconds': 90},
            ],
          },
          {
            'exercise_id': 'ex-ohp',
            'set_configs': [
              {'target_reps': 8, 'rest_seconds': 120},
              {'target_reps': 8, 'rest_seconds': 120},
            ],
          },
        ],
        'created_at': '2026-01-01T00:00:00Z',
      };

      final routine = Routine.fromJson(json);

      expect(routine.id, 'tmpl-push-001');
      expect(routine.userId, isNull);
      expect(routine.name, 'Push Day (Beginner)');
      expect(routine.isDefault, true);
      expect(routine.exercises, hasLength(2));
      expect(routine.exercises[0].setConfigs, hasLength(3));
      expect(routine.exercises[0].setConfigs[0].targetReps, 10);
      expect(routine.exercises[0].setConfigs[0].restSeconds, 90);
      expect(routine.exercises[1].setConfigs, hasLength(2));
      expect(routine.exercises[1].setConfigs[0].targetReps, 8);
    });
  });
}
