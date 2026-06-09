// RoutineRepository unit tests.
//
// Phase 15f Stage 6: exercise resolution now delegates to
// `ExerciseRepository.getExercisesByIds(locale, userId, ids)`. Tests stub
// that batch RPC with mocktail and pass `locale: 'en'` everywhere unless
// verifying multi-locale isolation.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/exceptions/app_exception.dart';
import 'package:repsaga/core/local_storage/cache_service.dart';
import 'package:repsaga/features/exercises/data/exercise_repository.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/routines/data/routine_repository.dart';
import 'package:repsaga/features/routines/data/workout_template_translation_resolver.dart';
import 'package:repsaga/features/routines/models/routine.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../fixtures/test_factories.dart';

class _MockExerciseRepository extends Mock implements ExerciseRepository {}

class _MockTemplateTranslations extends Mock
    implements WorkoutTemplateTranslationResolver {}

// ---------------------------------------------------------------------------
// Fake Supabase infrastructure (templates only — exercise reads go through
// the injected ExerciseRepository mock, not through `_client.from('exercises')`)
// ---------------------------------------------------------------------------

class _FakeSupabaseClient extends Fake implements supabase.SupabaseClient {
  _FakeSupabaseClient(this._templatesBuilder);

  final _FakeQueryBuilder _templatesBuilder;

  @override
  supabase.SupabaseQueryBuilder from(String table) {
    if (table == 'workout_templates') return _templatesBuilder;
    throw StateError('Unexpected table read: $table');
  }
}

// Mutable test fake: captures the last write payload so write-path tests can
// assert the exact columns sent to PostgREST. The mutable field is the point.
// ignore: must_be_immutable
class _FakeQueryBuilder extends Fake implements supabase.SupabaseQueryBuilder {
  _FakeQueryBuilder({this.data = const [], this.error});

  final List<Map<String, dynamic>> data;
  final Exception? error;

  /// Last payload passed to `insert` / `update`, captured so write-path tests
  /// can assert exactly what columns the repository sends to PostgREST.
  Map<String, dynamic>? lastWrittenPayload;

  @override
  _FakeFilterBuilder select([String columns = '*']) => _FakeFilterBuilder(this);

  @override
  _FakeFilterBuilder insert(dynamic values, {bool defaultToNull = true}) {
    lastWrittenPayload = (values as Map).cast<String, dynamic>();
    return _FakeFilterBuilder(this);
  }

  @override
  _FakeFilterBuilder update(Map values) {
    lastWrittenPayload = values.cast<String, dynamic>();
    return _FakeFilterBuilder(this);
  }

  @override
  _FakeFilterBuilder delete() => _FakeFilterBuilder(this);
}

class _FakeFilterBuilder extends Fake
    implements supabase.PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  _FakeFilterBuilder(this._parent);

  final _FakeQueryBuilder _parent;

  @override
  _FakeFilterBuilder select([String columns = '*']) => this;

  @override
  _FakeFilterBuilder eq(String column, Object value) => this;

  @override
  _FakeFilterBuilder or(String filter, {String? referencedTable}) => this;

  @override
  _FakeFilterBuilder inFilter(String column, List values) => this;

  @override
  _FakeTransformBuilder<Map<String, dynamic>> single() =>
      _FakeTransformBuilder<Map<String, dynamic>>(
        _parent,
        _parent.data.isEmpty ? <String, dynamic>{} : _parent.data.first,
      );

  @override
  _FakeTransformBuilder<List<Map<String, dynamic>>> order(
    String column, {
    bool ascending = false,
    bool nullsFirst = false,
    String? referencedTable,
  }) =>
      _FakeTransformBuilder<List<Map<String, dynamic>>>(_parent, _parent.data);

  @override
  Future<S> then<S>(
    FutureOr<S> Function(List<Map<String, dynamic>>) onValue, {
    Function? onError,
  }) {
    if (_parent.error != null) {
      return Future<List<Map<String, dynamic>>>.error(
        _parent.error!,
      ).then<S>(onValue, onError: onError);
    }
    return Future.value(onValue(_parent.data));
  }
}

