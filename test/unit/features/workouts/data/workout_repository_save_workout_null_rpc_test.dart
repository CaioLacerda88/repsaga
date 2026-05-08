import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/exceptions/app_exception.dart' as app;
import 'package:repsaga/core/local_storage/cache_service.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:repsaga/features/exercises/data/exercise_repository.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:repsaga/features/workouts/models/exercise_set.dart';
import 'package:repsaga/features/workouts/models/set_type.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/models/workout_exercise.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// BUG-004: `save_workout` RPC can return `null` when Postgres hits a
/// `RAISE EXCEPTION` inside a `DO` block (or any partial-commit error path).
/// The previous code did `Workout.fromJson(result as Map<String, dynamic>)`
/// — that cast threw the cryptic
/// `type 'Null' is not a subtype of type 'Map<String, dynamic>'` error and
/// trapped the user in a state where the workout was never durable but the
/// retry loop couldn't classify the failure.
///
/// The fix throws a typed [app.DatabaseException] with code `rpc_null_result`
/// so the offline-queue retry loop and the [SyncErrorMapper] can classify
/// it.

/// Minimal awaitable fake for the `PostgrestFilterBuilder` returned by
/// `SupabaseClient.rpc(...)`. The real builder implements `Future.then` and
/// `Future.timeout` internally (the production code chains `.timeout(30s)`
/// on the rpc Future per AW-EX-D-US1-04 guard); we mirror both so
/// `await client.rpc(...).timeout(...)` resolves to whatever value we
/// specify under test.
class _FakeRpcBuilder extends Fake
    implements supabase.PostgrestFilterBuilder<dynamic> {
  _FakeRpcBuilder(this._value);

  final dynamic _value;

  @override
  Future<S> then<S>(
    FutureOr<S> Function(dynamic) onValue, {
    Function? onError,
  }) {
    return Future.value(_value).then<S>(onValue, onError: onError);
  }

  @override
  Future<dynamic> timeout(
    Duration timeLimit, {
    FutureOr<dynamic> Function()? onTimeout,
  }) {
    // Resolve immediately with the canned value — these tests inspect the
    // post-RPC null-guard, not the timeout. A real timeout test lives in
    // active_workout_notifier_finish_classification_test.dart.
    return Future.value(_value);
  }
}

class _MockSupabaseClient extends Mock implements supabase.SupabaseClient {}

class _MockExerciseRepository extends Mock implements ExerciseRepository {}

void main() {
  late Directory tempDir;
  late CacheService cache;
  late _MockSupabaseClient mockClient;
  late _MockExerciseRepository mockExerciseRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('save_workout_null_rpc_');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>(HiveService.workoutHistoryCache);
    await Hive.openBox<dynamic>(HiveService.lastSetsCache);
    cache = const CacheService();

    mockClient = _MockSupabaseClient();
    mockExerciseRepo = _MockExerciseRepository();

    when(
      () => mockExerciseRepo.getExercisesByIds(
        locale: any(named: 'locale'),
        userId: any(named: 'userId'),
        ids: any(named: 'ids'),
      ),
    ).thenAnswer((_) async => <String, Exercise>{});
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  Workout buildWorkout() {
    return Workout(
      id: 'w-null-rpc',
      userId: 'user-1',
      name: 'Push Day',
      startedAt: DateTime.utc(2026, 4, 17, 10, 0, 0),
      finishedAt: DateTime.utc(2026, 4, 17, 11, 0, 0),
      durationSeconds: 3600,
      isActive: false,
      createdAt: DateTime.utc(2026, 4, 17, 11, 0, 0),
    );
  }

  WorkoutExercise buildWorkoutExercise() {
    return const WorkoutExercise(
      id: 'we-1',
      workoutId: 'w-null-rpc',
      exerciseId: 'ex-1',
      order: 1,
    );
  }

  ExerciseSet buildSet() {
    return ExerciseSet(
      id: 's-1',
      workoutExerciseId: 'we-1',
      setNumber: 1,
      reps: 5,
      weight: 100,
      setType: SetType.working,
      isCompleted: true,
      createdAt: DateTime.utc(2026, 4, 17, 10, 30, 0),
    );
  }

  test(
    'BUG-004: throws app.DatabaseException(rpc_null_result) when RPC returns null',
    () async {
      // Simulate Postgres returning null from the save_workout RPC.
      when(
        () => mockClient.rpc(any(), params: any(named: 'params')),
      ).thenAnswer((_) => _FakeRpcBuilder(null));

      final repo = WorkoutRepository(mockClient, cache, mockExerciseRepo);

      await expectLater(
        () => repo.saveWorkout(
          workout: buildWorkout(),
          exercises: [buildWorkoutExercise()],
          sets: [buildSet()],
        ),
        throwsA(
          isA<app.DatabaseException>().having(
            (e) => e.code,
            'code',
            'rpc_null_result',
          ),
        ),
      );
    },
  );

  test(
    'BUG-004: throws app.DatabaseException when RPC returns a non-Map type',
    () async {
      // Defensive: any non-Map result (list, string, int) must also be
      // rejected — the cast in Workout.fromJson would throw a TypeError
      // otherwise, which is exactly the symptom we are guarding against.
      when(
        () => mockClient.rpc(any(), params: any(named: 'params')),
      ).thenAnswer((_) => _FakeRpcBuilder(<dynamic>['unexpected list shape']));

      final repo = WorkoutRepository(mockClient, cache, mockExerciseRepo);

      await expectLater(
        () => repo.saveWorkout(
          workout: buildWorkout(),
          exercises: const [],
          sets: const [],
        ),
        throwsA(isA<app.DatabaseException>()),
      );
    },
  );
}
