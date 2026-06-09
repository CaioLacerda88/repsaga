// Q1 (notes-edit-after): unit coverage for the `updateWorkoutNotes` path that
// lets the History detail screen edit a past workout's free-text notes.
//
// Behavior pinned:
//   * the persisted UPDATE payload carries the exact `notes` value (round-trip),
//   * the write is owner-scoped (`user_id` filter applied),
//   * a clear (null) is persisted as a real null sentinel,
//   * a Postgrest failure is mapped to the domain `DatabaseException` (not a
//     raw PostgrestException) via BaseRepository.mapException.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/exceptions/app_exception.dart';
import 'package:repsaga/core/local_storage/cache_service.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:repsaga/features/exercises/data/exercise_repository.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../_helpers/fake_supabase.dart';

class _MockExerciseRepository extends Mock implements ExerciseRepository {}

void main() {
  late Directory tempDir;
  late CacheService cache;
  late _MockExerciseRepository mockExerciseRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('workout_notes_test_');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>(HiveService.workoutHistoryCache);
    await Hive.openBox<dynamic>(HiveService.lastSetsCache);
    cache = const CacheService();
    mockExerciseRepo = _MockExerciseRepository();
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('WorkoutRepository.updateWorkoutNotes', () {
    test('persists the notes value scoped to the owning user', () async {
      final builder = FakeQueryBuilder();
      final repo = WorkoutRepository(
        FakeSupabaseClient(builder),
        cache,
        mockExerciseRepo,
      );

      await repo.updateWorkoutNotes(
        'w-42',
        notes: 'Felt strong on the top set',
        userId: 'user-001',
      );

      // The exact value round-trips into the UPDATE payload.
      expect(builder.lastUpdateValues, {'notes': 'Felt strong on the top set'});
      // Owner-scoped: both the workout id and the user id are applied as
      // equality filters (RLS defence-in-depth, mirrors discardWorkout).
      expect(builder.calledMethods, contains('update'));
      expect(builder.calledMethods, contains('eq:id=w-42'));
      expect(builder.calledMethods, contains('eq:user_id=user-001'));
    });

    test('persists null to clear an existing note', () async {
      final builder = FakeQueryBuilder();
      final repo = WorkoutRepository(
        FakeSupabaseClient(builder),
        cache,
        mockExerciseRepo,
      );

      await repo.updateWorkoutNotes('w-42', notes: null, userId: 'user-001');

      expect(builder.lastUpdateValues, {'notes': null});
    });

    test('maps a Postgrest failure to a domain DatabaseException', () async {
      final builder = FakeQueryBuilder(
        error: const supabase.PostgrestException(
          message: 'permission denied for table workouts',
          code: '42501',
        ),
      );
      final repo = WorkoutRepository(
        FakeSupabaseClient(builder),
        cache,
        mockExerciseRepo,
      );

      // The raw PostgrestException must not escape the repository layer —
      // BaseRepository.mapException transforms it into the sealed domain type.
      await expectLater(
        repo.updateWorkoutNotes('w-42', notes: 'x', userId: 'user-001'),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
