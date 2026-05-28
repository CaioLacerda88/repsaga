// Phase 15f Stage 6: ExerciseRepository now routes reads/writes through the
// localized RPCs (`fn_exercises_localized`, `fn_search_exercises_localized`,
// `fn_insert_user_exercise`, `fn_update_user_exercise`). Tests use
// `FakeRpcClient` from test/fixtures/rpc_fakes.dart for RPC calls; the only
// surviving direct-table path (softDeleteExercise) keeps using the shared
// `FakeQueryBuilder` from test/unit/_helpers/fake_supabase.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/exceptions/app_exception.dart';
import 'package:repsaga/core/local_storage/cache_service.dart';
import 'package:repsaga/features/exercises/data/exercise_repository.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../fixtures/rpc_fakes.dart';
import '../../../../fixtures/test_factories.dart';
import '../../../_helpers/fake_supabase.dart';

void main() {
  group('ExerciseRepository (RPC-based)', () {
    group('getExercises', () {
      test('routes to fn_exercises_localized with locale + user', () async {
        final client = FakeRpcClient()
          ..registerRpc('fn_exercises_localized', (params) {
            return [
              TestExerciseFactory.create(),
              TestExerciseFactory.create(
                id: 'exercise-002',
                name: 'Squat',
                muscleGroup: 'legs',
                slug: 'squat',
              ),
            ];
          });
        final repo = ExerciseRepository(client, const CacheService());

        final result = await repo.getExercises(
          locale: 'en',
          userId: 'user-001',
        );

        expect(result, hasLength(2));
        expect(result[0].name, 'Bench Press');
        expect(result[1].name, 'Squat');
        expect(client.lastRpcName, 'fn_exercises_localized');
        expect(client.lastRpcParams, {
          'p_locale': 'en',
          'p_user_id': 'user-001',
          'p_muscle_group': null,
          'p_equipment_type': null,
          'p_ids': null,
          'p_order': 'name',
        });
      });

      test('passes muscle group filter', () async {
        final client = FakeRpcClient()
          ..registerRpc('fn_exercises_localized', (params) {
            expect(params!['p_muscle_group'], 'chest');
            return [TestExerciseFactory.create()];
          });
        final repo = ExerciseRepository(client, const CacheService());

        await repo.getExercises(
          locale: 'en',
          userId: 'user-001',
          muscleGroup: MuscleGroup.chest,
        );

        expect(client.lastRpcParams!['p_muscle_group'], 'chest');
        expect(client.lastRpcParams!['p_equipment_type'], null);
      });

      test('passes equipment type filter', () async {
        final client = FakeRpcClient()
          ..registerRpc('fn_exercises_localized', (params) {
            return [TestExerciseFactory.create()];
          });
        final repo = ExerciseRepository(client, const CacheService());

        await repo.getExercises(
          locale: 'pt',
          userId: 'user-001',
          equipmentType: EquipmentType.barbell,
        );

        expect(client.lastRpcParams!['p_equipment_type'], 'barbell');
        expect(client.lastRpcParams!['p_locale'], 'pt');
      });

      test('exactly one RPC call per invocation', () async {
        final client = FakeRpcClient()
          ..registerRpc(
            'fn_exercises_localized',
            (_) => List.generate(
              5,
              (i) => TestExerciseFactory.create(id: 'ex-$i', slug: 'ex_$i'),
            ),
          );
        final repo = ExerciseRepository(client, const CacheService());

        await repo.getExercises(locale: 'en', userId: 'user-001');

        expect(client.callCountFor('fn_exercises_localized'), 1);
      });
    });

    group('searchExercises', () {
      test('routes to fn_search_exercises_localized', () async {
        final client = FakeRpcClient()
          ..registerRpc('fn_search_exercises_localized', (params) {
            return [TestExerciseFactory.create()];
          });
        final repo = ExerciseRepository(client, const CacheService());

        final result = await repo.searchExercises(
          locale: 'en',
          userId: 'user-001',
          query: 'bench',
        );

        expect(result, hasLength(1));
        expect(client.lastRpcName, 'fn_search_exercises_localized');
        expect(client.lastRpcParams, {
          'p_query': 'bench',
          'p_locale': 'en',
          'p_user_id': 'user-001',
          'p_muscle_group': null,
          'p_equipment_type': null,
        });
      });

      test('forwards filters to the RPC', () async {
        final client = FakeRpcClient()
          ..registerRpc('fn_search_exercises_localized', (params) {
            expect(params!['p_muscle_group'], 'chest');
            expect(params['p_equipment_type'], 'barbell');
            return [TestExerciseFactory.create()];
          });
        final repo = ExerciseRepository(client, const CacheService());

        await repo.searchExercises(
          locale: 'pt',
          userId: 'user-001',
          query: 'press',
          muscleGroup: MuscleGroup.chest,
          equipmentType: EquipmentType.barbell,
        );

        expect(client.lastRpcParams!['p_locale'], 'pt');
      });
    });

    group('getExerciseById', () {
      test('passes p_ids = [id] and returns the row', () async {
        final client = FakeRpcClient()
          ..registerRpc('fn_exercises_localized', (params) {
            expect(params!['p_ids'], ['exercise-001']);
            return [TestExerciseFactory.create()];
          });
        final repo = ExerciseRepository(client, const CacheService());

        final result = await repo.getExerciseById(
          locale: 'en',
          userId: 'user-001',
          id: 'exercise-001',
        );

        expect(result.id, 'exercise-001');
        expect(result.name, 'Bench Press');
      });

      test('throws when RPC returns empty list', () async {
        final client = FakeRpcClient()
          ..registerRpc('fn_exercises_localized', (_) => []);
        final repo = ExerciseRepository(client, const CacheService());

        // The repository throws StateError for missing rows; mapException
        // routes it through ErrorMapper, which surfaces non-Supabase errors
        // as NetworkException (the safe-default unmapped bucket — see
        // ErrorMapper.mapException). We assert the concrete sealed-subtype
        // here so a future refactor that swallows the throw or converts it
        // to a successful empty result fails this test loudly.
        await expectLater(
          repo.getExerciseById(locale: 'en', userId: 'user-001', id: 'missing'),
          throwsA(isA<NetworkException>()),
        );
      });
    });

    group('getExercisesByIds', () {
      test('returns map keyed by exercise id', () async {
        final client = FakeRpcClient()
          ..registerRpc('fn_exercises_localized', (params) {
            expect(params!['p_ids'], ['ex-1', 'ex-2']);
            return [
              TestExerciseFactory.create(id: 'ex-1', name: 'Bench Press'),
              TestExerciseFactory.create(
                id: 'ex-2',
                name: 'Squat',
                muscleGroup: 'legs',
                slug: 'squat',
              ),
            ];
          });
        final repo = ExerciseRepository(client, const CacheService());

        final result = await repo.getExercisesByIds(
          locale: 'en',
          userId: 'user-001',
          ids: ['ex-1', 'ex-2'],
        );

        expect(result, hasLength(2));
        expect(result['ex-1']!.name, 'Bench Press');
        expect(result['ex-2']!.name, 'Squat');
      });

      test('empty ids short-circuits with no RPC call', () async {
        final client = FakeRpcClient();
        // Intentionally no handler — would throw if called.
        final repo = ExerciseRepository(client, const CacheService());

        final result = await repo.getExercisesByIds(
          locale: 'en',
          userId: 'user-001',
          ids: const [],
        );

        expect(result, isEmpty);
        expect(client.rpcCallCount, 0);
      });

      test('drops missing ids silently (visibility filter)', () async {
        final client = FakeRpcClient()
          ..registerRpc('fn_exercises_localized', (_) {
            // Server filters out the deleted row; only ex-1 returned.
            return [TestExerciseFactory.create(id: 'ex-1')];
          });
        final repo = ExerciseRepository(client, const CacheService());

        final result = await repo.getExercisesByIds(
          locale: 'en',
          userId: 'user-001',
          ids: const ['ex-1', 'ex-deleted'],
        );

        expect(result.containsKey('ex-1'), isTrue);
        expect(result.containsKey('ex-deleted'), isFalse);
      });

      test('exactly one RPC call regardless of id count', () async {
        final client = FakeRpcClient()
          ..registerRpc(
            'fn_exercises_localized',
            (_) => List.generate(
              50,
              (i) => TestExerciseFactory.create(id: 'ex-$i', slug: 'ex_$i'),
            ),
          );
        final repo = ExerciseRepository(client, const CacheService());

        await repo.getExercisesByIds(
          locale: 'en',
          userId: 'user-001',
          ids: List.generate(50, (i) => 'ex-$i'),
        );

        expect(client.callCountFor('fn_exercises_localized'), 1);
      });
    });

    group('updateExercise', () {
      test('routes to fn_update_user_exercise with non-null fields', () async {
        final client = FakeRpcClient()
          ..registerRpc('fn_update_user_exercise', (params) {
            expect(params!['p_exercise_id'], 'ex-1');
            expect(params['p_name'], 'New Name');
            expect(params['p_muscle_group'], isNull);
            expect(params['p_equipment_type'], 'dumbbell');
            return [
              TestExerciseFactory.create(
                id: 'ex-1',
                name: 'New Name',
                equipmentType: 'dumbbell',
              ),
            ];
          });
        final repo = ExerciseRepository(client, const CacheService());

        final result = await repo.updateExercise(
          id: 'ex-1',
          name: 'New Name',
          equipmentType: EquipmentType.dumbbell,
        );

        expect(result.name, 'New Name');
        expect(result.equipmentType, EquipmentType.dumbbell);
      });

      test('maps SQLSTATE 23505 to ValidationException', () async {
        final client = FakeRpcClient()
          ..registerRpc('fn_update_user_exercise', (_) {
            throw const supabase.PostgrestException(
              message: 'duplicate exercise name for user: X',
              code: '23505',
            );
          });
        final repo = ExerciseRepository(client, const CacheService());

        await expectLater(
          () => repo.updateExercise(id: 'ex-1', name: 'X'),
          throwsA(isA<ValidationException>()),
        );
      });
    });

    group('softDeleteExercise', () {
      test('updates deleted_at via direct table call', () async {
        final fakeBuilder = FakeQueryBuilder();
        final client = FakeRpcClient(tableBuilders: {'exercises': fakeBuilder});
        final repo = ExerciseRepository(client, const CacheService());

        await repo.softDeleteExercise('exercise-001', userId: 'user-001');

        expect(fakeBuilder.calledMethods, contains('update'));
        expect(fakeBuilder.calledMethods, contains('eq:id=exercise-001'));
        expect(fakeBuilder.calledMethods, contains('eq:user_id=user-001'));
        // softDelete should not invoke any RPC.
        expect(client.rpcCallCount, 0);
      });
    });

    group('recentExercises', () {
      test(
        'routes to fn_exercises_localized with p_order=created_at_desc and trims to limit',
        () async {
          final client = FakeRpcClient()
            ..registerRpc('fn_exercises_localized', (params) {
              expect(params!['p_order'], 'created_at_desc');
              return List.generate(
                15,
                (i) => TestExerciseFactory.create(id: 'ex-$i', slug: 'ex_$i'),
              );
            });
          final repo = ExerciseRepository(client, const CacheService());

          final result = await repo.recentExercises(
            locale: 'en',
            userId: 'user-001',
            limit: 5,
          );

          expect(result, hasLength(5));
        },
      );
    });
  });
}