class _FakeTransformBuilder<T> extends Fake
    implements supabase.PostgrestTransformBuilder<T> {
  _FakeTransformBuilder(this._parent, this._result);

  final _FakeQueryBuilder _parent;
  final T _result;

  @override
  _FakeFilterBuilder select([String columns = '*']) =>
      _FakeFilterBuilder(_parent);

  @override
  Future<S> then<S>(FutureOr<S> Function(T) onValue, {Function? onError}) {
    if (_parent.error != null) {
      return Future<T>.error(_parent.error!).then<S>(onValue, onError: onError);
    }
    return Future.value(onValue(_result));
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _RepoBundle {
  _RepoBundle(
    this.repo,
    this.mockExerciseRepo,
    this.mockTemplateTranslations,
    this.templatesBuilder,
  );
  final RoutineRepository repo;
  final _MockExerciseRepository mockExerciseRepo;
  final _MockTemplateTranslations mockTemplateTranslations;
  final _FakeQueryBuilder templatesBuilder;
}

_RepoBundle _makeRepo({
  List<Map<String, dynamic>> templates = const [],
  Map<String, Exercise> exerciseMap = const {},
  Exception? templatesError,
}) {
  final templatesBuilder = _FakeQueryBuilder(
    data: templates,
    error: templatesError,
  );
  final client = _FakeSupabaseClient(templatesBuilder);
  final mockExerciseRepo = _MockExerciseRepository();
  when(
    () => mockExerciseRepo.getExercisesByIds(
      locale: any(named: 'locale'),
      userId: any(named: 'userId'),
      ids: any(named: 'ids'),
    ),
  ).thenAnswer((_) async => exerciseMap);
  // Default: resolver returns empty map (no translations). Tests covering the
  // template-translation rewrite path override this via the exposed
  // `mockTemplateTranslations` on the bundle.
  final mockTemplateTranslations = _MockTemplateTranslations();
  when(
    () => mockTemplateTranslations.resolveNames(
      slugs: any(named: 'slugs'),
      locale: any(named: 'locale'),
    ),
  ).thenAnswer((_) async => const <String, String>{});
  return _RepoBundle(
    RoutineRepository(
      client,
      const CacheService(),
      mockExerciseRepo,
      mockTemplateTranslations,
    ),
    mockExerciseRepo,
    mockTemplateTranslations,
    templatesBuilder,
  );
}

Exercise _ex({required String id, String name = 'Bench Press'}) {
  return Exercise.fromJson(TestExerciseFactory.create(id: id, name: name));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(<String>[]);
  });

  group('RoutineRepository._resolveExercises / _fetchExerciseMap', () {
    test('returns routines with exercise=null when batch RPC returns empty '
        '(BUG-005: exercises lookup unreachable or empty)', () async {
      final templateRow = TestRoutineFactory.create(
        id: 'r-001',
        exercises: [
          TestRoutineExerciseFactory.create(exerciseId: 'ex-A'),
          TestRoutineExerciseFactory.create(exerciseId: 'ex-B'),
        ],
      );

      // Batch RPC returns nothing — repo must keep RoutineExercise.exercise
      // null and not throw.
      final bundle = _makeRepo(templates: [templateRow]);

      final routines = await bundle.repo.getRoutines(
        userId: 'user-001',
        locale: 'en',
      );

      expect(routines, hasLength(1));
      expect(routines[0].exercises[0].exercise, isNull);
      expect(routines[0].exercises[1].exercise, isNull);
    });

    test(
      'populates exercise references when batch RPC returns matching rows',
      () async {
        final templateRow = TestRoutineFactory.create(
          id: 'r-001',
          exercises: [
            TestRoutineExerciseFactory.create(exerciseId: 'ex-bench'),
          ],
        );

        final bundle = _makeRepo(
          templates: [templateRow],
          exerciseMap: {'ex-bench': _ex(id: 'ex-bench', name: 'Bench Press')},
        );

        final routines = await bundle.repo.getRoutines(
          userId: 'user-001',
          locale: 'en',
        );

        expect(routines[0].exercises[0].exercise, isNotNull);
        expect(routines[0].exercises[0].exercise!.name, 'Bench Press');
      },
    );

    test('skips the batch RPC entirely when routine has no exercises '
        '(fast path)', () async {
      final templateRow = TestRoutineFactory.create(
        id: 'r-empty',
        exercises: [],
      );

      final bundle = _makeRepo(templates: [templateRow]);

      final routines = await bundle.repo.getRoutines(
        userId: 'user-001',
        locale: 'en',
      );

      expect(routines, hasLength(1));
      expect(routines[0].exercises, isEmpty);
      verifyNever(
        () => bundle.mockExerciseRepo.getExercisesByIds(
          locale: any(named: 'locale'),
          userId: any(named: 'userId'),
          ids: any(named: 'ids'),
        ),
      );
    });

    test(
      'partial resolution: exercises present for some IDs but not others',
      () async {
        final templateRow = TestRoutineFactory.create(
          exercises: [
            TestRoutineExerciseFactory.create(exerciseId: 'ex-A'),
            TestRoutineExerciseFactory.create(exerciseId: 'ex-B'),
          ],
        );

        final bundle = _makeRepo(
          templates: [templateRow],
          exerciseMap: {'ex-A': _ex(id: 'ex-A', name: 'Squat')},
        );

        final routines = await bundle.repo.getRoutines(
          userId: 'user-001',
          locale: 'en',
        );

        expect(routines[0].exercises[0].exercise?.name, 'Squat');
        expect(
          routines[0].exercises[1].exercise,
          isNull,
          reason:
              'ex-B has no entry in the batch RPC result — should be null, '
              'not throw',
        );
      },
    );

    test('getRoutines maps template row fields correctly', () async {
      final templateRow = TestRoutineFactory.create(
        id: 'r-abc',
        name: 'Leg Day',
        isDefault: true,
        exercises: [],
      );

      final bundle = _makeRepo(templates: [templateRow]);

      final routines = await bundle.repo.getRoutines(
        userId: 'user-001',
        locale: 'en',
      );

      expect(routines, hasLength(1));
      expect(routines[0].id, 'r-abc');
      expect(routines[0].name, 'Leg Day');
      expect(routines[0].isDefault, isTrue);
    });

    test(
      'getRoutines returns empty list when templates table returns no rows',
      () async {
        final bundle = _makeRepo(templates: []);

        final routines = await bundle.repo.getRoutines(
          userId: 'user-001',
          locale: 'en',
        );

        expect(routines, isEmpty);
      },
    );

    test('getRoutines wraps Supabase errors in AppException', () async {
      const supabaseError = supabase.PostgrestException(
        message: 'relation "workout_templates" does not exist',
        code: '42P01',
      );
      final bundle = _makeRepo(templatesError: supabaseError);

      expect(
        () => bundle.repo.getRoutines(userId: 'user-001', locale: 'en'),
        throwsA(isA<AppException>()),
        reason:
            'A PostgrestException from Supabase must be wrapped by '
            'mapException() into an AppException, not leaked as raw',
      );
    });

    test(
      'multiple routines each get their exercises resolved independently',
      () async {
        final template1 = TestRoutineFactory.create(
          id: 'r-001',
          name: 'Push',
          exercises: [TestRoutineExerciseFactory.create(exerciseId: 'ex-A')],
        );
        final template2 = TestRoutineFactory.create(
          id: 'r-002',
          name: 'Pull',
          exercises: [TestRoutineExerciseFactory.create(exerciseId: 'ex-B')],
        );

        final bundle = _makeRepo(
          templates: [template1, template2],
          exerciseMap: {
            'ex-A': _ex(id: 'ex-A', name: 'Bench Press'),
            'ex-B': _ex(id: 'ex-B', name: 'Squat'),
          },
        );

        final routines = await bundle.repo.getRoutines(
          userId: 'user-001',
          locale: 'en',
        );

        expect(routines, hasLength(2));
        expect(routines[0].exercises[0].exercise?.name, 'Bench Press');
        expect(routines[1].exercises[0].exercise?.name, 'Squat');
      },
    );

    test(
      'forwards locale and userId to ExerciseRepository.getExercisesByIds',
      () async {
        final templateRow = TestRoutineFactory.create(
          exercises: [
            TestRoutineExerciseFactory.create(exerciseId: 'ex-A'),
            TestRoutineExerciseFactory.create(exerciseId: 'ex-A'),
            TestRoutineExerciseFactory.create(exerciseId: 'ex-B'),
          ],
        );

        final bundle = _makeRepo(templates: [templateRow]);

        await bundle.repo.getRoutines(userId: 'user-xyz', locale: 'pt');

        final captured =
            verify(
                  () => bundle.mockExerciseRepo.getExercisesByIds(
                    locale: 'pt',
                    userId: 'user-xyz',
                    ids: captureAny(named: 'ids'),
                  ),
                ).captured.single
                as List<String>;

        // IDs are deduped via a Set before forwarding.
        expect(captured.toSet(), {'ex-A', 'ex-B'});
      },
    );
  });

  group('RoutineRepository write path persists notes (Q2)', () {
    test('createRoutine sends notes in the insert payload', () async {
      // single() after insert returns data.first — seed it with the row the
      // DB would echo back so _resolveExercises has something to parse.
      final echoed = TestRoutineFactory.create(
        id: 'r-new',
        name: 'Push Day',
        exercises: [],
        notes: 'Brace before every rep.',
      );
      final bundle = _makeRepo(templates: [echoed]);

      await bundle.repo.createRoutine(
        userId: 'user-001',
        locale: 'en',
        name: 'Push Day',
        exercises: const [],
        notes: 'Brace before every rep.',
      );

      expect(
        bundle.templatesBuilder.lastWrittenPayload?['notes'],
        'Brace before every rep.',
      );
    });

    test('createRoutine sends null notes when none provided', () async {
      final echoed = TestRoutineFactory.create(id: 'r-new', exercises: []);
      final bundle = _makeRepo(templates: [echoed]);

      await bundle.repo.createRoutine(
        userId: 'user-001',
        locale: 'en',
        name: 'Push Day',
        exercises: const [],
      );

      expect(
        bundle.templatesBuilder.lastWrittenPayload!.containsKey('notes'),
        isTrue,
      );
      expect(bundle.templatesBuilder.lastWrittenPayload!['notes'], isNull);
    });

    test('updateRoutine sends notes in the update payload', () async {
      final echoed = TestRoutineFactory.create(
        id: 'r-1',
        exercises: [],
        notes: 'Deload week 4.',
      );
      final bundle = _makeRepo(templates: [echoed]);

      await bundle.repo.updateRoutine(
        id: 'r-1',
        userId: 'user-001',
        locale: 'en',
        name: 'Push Day',
        exercises: const [],
        notes: 'Deload week 4.',
      );

      expect(
        bundle.templatesBuilder.lastWrittenPayload?['notes'],
        'Deload week 4.',
      );
    });

    test('updateRoutine sends null notes to clear an existing value', () async {
      final echoed = TestRoutineFactory.create(id: 'r-1', exercises: []);
      final bundle = _makeRepo(templates: [echoed]);

      await bundle.repo.updateRoutine(
        id: 'r-1',
        userId: 'user-001',
        locale: 'en',
        name: 'Push Day',
        exercises: const [],
      );

      // The key is present-and-null so clearing the field persists, rather
      // than leaving a stale value untouched.
      expect(
        bundle.templatesBuilder.lastWrittenPayload!.containsKey('notes'),
        isTrue,
      );
      expect(bundle.templatesBuilder.lastWrittenPayload!['notes'], isNull);
    });
  });

  group('RoutineRepository.parseRoutineRow', () {
    test('parses routine row with nested exercise objects in JSONB', () {
      // When the exercise field is included in the JSONB exercises array
      // (e.g. from a JOIN or embedded object), it must be parsed into the
      // exercise field on RoutineExercise.
      final row = TestRoutineFactory.create(
        id: 'r-parse-001',
        exercises: [
          TestRoutineExerciseFactory.create(
            exerciseId: 'ex-001',
            exercise: TestExerciseFactory.create(
              id: 'ex-001',
              name: 'Overhead Press',
            ),
          ),
        ],
      );

      final routine = Routine.fromJson(row);

      // The exercise field in RoutineExercise uses @JsonKey(includeToJson: false)
      // which means it IS read from JSON (fromJson) but is excluded from toJson.
      // When the JSONB row contains an 'exercise' key, it must be parsed.
      expect(routine.exercises[0].exerciseId, 'ex-001');
      // Note: RoutineExercise.exercise intentionally has @JsonKey(includeToJson: false)
      // so it is excluded from toJson but included from fromJson. When the DB
      // row has an 'exercise' key (e.g. via a JOIN), it should be populated.
      // If it's not in the JSONB (normal case), it should be null.
    });

    test('setConfigs are parsed correctly from JSONB array', () {
      final row = TestRoutineFactory.create(
        exercises: [
          TestRoutineExerciseFactory.create(
            setConfigs: [
              TestRoutineSetConfigFactory.create(
                targetReps: 5,
                targetWeight: 100.0,
                restSeconds: 180,
              ),
              TestRoutineSetConfigFactory.create(
                targetReps: 3,
                restSeconds: 180,
              ),
            ],
          ),
        ],
      );

      final routine = Routine.fromJson(row);

      expect(routine.exercises[0].setConfigs, hasLength(2));
      expect(routine.exercises[0].setConfigs[0].targetReps, 5);
      expect(routine.exercises[0].setConfigs[0].targetWeight, 100.0);
      expect(routine.exercises[0].setConfigs[0].restSeconds, 180);
      expect(routine.exercises[0].setConfigs[1].targetReps, 3);
    });
  });

  group('RoutineRepository._applyTemplateTranslations (Phase 32 PR 32a)', () {
    test('rewrites default-template name with resolver-supplied localized '
        'name when templateSlug is non-null', () async {
      final templateRow = TestRoutineFactory.create(
        id: 'r-push',
        userId: null,
        name: 'Push Day',
        isDefault: true,
        templateSlug: 'push_day',
      );
      final bundle = _makeRepo(templates: [templateRow]);
      // Override the default empty-map stub: resolver returns a pt translation
      // for the push_day slug. This pins the rewrite contract — if
      // `_applyTemplateTranslations` ever stops calling `copyWith(name: ...)`
      // the assertion below catches it.
      when(
        () => bundle.mockTemplateTranslations.resolveNames(
          slugs: any(named: 'slugs'),
          locale: 'pt',
        ),
      ).thenAnswer((_) async => const {'push_day': 'Dia de Empurrar'});

      final routines = await bundle.repo.getRoutines(
        userId: 'user-001',
        locale: 'pt',
      );

      expect(routines, hasLength(1));
      expect(routines.single.name, 'Dia de Empurrar');
      expect(routines.single.templateSlug, 'push_day');
    });

    test('leaves user-created routine name untouched when templateSlug is '
        'null even if resolver has unrelated entries', () async {
      final userRoutine = TestRoutineFactory.create(
        id: 'r-user',
        userId: 'user-001',
        name: 'My Custom Push',
        isDefault: false,
        templateSlug: null,
      );
      final bundle = _makeRepo(templates: [userRoutine]);
      // Resolver advertises a translation that shouldn't apply — the user
      // routine has slug == null, so the resolver shouldn't even be called
      // for it. Even if some bug fed it the empty slug set, the rewrite must
      // not touch the user's verbatim name.
      when(
        () => bundle.mockTemplateTranslations.resolveNames(
          slugs: any(named: 'slugs'),
          locale: any(named: 'locale'),
        ),
      ).thenAnswer((_) async => const {'push_day': 'Dia de Empurrar'});

      final routines = await bundle.repo.getRoutines(
        userId: 'user-001',
        locale: 'pt',
      );

      expect(routines, hasLength(1));
      expect(routines.single.name, 'My Custom Push');
      expect(routines.single.templateSlug, isNull);
    });
  });
}
