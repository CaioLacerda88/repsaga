import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/local_storage/cache_service.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:repsaga/features/exercises/data/exercise_repository.dart';
import 'package:repsaga/features/personal_records/data/pr_repository.dart';
import 'package:repsaga/features/personal_records/models/personal_record.dart';
import 'package:repsaga/features/personal_records/models/record_type.dart';

import '../../../../fixtures/test_factories.dart';
import '../../../_helpers/fake_supabase.dart';

class _MockExerciseRepository extends Mock implements ExerciseRepository {}

void main() {
  late Directory tempDir;
  late CacheService cache;
  late Box<dynamic> prBox;
  late _MockExerciseRepository mockExerciseRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pr_per_exercise_test_');
    Hive.init(tempDir.path);
    prBox = await Hive.openBox<dynamic>(HiveService.prCache);
    cache = const CacheService();
    mockExerciseRepo = _MockExerciseRepository();
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('PRRepository.seedExerciseCacheEntries', () {
    test(
      'writes one cache entry per exercise id (groups by exerciseId)',
      () async {
        final repo = PRRepository(
          FakeSupabaseClient(FakeQueryBuilder()),
          cache,
          mockExerciseRepo,
        );

        final records = [
          PersonalRecord(
            id: 'pr-1',
            userId: 'u-1',
            exerciseId: 'ex-1',
            recordType: RecordType.maxWeight,
            value: 100,
            achievedAt: DateTime.utc(2026, 1, 1),
          ),
          PersonalRecord(
            id: 'pr-2',
            userId: 'u-1',
            exerciseId: 'ex-1',
            recordType: RecordType.maxReps,
            value: 8,
            achievedAt: DateTime.utc(2026, 1, 1),
          ),
          PersonalRecord(
            id: 'pr-3',
            userId: 'u-1',
            exerciseId: 'ex-2',
            recordType: RecordType.maxWeight,
            value: 200,
            achievedAt: DateTime.utc(2026, 1, 1),
          ),
        ];

        await repo.seedExerciseCacheEntries(records);

        final ex1Json = prBox.get('exercises:ex-1') as String?;
        final ex2Json = prBox.get('exercises:ex-2') as String?;
        expect(ex1Json, isNotNull);
        expect(ex2Json, isNotNull);

        final ex1 = jsonDecode(ex1Json!) as Map<String, dynamic>;
        expect((ex1['ex-1'] as List), hasLength(2));

        final ex2 = jsonDecode(ex2Json!) as Map<String, dynamic>;
        expect((ex2['ex-2'] as List), hasLength(1));
      },
    );

    test('empty records list is a no-op', () async {
      final repo = PRRepository(
        FakeSupabaseClient(FakeQueryBuilder()),
        cache,
        mockExerciseRepo,
      );

      await repo.seedExerciseCacheEntries(const []);

      expect(prBox.isEmpty, isTrue);
    });
  });

  group('PRRepository.getRecordsForExercises — per-exercise cache fallback '
      '(BLOCKER fix: AW-EX-D-US1-01)', () {
    test(
      'falls back to assembled per-exercise cache entries when network fails '
      'and multi-exercise key is absent',
      () async {
        // Seed only per-exercise keys (as the bootstrap would). NO
        // multi-exercise subset key is present.
        await prBox.put(
          'exercises:ex-1',
          jsonEncode({
            'ex-1': [
              TestPersonalRecordFactory.create(
                id: 'pr-1',
                exerciseId: 'ex-1',
                value: 50.0,
              ),
            ],
          }),
        );
        await prBox.put(
          'exercises:ex-2',
          jsonEncode({
            'ex-2': [
              TestPersonalRecordFactory.create(
                id: 'pr-2',
                exerciseId: 'ex-2',
                value: 75.0,
              ),
            ],
          }),
        );

        final client = FakeSupabaseClient(
          FakeQueryBuilder(error: Exception('offline')),
        );
        final repo = PRRepository(client, cache, mockExerciseRepo);

        // Querying a NEW subset (multi-id key would be 'exercises:ex-1,ex-2',
        // not present in cache) — falls back to per-exercise entries.
        final result = await repo.getRecordsForExercises(['ex-2', 'ex-1']);

        expect(result.keys, containsAll(['ex-1', 'ex-2']));
        expect(result['ex-1']!.first.value, 50.0);
        expect(result['ex-2']!.first.value, 75.0);
      },
    );

    test('partial per-exercise cache yields a result map for the seeded ids '
        '(missing ids absent) when the network is offline', () async {
      await prBox.put(
        'exercises:ex-1',
        jsonEncode({
          'ex-1': [
            TestPersonalRecordFactory.create(
              id: 'pr-1',
              exerciseId: 'ex-1',
              value: 50.0,
            ),
          ],
        }),
      );

      final client = FakeSupabaseClient(
        FakeQueryBuilder(error: Exception('offline')),
      );
      final repo = PRRepository(client, cache, mockExerciseRepo);

      // Asking for ex-1 (cached) and ex-untracked (no cache, never trained).
      final result = await repo.getRecordsForExercises([
        'ex-1',
        'ex-untracked',
      ]);

      // Cached exercise resolves to its records; the untracked one is
      // simply absent from the map (the resolver treats missing keys as
      // "no prior record" — first-ever-workout semantic).
      expect(result['ex-1']!.first.value, 50.0);
      expect(result.containsKey('ex-untracked'), isFalse);
    });

    test('still rethrows when neither multi-key nor per-exercise entries exist '
        'and the network call fails', () async {
      final client = FakeSupabaseClient(
        FakeQueryBuilder(error: Exception('offline')),
      );
      final repo = PRRepository(client, cache, mockExerciseRepo);

      await expectLater(
        repo.getRecordsForExercises(['ex-no-cache-at-all']),
        throwsA(isA<Exception>()),
      );
    });
  });
}
