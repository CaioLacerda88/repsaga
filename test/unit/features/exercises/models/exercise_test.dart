import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';

import '../../../../fixtures/test_factories.dart';

// ignore_for_file: lines_longer_than_80_chars

void main() {
  group('MuscleGroup', () {
    test('displayName capitalizes first letter for all values', () {
      for (final group in MuscleGroup.values) {
        expect(group.displayName[0], group.displayName[0].toUpperCase());
        expect(group.displayName.length, greaterThan(1));
      }
    });

    test('fromString round-trips all values', () {
      for (final group in MuscleGroup.values) {
        expect(MuscleGroup.fromString(group.name), group);
      }
    });

    test('fromString throws StateError for invalid value', () {
      expect(
        () => MuscleGroup.fromString('invalid'),
        throwsA(isA<StateError>()),
      );
    });

    // §17.0d — enum migrated from IconData to String svgIcon.
    // §17.0e — svgIcon is now a v3-silhouette asset path, no longer inline XML.
    test('svgIcon returns a v3-silhouette asset path for every value', () {
      for (final group in MuscleGroup.values) {
        final path = group.svgIcon;
        expect(
          path,
          isNotEmpty,
          reason: '${group.name}.svgIcon must not be empty',
        );
        expect(
          path,
          startsWith('assets/icons/v3-silhouette/'),
          reason:
              '${group.name}.svgIcon must resolve to the v3-silhouette pack',
        );
        expect(
          path,
          endsWith('.svg'),
          reason: '${group.name}.svgIcon must point at a .svg asset',
        );
      }
    });
  });

  group('EquipmentType', () {
    test('displayName capitalizes first letter for all values', () {
      for (final type in EquipmentType.values) {
        expect(type.displayName[0], type.displayName[0].toUpperCase());
        expect(type.displayName.length, greaterThan(1));
      }
    });

    test('fromString round-trips all values', () {
      for (final type in EquipmentType.values) {
        expect(EquipmentType.fromString(type.name), type);
      }
    });

    test('fromString throws StateError for invalid value', () {
      expect(
        () => EquipmentType.fromString('invalid'),
        throwsA(isA<StateError>()),
      );
    });

    // §17.0d — enum migrated from IconData to String svgIcon.
    // §17.0e — svgIcon is now a v3-silhouette asset path, no longer inline XML.
    test('svgIcon returns a v3-silhouette asset path for every value', () {
      for (final type in EquipmentType.values) {
        final path = type.svgIcon;
        expect(
          path,
          isNotEmpty,
          reason: '${type.name}.svgIcon must not be empty',
        );
        expect(
          path,
          startsWith('assets/icons/v3-silhouette/'),
          reason: '${type.name}.svgIcon must resolve to the v3-silhouette pack',
        );
        expect(
          path,
          endsWith('.svg'),
          reason: '${type.name}.svgIcon must point at a .svg asset',
        );
      }
    });
  });

  group('Exercise', () {
    test('fromJson parses complete data including image URLs', () {
      final json = TestExerciseFactory.create(
        userId: 'user-001',
        deletedAt: '2026-02-01T00:00:00Z',
        imageStartUrl: 'https://example.com/start.jpg',
        imageEndUrl: 'https://example.com/end.jpg',
      );

      final exercise = Exercise.fromJson(json);

      expect(exercise.id, 'exercise-001');
      expect(exercise.name, 'Bench Press');
      expect(exercise.muscleGroup, MuscleGroup.chest);
      expect(exercise.equipmentType, EquipmentType.barbell);
      expect(exercise.isDefault, true);
      expect(exercise.userId, 'user-001');
      expect(exercise.deletedAt, DateTime.parse('2026-02-01T00:00:00Z'));
      expect(exercise.imageStartUrl, 'https://example.com/start.jpg');
      expect(exercise.imageEndUrl, 'https://example.com/end.jpg');
    });

    test('fromJson handles null optional fields', () {
      final json = TestExerciseFactory.create();

      final exercise = Exercise.fromJson(json);

      expect(exercise.userId, isNull);
      expect(exercise.deletedAt, isNull);
      expect(exercise.imageStartUrl, isNull);
      expect(exercise.imageEndUrl, isNull);
    });

    test('fromJson handles asymmetric image URLs', () {
      final json = TestExerciseFactory.create(
        imageStartUrl: 'https://example.com/start.jpg',
      );

      final exercise = Exercise.fromJson(json);

      expect(exercise.imageStartUrl, 'https://example.com/start.jpg');
      expect(exercise.imageEndUrl, isNull);
    });

    test('toJson round-trip preserves data', () {
      final originalJson = TestExerciseFactory.create(
        userId: 'user-001',
        imageStartUrl: 'https://example.com/start.jpg',
        imageEndUrl: 'https://example.com/end.jpg',
      );
      final exercise = Exercise.fromJson(originalJson);
      final roundTripped = Exercise.fromJson(exercise.toJson());

      expect(roundTripped, exercise);
    });

    test('fromJson parses description and formTips when present', () {
      final json = TestExerciseFactory.create(
        description: 'A hip-hinge movement targeting the hamstrings.',
        formTips: 'Keep bar close\nHinge at hips\nSqueeze glutes',
      );

      final exercise = Exercise.fromJson(json);

      expect(
        exercise.description,
        'A hip-hinge movement targeting the hamstrings.',
      );
      expect(
        exercise.formTips,
        'Keep bar close\nHinge at hips\nSqueeze glutes',
      );
    });

    test('fromJson sets description and formTips to null when absent', () {
      final json = TestExerciseFactory.create();

      final exercise = Exercise.fromJson(json);

      expect(exercise.description, isNull);
      expect(exercise.formTips, isNull);
    });

    test('toJson round-trip preserves description and formTips', () {
      final json = TestExerciseFactory.create(
        description: 'Targets chest and anterior deltoids.',
        formTips: 'Full range of motion\nControl the descent',
      );
      final exercise = Exercise.fromJson(json);
      final roundTripped = Exercise.fromJson(exercise.toJson());

      expect(roundTripped.description, exercise.description);
      expect(roundTripped.formTips, exercise.formTips);
      expect(roundTripped, exercise);
    });

    test('toJson round-trip preserves null description and formTips', () {
      final json = TestExerciseFactory.create();
      final exercise = Exercise.fromJson(json);
      final roundTripped = Exercise.fromJson(exercise.toJson());

      expect(roundTripped.description, isNull);
      expect(roundTripped.formTips, isNull);
    });

    test('fromJson parses exercise with description but no formTips', () {
      final json = TestExerciseFactory.create(
        description: 'A compound push movement.',
      );

      final exercise = Exercise.fromJson(json);

      expect(exercise.description, 'A compound push movement.');
      expect(exercise.formTips, isNull);
    });

    test('fromJson parses exercise with formTips but no description', () {
      final json = TestExerciseFactory.create(
        formTips: 'Keep elbows at 45 degrees\nDrive through heels',
      );

      final exercise = Exercise.fromJson(json);

      expect(exercise.description, isNull);
      expect(
        exercise.formTips,
        'Keep elbows at 45 degrees\nDrive through heels',
      );
    });

    // -----------------------------------------------------------------
    // Phase 24c — usesBodyweightLoad
    //
    // The 20 curated bodyweight exercises (pull-ups, dips, push-ups,
    // pistol squats, etc.) get `uses_bodyweight_load = TRUE` server-side.
    // Every other exercise (loaded barbell/dumbbell, isolation, cardio,
    // isometrics) stays FALSE. The Dart default is FALSE so legacy cache
    // rows that pre-date the column deserialize safely until the next
    // network fetch repopulates with the authoritative server flag.
    // -----------------------------------------------------------------
    group('usesBodyweightLoad (Phase 24c)', () {
      test(
        'defaults to false when uses_bodyweight_load is absent from JSON',
        () {
          final json = TestExerciseFactory.create()
            ..remove('uses_bodyweight_load');

          final exercise = Exercise.fromJson(json);

          expect(exercise.usesBodyweightLoad, isFalse);
        },
      );

      test('defaults to false when uses_bodyweight_load is null in JSON', () {
        final json = TestExerciseFactory.create()
          ..['uses_bodyweight_load'] = null;

        final exercise = Exercise.fromJson(json);

        expect(exercise.usesBodyweightLoad, isFalse);
      });

      test('parses true value from JSON', () {
        final json = TestExerciseFactory.create(
          name: 'Pull-up',
          muscleGroup: 'back',
          equipmentType: 'bodyweight',
          slug: 'pull_up',
          usesBodyweightLoad: true,
        );

        final exercise = Exercise.fromJson(json);

        expect(exercise.usesBodyweightLoad, isTrue);
      });

      test('parses false value from JSON', () {
        final json = TestExerciseFactory.create(usesBodyweightLoad: false);

        final exercise = Exercise.fromJson(json);

        expect(exercise.usesBodyweightLoad, isFalse);
      });

      test('toJson includes uses_bodyweight_load when true', () {
        final json = TestExerciseFactory.create(usesBodyweightLoad: true);
        final exercise = Exercise.fromJson(json);

        final out = exercise.toJson();

        expect(out['uses_bodyweight_load'], isTrue);
      });

      test('toJson includes uses_bodyweight_load when false', () {
        final json = TestExerciseFactory.create(usesBodyweightLoad: false);
        final exercise = Exercise.fromJson(json);

        final out = exercise.toJson();

        expect(out['uses_bodyweight_load'], isFalse);
      });

      test('toJson round-trip preserves usesBodyweightLoad=true', () {
        final json = TestExerciseFactory.create(
          name: 'Dips',
          muscleGroup: 'chest',
          equipmentType: 'bodyweight',
          slug: 'dips',
          usesBodyweightLoad: true,
        );
        final exercise = Exercise.fromJson(json);
        final roundTripped = Exercise.fromJson(exercise.toJson());

        expect(roundTripped.usesBodyweightLoad, isTrue);
        expect(roundTripped, exercise);
      });

      test('toJson round-trip preserves usesBodyweightLoad=false', () {
        final json = TestExerciseFactory.create();
        final exercise = Exercise.fromJson(json);
        final roundTripped = Exercise.fromJson(exercise.toJson());

        expect(roundTripped.usesBodyweightLoad, isFalse);
      });

      test(
        'two exercises differing only in usesBodyweightLoad are not equal',
        () {
          final loaded = Exercise.fromJson(
            TestExerciseFactory.create(usesBodyweightLoad: false),
          );
          final bodyweight = Exercise.fromJson(
            TestExerciseFactory.create(usesBodyweightLoad: true),
          );

          expect(loaded, isNot(equals(bodyweight)));
        },
      );
    });
  });
}
