import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:repsaga/features/auth/providers/auth_providers.dart';
import 'package:repsaga/features/personal_records/data/pr_repository.dart';
import 'package:repsaga/features/personal_records/models/personal_record.dart';
import 'package:repsaga/features/personal_records/models/record_type.dart';
import 'package:repsaga/features/personal_records/providers/pr_cache_bootstrap_provider.dart';
import 'package:repsaga/features/personal_records/providers/pr_providers.dart';
import 'package:repsaga/core/l10n/locale_provider.dart';

class _MockPRRepository extends Mock implements PRRepository {}

class _FakeLocaleNotifier extends LocaleNotifier {
  _FakeLocaleNotifier(this._initial);
  final Locale _initial;
  @override
  Locale build() => _initial;
}

PersonalRecord _record({
  required String id,
  required String exerciseId,
  RecordType type = RecordType.maxWeight,
  double value = 100.0,
  String userId = 'user-1',
}) {
  return PersonalRecord(
    id: id,
    userId: userId,
    exerciseId: exerciseId,
    recordType: type,
    value: value,
    achievedAt: DateTime.utc(2026, 1, 1, 12),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<dynamic> prBox;
  late Box<dynamic> prefsBox;
  late _MockPRRepository mockRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pr_bootstrap_test_');
    Hive.init(tempDir.path);
    prBox = await Hive.openBox<dynamic>(HiveService.prCache);
    prefsBox = await Hive.openBox<dynamic>(HiveService.userPrefs);
    mockRepo = _MockPRRepository();
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  ProviderContainer makeContainer({
    String? userId = 'user-1',
    String localeCode = 'en',
  }) {
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWithValue(userId),
        prRepositoryProvider.overrideWithValue(mockRepo),
        localeProvider.overrideWith(
          () => _FakeLocaleNotifier(Locale(localeCode)),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('prCacheBootstrapProvider', () {
    test('seeds per-exercise cache entries from the user PR list', () async {
      final records = [
        _record(id: 'pr-1', exerciseId: 'ex-1', value: 100),
        _record(
          id: 'pr-2',
          exerciseId: 'ex-1',
          value: 8,
          type: RecordType.maxReps,
        ),
        _record(id: 'pr-3', exerciseId: 'ex-2', value: 200),
      ];
      when(
        () => mockRepo.getRecordsForUser(
          userId: any(named: 'userId'),
          locale: any(named: 'locale'),
        ),
      ).thenAnswer((_) async => records);

      final container = makeContainer();

      // Trigger the future.
      await container.read(prCacheBootstrapProvider.future);

      // Per-exercise cache entries are populated under the same key shape
      // PRRepository.getRecordsForExercises([id]) writes to: 'exercises:<id>'.
      final ex1Raw = prBox.get('exercises:ex-1') as String?;
      final ex2Raw = prBox.get('exercises:ex-2') as String?;
      expect(
        ex1Raw,
        isNotNull,
        reason: 'bootstrap must seed per-exercise key for ex-1',
      );
      expect(
        ex2Raw,
        isNotNull,
        reason: 'bootstrap must seed per-exercise key for ex-2',
      );

      final ex1 = jsonDecode(ex1Raw!) as Map<String, dynamic>;
      expect(
        (ex1['ex-1'] as List),
        hasLength(2),
        reason: 'two records for ex-1 should be grouped',
      );

      final ex2 = jsonDecode(ex2Raw!) as Map<String, dynamic>;
      expect((ex2['ex-2'] as List), hasLength(1));
    });

    test(
      'subsequent reads do not refetch (provider keeps cached value)',
      () async {
        when(
          () => mockRepo.getRecordsForUser(
            userId: any(named: 'userId'),
            locale: any(named: 'locale'),
          ),
        ).thenAnswer((_) async => <PersonalRecord>[]);

        final container = makeContainer();

        await container.read(prCacheBootstrapProvider.future);
        await container.read(prCacheBootstrapProvider.future);

        // Repo is called exactly once across two reads (Riverpod caches the
        // future for the same provider instance).
        verify(
          () => mockRepo.getRecordsForUser(
            userId: any(named: 'userId'),
            locale: any(named: 'locale'),
          ),
        ).called(1);
      },
    );

    test('ref.invalidate triggers a fresh fetch (re-seed contract)', () async {
      when(
        () => mockRepo.getRecordsForUser(
          userId: any(named: 'userId'),
          locale: any(named: 'locale'),
        ),
      ).thenAnswer((_) async => <PersonalRecord>[]);

      final container = makeContainer();

      await container.read(prCacheBootstrapProvider.future);
      container.invalidate(prCacheBootstrapProvider);
      await container.read(prCacheBootstrapProvider.future);

      verify(
        () => mockRepo.getRecordsForUser(
          userId: any(named: 'userId'),
          locale: any(named: 'locale'),
        ),
      ).called(2);
    });

    test(
      'returns immediately without calling repo when no signed-in user',
      () async {
        final container = makeContainer(userId: null);

        await container.read(prCacheBootstrapProvider.future);

        verifyNever(
          () => mockRepo.getRecordsForUser(
            userId: any(named: 'userId'),
            locale: any(named: 'locale'),
          ),
        );
      },
    );

    test(
      'survives repository errors without throwing (best-effort warmup)',
      () async {
        when(
          () => mockRepo.getRecordsForUser(
            userId: any(named: 'userId'),
            locale: any(named: 'locale'),
          ),
        ).thenThrow(Exception('offline'));

        final container = makeContainer();

        // The provider must NOT throw — bootstrap is best-effort. A failed
        // network warmup still allows the existing read-through caching path
        // to handle subsequent reads.
        await expectLater(
          container.read(prCacheBootstrapProvider.future),
          completes,
        );
      },
    );
  });

  group('pr_cache_v2_migrated one-shot Hive migration', () {
    test(
      'clears prCache once when flag absent and sets flag afterwards',
      () async {
        // Pre-populate prCache with stale (potentially polluted) entries.
        await prBox.put(
          'exercises:ex-stale',
          jsonEncode({
            'ex-stale': [
              {
                'id': 'old-pr',
                'user_id': 'user-1',
                'exercise_id': 'ex-stale',
                'record_type': 'max_weight',
                'value': 999.0,
                'achieved_at': '2025-01-01T00:00:00Z',
              },
            ],
          }),
        );
        expect(prBox.isEmpty, isFalse);
        expect(prefsBox.get('pr_cache_v2_migrated'), isNull);

        when(
          () => mockRepo.getRecordsForUser(
            userId: any(named: 'userId'),
            locale: any(named: 'locale'),
          ),
        ).thenAnswer((_) async => <PersonalRecord>[]);

        final container = makeContainer();
        await container.read(prCacheBootstrapProvider.future);

        // Stale entries are wiped.
        expect(
          prBox.get('exercises:ex-stale'),
          isNull,
          reason: 'one-shot migration must wipe stale prCache entries',
        );
        // Migration flag is now set.
        expect(prefsBox.get('pr_cache_v2_migrated'), isTrue);
      },
    );

    test(
      'is idempotent — running with flag already set does not wipe cache',
      () async {
        // Flag pre-set by a previous run.
        await prefsBox.put('pr_cache_v2_migrated', true);

        // Bootstrap will write per-exercise entries; we expect those to
        // survive (the migration only runs when flag is absent).
        final records = [
          _record(id: 'pr-keep', exerciseId: 'ex-keep', value: 50),
        ];
        when(
          () => mockRepo.getRecordsForUser(
            userId: any(named: 'userId'),
            locale: any(named: 'locale'),
          ),
        ).thenAnswer((_) async => records);

        // Pre-seed an entry that the migration would wipe if it ran.
        await prBox.put(
          'exercises:should-survive',
          jsonEncode({'should-survive': []}),
        );

        final container = makeContainer();
        await container.read(prCacheBootstrapProvider.future);

        // Existing entry is preserved (migration was a no-op).
        expect(
          prBox.get('exercises:should-survive'),
          isNotNull,
          reason: 'flag-set path must NOT touch prCache',
        );
        // Bootstrap-seeded entries are added.
        expect(prBox.get('exercises:ex-keep'), isNotNull);
      },
    );

    test(
      'runs exactly once across two bootstrap reads (re-running is a no-op)',
      () async {
        when(
          () => mockRepo.getRecordsForUser(
            userId: any(named: 'userId'),
            locale: any(named: 'locale'),
          ),
        ).thenAnswer((_) async => <PersonalRecord>[]);

        final container = makeContainer();
        await container.read(prCacheBootstrapProvider.future);
        // After first run, flag is set and box is empty (no records to seed).
        expect(prefsBox.get('pr_cache_v2_migrated'), isTrue);

        // Second invocation does NOT re-run the migration (idempotent).
        // Pre-seed an entry that would be wiped if migration ran again.
        await prBox.put('exercises:still-here', jsonEncode({'still-here': []}));

        container.invalidate(prCacheBootstrapProvider);
        await container.read(prCacheBootstrapProvider.future);

        expect(
          prBox.get('exercises:still-here'),
          isNotNull,
          reason: 'migration must not re-run after the flag is set',
        );
      },
    );
  });
}
