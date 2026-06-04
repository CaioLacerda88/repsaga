import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/local_storage/cache_service.dart';
import 'package:repsaga/features/exercises/data/exercise_repository.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class _MockExerciseRepository extends Mock implements ExerciseRepository {}

// ---------------------------------------------------------------------------
// Fake Supabase infrastructure for WorkoutRepository.clearHistory
// ---------------------------------------------------------------------------

class FakeSupabaseClient extends Fake implements supabase.SupabaseClient {
  FakeSupabaseClient(this.fakeBuilder);
  final FakeQueryBuilder fakeBuilder;

  @override
  supabase.SupabaseQueryBuilder from(String table) {
    fakeBuilder.queriedTable = table;
    return fakeBuilder;
  }
}

// ignore: must_be_immutable
class FakeQueryBuilder extends Fake implements supabase.SupabaseQueryBuilder {
  FakeQueryBuilder({this.error});

  final Exception? error;
  String? queriedTable;
  final List<String> calledMethods = [];

  @override
  FakeFilterBuilder delete() {
    calledMethods.add('delete');
    return FakeFilterBuilder(this);
  }
}

class FakeFilterBuilder extends Fake
    implements supabase.PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  FakeFilterBuilder(this._parent);

  final FakeQueryBuilder _parent;

  @override
  FakeFilterBuilder eq(String column, Object value) {
    _parent.calledMethods.add('eq:$column=$value');
    return this;
  }

  @override
  FakeFilterBuilder not(String column, String operator, Object? value) {
    _parent.calledMethods.add('not:$column.$operator=$value');
    return this;
  }

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
    return Future.value(onValue(const []));
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('WorkoutRepository.clearHistory', () {
    test('deletes finished non-active workouts for a user', () async {
      final fakeBuilder = FakeQueryBuilder();
      final repo = WorkoutRepository(
        FakeSupabaseClient(fakeBuilder),
        const CacheService(),
        _MockExerciseRepository(),
      );

      await repo.clearHistory('user-001');

      expect(fakeBuilder.queriedTable, 'workouts');
      expect(fakeBuilder.calledMethods, contains('delete'));
      expect(fakeBuilder.calledMethods, contains('eq:user_id=user-001'));
      expect(fakeBuilder.calledMethods, contains('eq:is_active=false'));
      expect(fakeBuilder.calledMethods, contains('not:finished_at.is=null'));
    });

    test('does NOT delete active workouts', () async {
      final fakeBuilder = FakeQueryBuilder();
      final repo = WorkoutRepository(
        FakeSupabaseClient(fakeBuilder),
        const CacheService(),
        _MockExerciseRepository(),
      );

      await repo.clearHistory('user-001');

      // Verify the is_active=false filter is present.
      expect(fakeBuilder.calledMethods, contains('eq:is_active=false'));
    });

    test('uses mapException pattern', () async {
      final fakeBuilder = FakeQueryBuilder(
        error: Exception('Connection failed'),
      );
      final repo = WorkoutRepository(
        FakeSupabaseClient(fakeBuilder),
        const CacheService(),
        _MockExerciseRepository(),
      );

      expect(() => repo.clearHistory('user-001'), throwsA(isA<Exception>()));
    });

    // Cluster: data-protection-compliance. The Reset All affordance must
    // drop the `is_active = false` + `finished_at IS NOT NULL` filters so
    // an in-progress / draft workout cannot survive the reset and be
    // resurrected by a subsequent sign-in. Default callers (Delete
    // Workout History affordance) MUST still preserve the filters.
    group('includeActive: true (Reset All path)', () {
      test('drops is_active filter so draft workouts are deleted', () async {
        final fakeBuilder = FakeQueryBuilder();
        final repo = WorkoutRepository(
          FakeSupabaseClient(fakeBuilder),
          const CacheService(),
          _MockExerciseRepository(),
        );

        await repo.clearHistory('user-001', includeActive: true);

        expect(fakeBuilder.queriedTable, 'workouts');
        expect(fakeBuilder.calledMethods, contains('delete'));
        expect(fakeBuilder.calledMethods, contains('eq:user_id=user-001'));
        // The active-workout filter MUST NOT be applied — that's the bug
        // this PR closes.
        expect(
          fakeBuilder.calledMethods,
          isNot(contains('eq:is_active=false')),
        );
        // And the finished_at filter MUST NOT be applied either — drafts
        // (finished_at IS NULL) are part of the "all" set.
        expect(
          fakeBuilder.calledMethods,
          isNot(contains('not:finished_at.is=null')),
        );
      });

      test(
        'default (no includeActive) still preserves the finished-only contract',
        () async {
          // Regression guard for the Delete Workout History affordance.
          // That flow's user-facing copy ("Your active workout is not
          // affected") depends on this filter staying on the default
          // call path.
          final fakeBuilder = FakeQueryBuilder();
          final repo = WorkoutRepository(
            FakeSupabaseClient(fakeBuilder),
            const CacheService(),
            _MockExerciseRepository(),
          );

          await repo.clearHistory('user-001');

          expect(fakeBuilder.calledMethods, contains('eq:is_active=false'));
          expect(
            fakeBuilder.calledMethods,
            contains('not:finished_at.is=null'),
          );
        },
      );
    });
  });
}
