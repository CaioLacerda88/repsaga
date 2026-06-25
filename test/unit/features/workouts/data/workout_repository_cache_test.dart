// Phase 15f Stage 6: history cache keys are now `'<userId>:<locale>'` and
// the repo resolves localized exercise names via a follow-up batch RPC on
// `ExerciseRepository.getExercisesByIds`. Tests stub that with mocktail and
// pass `locale: 'en'` everywhere unless verifying multi-locale isolation.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/local_storage/cache_service.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:repsaga/features/exercises/data/exercise_repository.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';

import '../../../../fixtures/test_factories.dart';
import '../../../_helpers/fake_supabase.dart';

class _MockExerciseRepository extends Mock implements ExerciseRepository {}

void main() {
  late Directory tempDir;
  late CacheService cache;
  late Box<dynamic> historyBox;
  late Box<dynamic> lastSetsBox;
  late _MockExerciseRepository mockExerciseRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('workout_cache_test_');
    Hive.init(tempDir.path);
    historyBox = await Hive.openBox<dynamic>(HiveService.workoutHistoryCache);
    lastSetsBox = await Hive.openBox<dynamic>(HiveService.lastSetsCache);
    cache = const CacheService();
    mockExerciseRepo = _MockExerciseRepository();
    // Default: batch returns an empty map — fine for tests that only check
    // workout shape / cache plumbing without asserting on exercise summaries.
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

  group('WorkoutRepository cache - getWorkoutHistory', () {
    // The cache is only active when offset==0 AND limit>=50 (the "refresh
    // pass"). Default UI fetches (limit=20) intentionally skip the cache to
    // avoid a small fetch overwriting a richer 50-item cache entry.

    test('cache key is locale-prefixed (`<userId>:<locale>`)', () async {
      final workoutData = [
        {
          ...TestWorkoutFactory.create(id: 'w-1'),
          'workout_exercises': <dynamic>[],
        },
      ];
      final client = FakeSupabaseClient(FakeQueryBuilder(data: workoutData));
      final repo = WorkoutRepository(client, cache, mockExerciseRepo);

      await repo.getWorkoutHistory('user-001', locale: 'en', limit: 50);

      // Cache key now includes the locale.
      expect(
        historyBox.get('user-001:en'),
        isNotNull,
        reason: 'cache key must be `<userId>:<locale>`',
      );
      expect(
        historyBox.get('user-001'),
        isNull,
        reason: 'legacy key without locale must not be written',
      );
    });

    test('cache preserves exerciseSummary through roundtrip', () async {
      // Pre-populate cache with a workout that has _exercise_summary, under
      // the locale-prefixed key.
      final workoutJson = TestWorkoutFactory.create(
        id: 'w-1',
        name: 'Push Day',
      );
      workoutJson['_exercise_summary'] = 'Bench Press, Squat';
      await historyBox.put('user-001:en', jsonEncode([workoutJson]));

      // Create repo with a failing client to force cache read.
      final client = FakeSupabaseClient(
        FakeQueryBuilder(error: Exception('offline')),
      );
      final repo = WorkoutRepository(client, cache, mockExerciseRepo);

      // Must use limit >= 50 to trigger the cache path.
      final result = await repo.getWorkoutHistory(
        'user-001',
        locale: 'en',
        limit: 50,
      );

      expect(result, hasLength(1));
      expect(result[0].id, 'w-1');
      expect(result[0].exerciseSummary, 'Bench Press, Squat');
    });

    test('does not cache when limit < 50 (default UI fetch)', () async {
      final workoutData = [
        {
          ...TestWorkoutFactory.create(id: 'w-1'),
          'workout_exercises': <dynamic>[],
        },
      ];
      final client = FakeSupabaseClient(FakeQueryBuilder(data: workoutData));
      final repo = WorkoutRepository(client, cache, mockExerciseRepo);

      // Default limit (20) — must NOT write to cache.
      await repo.getWorkoutHistory('user-001', locale: 'en');

      final raw = historyBox.get('user-001:en');
      expect(raw, isNull, reason: 'limit < 50 must not write to cache');
    });

    test('does not cache when offset > 0', () async {
      final workoutData = [
        {
          ...TestWorkoutFactory.create(id: 'w-1'),
          'workout_exercises': <dynamic>[],
        },
      ];
      final client = FakeSupabaseClient(FakeQueryBuilder(data: workoutData));
      final repo = WorkoutRepository(client, cache, mockExerciseRepo);

      // offset > 0 — must NOT cache even with limit >= 50.
      await repo.getWorkoutHistory(
        'user-001',
        locale: 'en',
        limit: 50,
        offset: 5,
      );

      final raw = historyBox.get('user-001:en');
      expect(raw, isNull, reason: 'offset > 0 must not write to cache');
    });

    test('network failure returns cached data (limit >= 50)', () async {
      final workoutJson = TestWorkoutFactory.create(id: 'w-cached');
      await historyBox.put('user-001:en', jsonEncode([workoutJson]));

      final client = FakeSupabaseClient(
        FakeQueryBuilder(error: Exception('offline')),
      );
      final repo = WorkoutRepository(client, cache, mockExerciseRepo);

      // Must use limit >= 50 to trigger the cache path.
      final result = await repo.getWorkoutHistory(
        'user-001',
        locale: 'en',
        limit: 50,
      );

      expect(result, hasLength(1));
      expect(result[0].id, 'w-cached');
    });

    test('en cache does not satisfy pt request', () async {
      // Seed only the en cache.
      final workoutJson = TestWorkoutFactory.create(id: 'w-en-only');
      await historyBox.put('user-001:en', jsonEncode([workoutJson]));

      // Network fails — pt request must NOT pick up en-cached data.
      final client = FakeSupabaseClient(
        FakeQueryBuilder(error: Exception('offline')),
      );
      final repo = WorkoutRepository(client, cache, mockExerciseRepo);

      await expectLater(
        repo.getWorkoutHistory('user-001', locale: 'pt', limit: 50),
        throwsA(isA<Exception>()),
        reason: 'pt request must not pick up en-cached data',
      );
    });

    test('rethrows when no cache and network fails', () async {
      final client = FakeSupabaseClient(
        FakeQueryBuilder(error: Exception('offline')),
      );
      final repo = WorkoutRepository(client, cache, mockExerciseRepo);

      // With limit >= 50, cache is checked but empty → must rethrow.
      await expectLater(
        repo.getWorkoutHistory('user-001', locale: 'en', limit: 50),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'rethrows even with default limit when no cache (limit < 50 bypasses cache)',
      () async {
        final client = FakeSupabaseClient(
          FakeQueryBuilder(error: Exception('offline')),
        );
        final repo = WorkoutRepository(client, cache, mockExerciseRepo);

        // Default limit (20) — cache is bypassed entirely, error always propagates.
        await expectLater(
          repo.getWorkoutHistory('user-001', locale: 'en'),
          throwsA(isA<Exception>()),
        );
      },
    );

    test(
      'fresh data is written and readable on subsequent offline call',
      () async {
        final workoutData = [
          {
            ...TestWorkoutFactory.create(id: 'w-written'),
            'workout_exercises': <dynamic>[],
          },
        ];
        // First call: network succeeds and writes to cache (limit >= 50).
        final onlineClient = FakeSupabaseClient(
          FakeQueryBuilder(data: workoutData),
        );
        await WorkoutRepository(
          onlineClient,
          cache,
          mockExerciseRepo,
        ).getWorkoutHistory('user-001', locale: 'en', limit: 50);

        // Second call: network fails — must return data from cache written above.
        final offlineClient = FakeSupabaseClient(
          FakeQueryBuilder(error: Exception('offline')),
        );
        final result = await WorkoutRepository(
          offlineClient,
          cache,
          mockExerciseRepo,
        ).getWorkoutHistory('user-001', locale: 'en', limit: 50);

        expect(result, hasLength(1));
        expect(result[0].id, 'w-written');
      },
    );

    // -----------------------------------------------------------------------
    // Phase 15f Stage 6 spec §12.2: the two-query merge in getWorkoutHistory
    // must batch the secondary exercise lookup. With N workouts each
    // referencing M exercises, exactly ONE call to
    // ExerciseRepository.getExercisesByIds is allowed, with a deduplicated
    // union of the IDs. Anything else regresses to N+1.
    // -----------------------------------------------------------------------
    test('getExercisesByIds called exactly once with deduplicated ids '
        '(N+1 protection, spec §12.2)', () async {
      // Five workouts, each with two workout_exercises. Some exercise IDs
      // repeat across workouts — the deduplicated union should be five IDs.
      // If the repo issued one fetch per workout (or per workout_exercise),
      // we'd see called(5) or called(10) instead of called(1).
      final workoutData = [
        {
          ...TestWorkoutFactory.create(id: 'w-1'),
          'workout_exercises': [
            {'order': 0, 'exercise_id': 'ex-A'},
            {'order': 1, 'exercise_id': 'ex-B'},
          ],
        },
        {
          ...TestWorkoutFactory.create(id: 'w-2'),
          'workout_exercises': [
            {'order': 0, 'exercise_id': 'ex-B'}, // dup with w-1
            {'order': 1, 'exercise_id': 'ex-C'},
          ],
        },
        {
          ...TestWorkoutFactory.create(id: 'w-3'),
          'workout_exercises': [
            {'order': 0, 'exercise_id': 'ex-A'}, // dup with w-1
            {'order': 1, 'exercise_id': 'ex-D'},
          ],
        },
        {
          ...TestWorkoutFactory.create(id: 'w-4'),
          'workout_exercises': [
            {'order': 0, 'exercise_id': 'ex-D'}, // dup with w-3
            {'order': 1, 'exercise_id': 'ex-E'},
          ],
        },
        {
          ...TestWorkoutFactory.create(id: 'w-5'),
          'workout_exercises': [
            {'order': 0, 'exercise_id': 'ex-C'}, // dup with w-2
            {'order': 1, 'exercise_id': 'ex-E'}, // dup with w-4
          ],
        },
      ];
      final client = FakeSupabaseClient(FakeQueryBuilder(data: workoutData));
      final repo = WorkoutRepository(client, cache, mockExerciseRepo);

      await repo.getWorkoutHistory('user-001', locale: 'en', limit: 50);

      // Exactly ONE batched call to getExercisesByIds, regardless of the
      // 5 workouts × 2 exercises = 10 workout_exercise rows.
      final captured =
          verify(
                () => mockExerciseRepo.getExercisesByIds(
                  locale: 'en',
                  userId: 'user-001',
                  ids: captureAny(named: 'ids'),
                ),
              ).captured.single
              as List<String>;

      // The captured ids must be the deduplicated union — five distinct
      // exercises across the page.
      expect(
        captured.toSet(),
        {'ex-A', 'ex-B', 'ex-C', 'ex-D', 'ex-E'},
        reason:
            'getExercisesByIds must receive the deduplicated union of '
            'exercise IDs across all workouts in the page',
      );
    });
  });

  group('WorkoutRepository cache - getLastWorkoutSets', () {
    test('cache roundtrip works', () async {
      // Pre-populate cache with sets data.
      final setsData = {
        'exercise-001': [
          TestSetFactory.create(id: 'set-1', reps: 10, weight: 80.0),
          TestSetFactory.create(
            id: 'set-2',
            setNumber: 2,
            reps: 8,
            weight: 85.0,
          ),
        ],
      };
      const key = 'exercise-001';
      await lastSetsBox.put(key, jsonEncode(setsData));

      // Create repo with a failing client to force cache read.
      final client = FakeSupabaseClient(
        FakeQueryBuilder(error: Exception('offline')),
      );
      final repo = WorkoutRepository(client, cache, mockExerciseRepo);

      final result = await repo.getLastWorkoutSets(['exercise-001']);

      expect(result.containsKey('exercise-001'), isTrue);
      expect(result['exercise-001'], hasLength(2));
      expect(result['exercise-001']![0].reps, 10);
      expect(result['exercise-001']![0].weight, 80.0);
      expect(result['exercise-001']![1].reps, 8);
    });

    test('network failure returns cached data', () async {
      final setsData = {
        'ex-1': [TestSetFactory.create(id: 's-1', reps: 5, weight: 100.0)],
      };
      await lastSetsBox.put('ex-1', jsonEncode(setsData));

      final client = FakeSupabaseClient(
        FakeQueryBuilder(error: Exception('offline')),
      );
      final repo = WorkoutRepository(client, cache, mockExerciseRepo);

      final result = await repo.getLastWorkoutSets(['ex-1']);

      expect(result['ex-1'], hasLength(1));
      expect(result['ex-1']![0].weight, 100.0);
    });

    test(
      'returns empty map immediately for empty exercise IDs list (no cache interaction)',
      () async {
        // No cache seeded, no network call expected.
        final client = FakeSupabaseClient(FakeQueryBuilder());
        final repo = WorkoutRepository(client, cache, mockExerciseRepo);

        final result = await repo.getLastWorkoutSets([]);

        expect(result, isEmpty);
        // Verify nothing was written to cache.
        expect(lastSetsBox.isEmpty, isTrue);
      },
    );

    test('rethrows when no cache and network fails', () async {
      final client = FakeSupabaseClient(
        FakeQueryBuilder(error: Exception('offline')),
      );
      final repo = WorkoutRepository(client, cache, mockExerciseRepo);

      await expectLater(
        repo.getLastWorkoutSets(['ex-missing']),
        throwsA(isA<Exception>()),
      );
    });

    test('cache key is sorted IDs — order-independent lookup', () async {
      // Pre-populate using the sorted key ("ex-1,ex-2").
      final setsData = {
        'ex-1': [TestSetFactory.create(id: 's-1', reps: 5, weight: 100.0)],
        'ex-2': [TestSetFactory.create(id: 's-2', reps: 8, weight: 60.0)],
      };
      await lastSetsBox.put('ex-1,ex-2', jsonEncode(setsData));

      final client = FakeSupabaseClient(
        FakeQueryBuilder(error: Exception('offline')),
      );
      final repo = WorkoutRepository(client, cache, mockExerciseRepo);

      // Pass IDs in reverse order — repo sorts them to build the cache key.
      final result = await repo.getLastWorkoutSets(['ex-2', 'ex-1']);

      expect(result.containsKey('ex-1'), isTrue);
      expect(result.containsKey('ex-2'), isTrue);
    });

    test('picks the most-recent session when PostgREST returns parent rows '
        'out of finished_at order (seed 0kg bug)', () async {
      // The canonical bug: `.order(referencedTable: "workouts")` sorts the
      // EMBEDDED to-one resource, not the top-level workout_exercises rows.
      // So PostgREST hands back parent rows in PK/insertion order, and the
      // FakeQueryBuilder mirrors that by returning `data` verbatim from
      // `.order(...)`. Seed an OLD 0kg session FIRST and the real most-recent
      // 60kg session LATER — exactly the live failure (2026-04-06 @ 0kg
      // returned before 2026-06-24 @ 60kg). The repo must sort client-side
      // before the `seen` dedup and pick the 60kg session.
      final rows = [
        {
          'exercise_id': 'ex-1',
          'workouts': {'finished_at': '2026-04-06T10:00:00Z'},
          'sets': [TestSetFactory.create(id: 'old-set', reps: 10, weight: 0.0)],
        },
        {
          'exercise_id': 'ex-1',
          'workouts': {'finished_at': '2026-06-24T10:00:00Z'},
          'sets': [
            TestSetFactory.create(id: 'recent-set', reps: 8, weight: 60.0),
          ],
        },
        {
          'exercise_id': 'ex-1',
          'workouts': {'finished_at': '2026-05-15T10:00:00Z'},
          'sets': [TestSetFactory.create(id: 'mid-set', reps: 9, weight: 40.0)],
        },
      ];

      final client = FakeSupabaseClient(FakeQueryBuilder(data: rows));
      final repo = WorkoutRepository(client, cache, mockExerciseRepo);

      final result = await repo.getLastWorkoutSets(['ex-1']);

      expect(result['ex-1'], hasLength(1));
      expect(
        result['ex-1']!.single.weight,
        60.0,
        reason:
            'must seed the most-recent (2026-06-24 @ 60kg) session, '
            'not the arbitrarily-first 0kg row',
      );
    });

    test('per-exercise dedup keeps each exercise own most-recent session '
        '(split-agnostic)', () async {
      // Two exercises interleaved, each out of finished_at order. The dedup
      // must independently pick the most-recent session PER exercise.
      final rows = [
        {
          'exercise_id': 'ex-1',
          'workouts': {'finished_at': '2026-01-01T10:00:00Z'},
          'sets': [TestSetFactory.create(id: 'a', reps: 5, weight: 20.0)],
        },
        {
          'exercise_id': 'ex-2',
          'workouts': {'finished_at': '2026-06-20T10:00:00Z'},
          'sets': [TestSetFactory.create(id: 'b', reps: 6, weight: 80.0)],
        },
        {
          'exercise_id': 'ex-1',
          'workouts': {'finished_at': '2026-06-22T10:00:00Z'},
          'sets': [TestSetFactory.create(id: 'c', reps: 7, weight: 90.0)],
        },
        {
          'exercise_id': 'ex-2',
          'workouts': {'finished_at': '2026-02-02T10:00:00Z'},
          'sets': [TestSetFactory.create(id: 'd', reps: 4, weight: 30.0)],
        },
      ];

      final client = FakeSupabaseClient(FakeQueryBuilder(data: rows));
      final repo = WorkoutRepository(client, cache, mockExerciseRepo);

      final result = await repo.getLastWorkoutSets(['ex-1', 'ex-2']);

      expect(
        result['ex-1']!.single.weight,
        90.0,
        reason: 'ex-1 most recent is 2026-06-22 @ 90kg',
      );
      expect(
        result['ex-2']!.single.weight,
        80.0,
        reason: 'ex-2 most recent is 2026-06-20 @ 80kg',
      );
    });

    test('rows with null/missing finished_at sort last (defensive)', () async {
      final rows = [
        {
          'exercise_id': 'ex-1',
          'workouts': {'finished_at': null},
          'sets': [TestSetFactory.create(id: 'null-row', reps: 1, weight: 0.0)],
        },
        {
          'exercise_id': 'ex-1',
          'workouts': {'finished_at': '2026-06-24T10:00:00Z'},
          'sets': [TestSetFactory.create(id: 'real', reps: 8, weight: 70.0)],
        },
      ];

      final client = FakeSupabaseClient(FakeQueryBuilder(data: rows));
      final repo = WorkoutRepository(client, cache, mockExerciseRepo);

      final result = await repo.getLastWorkoutSets(['ex-1']);

      expect(
        result['ex-1']!.single.weight,
        70.0,
        reason: 'the dated session wins over the null-finished_at row',
      );
    });
  });
}
