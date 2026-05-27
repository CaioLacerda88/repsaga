// Phase 15f Stage 6: routine cache keys are now `'<userId>:<locale>'` and the
// repo resolves exercise references via `ExerciseRepository.getExercisesByIds`
// (mocked here with mocktail). Tests pass `locale: 'en'` everywhere unless
// verifying multi-locale isolation.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/local_storage/cache_service.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:repsaga/features/exercises/data/exercise_repository.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/routines/data/routine_repository.dart';
import 'package:repsaga/features/routines/data/workout_template_translation_resolver.dart';

import '../../../../fixtures/test_factories.dart';
import '../../../_helpers/fake_supabase.dart';

class _MockExerciseRepository extends Mock implements ExerciseRepository {}

class _MockTemplateTranslations extends Mock
    implements WorkoutTemplateTranslationResolver {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String>[]);
  });

  late Directory tempDir;
  late CacheService cache;
  late Box<dynamic> routineBox;
  late _MockExerciseRepository mockExerciseRepo;
  late _MockTemplateTranslations mockTemplateTranslations;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('routine_cache_test_');
    Hive.init(tempDir.path);
    routineBox = await Hive.openBox<dynamic>(HiveService.routineCache);
    cache = const CacheService();
    mockExerciseRepo = _MockExerciseRepository();
    mockTemplateTranslations = _MockTemplateTranslations();
    // Default: empty exercise map. Individual tests override as needed.
    when(
      () => mockExerciseRepo.getExercisesByIds(
        locale: any(named: 'locale'),
        userId: any(named: 'userId'),
        ids: any(named: 'ids'),
      ),
    ).thenAnswer((_) async => <String, Exercise>{});
    // Default: no template translations. Cache tests don't care about the
    // template_slug rewrite path — they assert exercise resolution survives
    // the envelope round-trip.
    when(
      () => mockTemplateTranslations.resolveNames(
        slugs: any(named: 'slugs'),
        locale: any(named: 'locale'),
      ),
    ).thenAnswer((_) async => const <String, String>{});
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('RoutineRepository cache - getRoutines', () {
    test(
      'cache preserves resolved exercises through envelope roundtrip',
      () async {
        // Build the cache envelope as the repo would write it:
        // { routines: [...], exercises: { id -> exerciseJson } }
        // Key is `<userId>:<locale>`.
        final exerciseJson = TestExerciseFactory.create(
          id: 'ex-bench',
          name: 'Bench Press',
          equipmentType: 'barbell',
        );
        final routineJson = TestRoutineFactory.create(
          id: 'r-001',
          name: 'Push Day',
          exercises: [
            TestRoutineExerciseFactory.create(exerciseId: 'ex-bench'),
          ],
        );
        final envelope = {
          'routines': [routineJson],
          'exercises': {'ex-bench': exerciseJson},
        };
        await routineBox.put('user-001:en', jsonEncode(envelope));

        // Create repo with a failing client to force cache read.
        final client = FakeSupabaseClient(
          FakeQueryBuilder(error: Exception('offline')),
        );
        final repo = RoutineRepository(
          client,
          cache,
          mockExerciseRepo,
          mockTemplateTranslations,
        );

        final result = await repo.getRoutines(userId: 'user-001', locale: 'en');

        expect(result, hasLength(1));
        expect(result[0].name, 'Push Day');
        expect(result[0].exercises[0].exercise, isNotNull);
        expect(result[0].exercises[0].exercise!.name, 'Bench Press');
      },
    );

    test('cache key is locale-prefixed (`<userId>:<locale>`)', () async {
      // Online fetch with one routine — must write under the locale-prefixed key.
      final templateRow = TestRoutineFactory.create(id: 'r-1', exercises: []);
      final client = FakeSupabaseClient(FakeQueryBuilder(data: [templateRow]));
      final repo = RoutineRepository(
        client,
        cache,
        mockExerciseRepo,
        mockTemplateTranslations,
      );

      await repo.getRoutines(userId: 'user-001', locale: 'en');

      expect(
        routineBox.get('user-001:en'),
        isNotNull,
        reason: 'cache key must be `<userId>:<locale>`',
      );
      expect(
        routineBox.get('user-001'),
        isNull,
        reason: 'legacy key without locale must not be written',
      );
    });

    test('en cache does not satisfy pt request', () async {
      // Seed only the en cache.
      final routineJson = TestRoutineFactory.create(id: 'r-en-only');
      final envelope = {
        'routines': [routineJson],
        'exercises': <String, dynamic>{},
      };
      await routineBox.put('user-001:en', jsonEncode(envelope));

      // Network fails — pt request must NOT pick up en-cached data.
      final client = FakeSupabaseClient(
        FakeQueryBuilder(error: Exception('offline')),
      );
      final repo = RoutineRepository(
        client,
        cache,
        mockExerciseRepo,
        mockTemplateTranslations,
      );

      await expectLater(
        repo.getRoutines(userId: 'user-001', locale: 'pt'),
        throwsA(isA<Exception>()),
        reason: 'pt request must not pick up en-cached data',
      );
    });

    test(
      'network failure returns cached routines with resolved exercises',
      () async {
        // Build cache envelope with two exercises.
        final ex1 = TestExerciseFactory.create(id: 'ex-1', name: 'Squat');
        final ex2 = TestExerciseFactory.create(id: 'ex-2', name: 'Deadlift');
        final routineJson = TestRoutineFactory.create(
          id: 'r-002',
          name: 'Leg Day',
          exercises: [
            TestRoutineExerciseFactory.create(exerciseId: 'ex-1'),
            TestRoutineExerciseFactory.create(exerciseId: 'ex-2'),
          ],
        );
        final envelope = {
          'routines': [routineJson],
          'exercises': {'ex-1': ex1, 'ex-2': ex2},
        };
        await routineBox.put('user-001:en', jsonEncode(envelope));

        final client = FakeSupabaseClient(
          FakeQueryBuilder(error: Exception('offline')),
        );
        final repo = RoutineRepository(
          client,
          cache,
          mockExerciseRepo,
          mockTemplateTranslations,
        );

        final result = await repo.getRoutines(userId: 'user-001', locale: 'en');

        expect(result, hasLength(1));
        expect(result[0].exercises[0].exercise?.name, 'Squat');
        expect(result[0].exercises[1].exercise?.name, 'Deadlift');
      },
    );

    test('rethrows when no cache and network fails', () async {
      final client = FakeSupabaseClient(
        FakeQueryBuilder(error: Exception('offline')),
      );
      final repo = RoutineRepository(
        client,
        cache,
        mockExerciseRepo,
        mockTemplateTranslations,
      );

      expect(
        () => repo.getRoutines(userId: 'user-001', locale: 'en'),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'cached routine with no exercises reads back with empty exercise list',
      () async {
        final routineJson = TestRoutineFactory.create(
          id: 'r-empty',
          name: 'Empty Routine',
          exercises: [],
        );
        final envelope = {
          'routines': [routineJson],
          'exercises': <String, dynamic>{},
        };
        await routineBox.put('user-001:en', jsonEncode(envelope));

        final client = FakeSupabaseClient(
          FakeQueryBuilder(error: Exception('offline')),
        );
        final repo = RoutineRepository(
          client,
          cache,
          mockExerciseRepo,
          mockTemplateTranslations,
        );

        final result = await repo.getRoutines(userId: 'user-001', locale: 'en');

        expect(result, hasLength(1));
        expect(result[0].name, 'Empty Routine');
        expect(result[0].exercises, isEmpty);
      },
    );

    test(
      'fresh data is written and readable on subsequent offline call',
      () async {
        final templateRow = TestRoutineFactory.create(
          id: 'r-written',
          name: 'Written Routine',
          exercises: [TestRoutineExerciseFactory.create(exerciseId: 'ex-w')],
        );

        // Online fetch returns this routine; the batch RPC mock returns the
        // localized exercise so the cache envelope ends up with a resolved
        // exercise reference.
        when(
          () => mockExerciseRepo.getExercisesByIds(
            locale: 'en',
            userId: 'user-001',
            ids: any(named: 'ids'),
          ),
        ).thenAnswer(
          (_) async => {
            'ex-w': Exercise.fromJson(
              TestExerciseFactory.create(id: 'ex-w', name: 'Written Exercise'),
            ),
          },
        );

        // First call: network succeeds — repo writes cache.
        final onlineClient = FakeSupabaseClient(
          FakeQueryBuilder(data: [templateRow]),
        );
        await RoutineRepository(
          onlineClient,
          cache,
          mockExerciseRepo,
          mockTemplateTranslations,
        ).getRoutines(userId: 'user-001', locale: 'en');

        // Second call: network fails — must return data from cache.
        final offlineClient = FakeSupabaseClient(
          FakeQueryBuilder(error: Exception('offline')),
        );
        final result = await RoutineRepository(
          offlineClient,
          cache,
          mockExerciseRepo,
          mockTemplateTranslations,
        ).getRoutines(userId: 'user-001', locale: 'en');

        expect(result, hasLength(1));
        expect(result[0].name, 'Written Routine');
        expect(result[0].exercises[0].exercise?.name, 'Written Exercise');
      },
    );
  });
}
