import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/exceptions/app_exception.dart' as app;
import 'package:repsaga/features/profile/data/profile_repository.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

// ---------------------------------------------------------------------------
// Fake Supabase infrastructure
//
// ProfileRepository uses the following chains:
//   getProfile:      .from('profiles').select().eq('id', userId).maybeSingle()
//   upsertProfile:   .from('profiles').upsert(data).select().single()
//   updateWeightUnit:.from('profiles').update(data).eq('id', userId)
// ---------------------------------------------------------------------------

class _FakeSupabaseClient extends Fake implements supabase.SupabaseClient {
  _FakeSupabaseClient(this._builder);
  final _FakeQueryBuilder _builder;

  @override
  supabase.SupabaseQueryBuilder from(String table) => _builder;
}

// ignore: must_be_immutable
class _FakeQueryBuilder extends Fake implements supabase.SupabaseQueryBuilder {
  _FakeQueryBuilder({required this.singleResult, this.error});

  /// Returned by `.maybeSingle()` and `.single()`.
  final Map<String, dynamic>? singleResult;
  final Exception? error;

  final List<String> calledMethods = [];
  Map<String, dynamic>? capturedUpsert;
  Map<String, dynamic>? capturedUpdate;

  @override
  _FakeFilterBuilder<List<Map<String, dynamic>>> select([
    String columns = '*',
  ]) {
    calledMethods.add('select');
    return _FakeFilterBuilder<List<Map<String, dynamic>>>(this);
  }

  @override
  _FakeFilterBuilder<List<Map<String, dynamic>>> upsert(
    dynamic values, {
    String? onConflict,
    bool ignoreDuplicates = false,
    bool defaultToNull = true,
  }) {
    calledMethods.add('upsert');
    capturedUpsert = Map<String, dynamic>.from(values as Map);
    return _FakeFilterBuilder<List<Map<String, dynamic>>>(this);
  }

  @override
  _FakeFilterBuilder<List<Map<String, dynamic>>> update(Map values) {
    calledMethods.add('update');
    capturedUpdate = Map<String, dynamic>.from(values);
    return _FakeFilterBuilder<List<Map<String, dynamic>>>(this);
  }
}

class _FakeFilterBuilder<T> extends Fake
    implements supabase.PostgrestFilterBuilder<T> {
  _FakeFilterBuilder(this._parent);

  final _FakeQueryBuilder _parent;

  @override
  _FakeFilterBuilder<T> eq(String column, Object value) {
    _parent.calledMethods.add('eq:$column=$value');
    return this;
  }

  @override
  _FakeFilterBuilder<List<Map<String, dynamic>>> select([
    String columns = '*',
  ]) {
    _parent.calledMethods.add('chainSelect');
    return _FakeFilterBuilder<List<Map<String, dynamic>>>(_parent);
  }

  @override
  _FakeSingleBuilder<Map<String, dynamic>?> maybeSingle() {
    _parent.calledMethods.add('maybeSingle');
    return _FakeSingleBuilder<Map<String, dynamic>?>(_parent, nullable: true);
  }

  @override
  _FakeSingleBuilder<Map<String, dynamic>> single() {
    _parent.calledMethods.add('single');
    return _FakeSingleBuilder<Map<String, dynamic>>(_parent, nullable: false);
  }

  @override
  Future<S> then<S>(FutureOr<S> Function(T) onValue, {Function? onError}) {
    if (_parent.error != null) {
      return Future<T>.error(_parent.error!).then<S>(onValue, onError: onError);
    }
    // For update() the caller awaits the builder itself (no terminal method).
    return Future.value(onValue(<Map<String, dynamic>>[] as T));
  }
}

class _FakeSingleBuilder<T> extends Fake
    implements supabase.PostgrestTransformBuilder<T> {
  _FakeSingleBuilder(this._parent, {required this.nullable});

  final _FakeQueryBuilder _parent;
  final bool nullable;

  @override
  Future<S> then<S>(FutureOr<S> Function(T) onValue, {Function? onError}) {
    if (_parent.error != null) {
      return Future<T>.error(_parent.error!).then<S>(onValue, onError: onError);
    }
    final result = _parent.singleResult as T;
    return Future.value(onValue(result));
  }
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

ProfileRepository _makeRepo({Map<String, dynamic>? row, Exception? error}) {
  final builder = _FakeQueryBuilder(singleResult: row, error: error);
  return ProfileRepository(_FakeSupabaseClient(builder));
}

_FakeQueryBuilder _builderFor({Map<String, dynamic>? row, Exception? error}) {
  return _FakeQueryBuilder(singleResult: row, error: error);
}

Map<String, dynamic> _profileRow({
  String id = 'user-123',
  String? displayName = 'Test User',
  String? fitnessLevel = 'beginner',
  String weightUnit = 'kg',
}) {
  return {
    'id': id,
    'display_name': displayName,
    'fitness_level': fitnessLevel,
    'weight_unit': weightUnit,
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ProfileRepository', () {
    // -------------------------------------------------------------------
    // getProfile
    // -------------------------------------------------------------------
    group('getProfile', () {
      test('returns Profile when a row is found', () async {
        final repo = _makeRepo(row: _profileRow());

        final result = await repo.getProfile('user-123');

        expect(result, isA<Profile>());
        expect(result!.id, 'user-123');
        expect(result.displayName, 'Test User');
        expect(result.weightUnit, 'kg');
      });

      test(
        'returns null when no row is found (maybeSingle returns null)',
        () async {
          final repo = _makeRepo(row: null);

          final result = await repo.getProfile('user-not-found');

          expect(result, isNull);
        },
      );

      test(
        'queries the profiles table with correct userId eq filter',
        () async {
          final builder = _builderFor(row: _profileRow());
          final repo = ProfileRepository(_FakeSupabaseClient(builder));

          await repo.getProfile('user-abc');

          expect(builder.calledMethods, contains('eq:id=user-abc'));
          expect(builder.calledMethods, contains('maybeSingle'));
        },
      );

      test('maps Supabase exception to AppException', () async {
        final repo = _makeRepo(
          error: const supabase.PostgrestException(message: 'connection error'),
        );

        expect(
          () => repo.getProfile('user-123'),
          throwsA(isA<app.AppException>()),
        );
      });
    });

    // -------------------------------------------------------------------
    // upsertProfile
    // -------------------------------------------------------------------
    group('upsertProfile', () {
      test('returns Profile from upserted row', () async {
        final row = _profileRow(
          id: 'user-1',
          displayName: 'Alice',
          fitnessLevel: 'intermediate',
        );
        final repo = _makeRepo(row: row);

        final result = await repo.upsertProfile(
          userId: 'user-1',
          displayName: 'Alice',
          fitnessLevel: 'intermediate',
        );

        expect(result, isA<Profile>());
        expect(result.id, 'user-1');
        expect(result.displayName, 'Alice');
        expect(result.fitnessLevel, 'intermediate');
      });

      test(
        'upsert payload includes id and display_name when provided',
        () async {
          final builder = _builderFor(row: _profileRow());
          final repo = ProfileRepository(_FakeSupabaseClient(builder));

          await repo.upsertProfile(userId: 'user-1', displayName: 'Bob');

          expect(builder.capturedUpsert, isNotNull);
          expect(builder.capturedUpsert!['id'], 'user-1');
          expect(builder.capturedUpsert!['display_name'], 'Bob');
        },
      );

      test('omits display_name from payload when null', () async {
        final builder = _builderFor(row: _profileRow());
        final repo = ProfileRepository(_FakeSupabaseClient(builder));

        await repo.upsertProfile(userId: 'user-1', fitnessLevel: 'beginner');

        expect(builder.capturedUpsert!.containsKey('display_name'), isFalse);
        expect(builder.capturedUpsert!['fitness_level'], 'beginner');
      });

      test('omits fitness_level from payload when null', () async {
        final builder = _builderFor(row: _profileRow());
        final repo = ProfileRepository(_FakeSupabaseClient(builder));

        await repo.upsertProfile(userId: 'user-1', weightUnit: 'lbs');

        expect(builder.capturedUpsert!.containsKey('fitness_level'), isFalse);
        expect(builder.capturedUpsert!['weight_unit'], 'lbs');
      });

      test('includes locale in upsert payload when provided', () async {
        final builder = _builderFor(row: _profileRow());
        final repo = ProfileRepository(_FakeSupabaseClient(builder));

        await repo.upsertProfile(userId: 'user-1', locale: 'pt');

        expect(builder.capturedUpsert, isNotNull);
        expect(builder.capturedUpsert!['locale'], 'pt');
      });

      test('omits locale from payload when null', () async {
        final builder = _builderFor(row: _profileRow());
        final repo = ProfileRepository(_FakeSupabaseClient(builder));

        await repo.upsertProfile(userId: 'user-1', displayName: 'Bob');

        expect(builder.capturedUpsert!.containsKey('locale'), isFalse);
      });

      // ---------------------------------------------------------------
      // Phase 24c — bodyweight_kg parameter
      //
      // Same omit-on-null discipline as the other optional params: a
      // missing arg must NOT clobber the row's existing bodyweight.
      // The SQL `record_xp` RPC tolerates a null/missing column (falls
      // back to a zero bodyweight contribution) but the upsert payload
      // would write null, overwriting any stored value, if we forwarded
      // the param unconditionally.
      // ---------------------------------------------------------------
      test('includes bodyweight_kg in upsert payload when provided', () async {
        final builder = _builderFor(row: _profileRow());
        final repo = ProfileRepository(_FakeSupabaseClient(builder));

        await repo.upsertProfile(userId: 'user-1', bodyweightKg: 70.5);

        expect(builder.capturedUpsert, isNotNull);
        expect(builder.capturedUpsert!['bodyweight_kg'], 70.5);
      });

      test('omits bodyweight_kg from payload when null', () async {
        final builder = _builderFor(row: _profileRow());
        final repo = ProfileRepository(_FakeSupabaseClient(builder));

        await repo.upsertProfile(userId: 'user-1', displayName: 'Bob');

        expect(
          builder.capturedUpsert!.containsKey('bodyweight_kg'),
          isFalse,
          reason:
              'Forwarding null would clobber the stored bodyweight on every '
              'unrelated profile update; the key must be omitted entirely.',
        );
      });

      test('maps Supabase exception to AppException', () async {
        final repo = _makeRepo(
          error: const supabase.PostgrestException(message: 'unique violation'),
        );

        expect(
          () => repo.upsertProfile(userId: 'user-1'),
          throwsA(isA<app.AppException>()),
        );
      });
    });

    // -------------------------------------------------------------------
    // updateLocale
    // -------------------------------------------------------------------
    group('updateLocale', () {
      test('calls update with locale value and eq filter for userId', () async {
        final builder = _builderFor(row: null);
        final repo = ProfileRepository(_FakeSupabaseClient(builder));

        await repo.updateLocale('user-1', 'pt');

        expect(builder.calledMethods, contains('update'));
        expect(builder.calledMethods, contains('eq:id=user-1'));
        expect(builder.capturedUpdate, isNotNull);
        expect(builder.capturedUpdate!['locale'], 'pt');
      });

      test('completes without error on success', () async {
        final repo = _makeRepo(row: null);

        await expectLater(
          () => repo.updateLocale('user-1', 'en'),
          returnsNormally,
        );
      });

      test('maps Supabase exception to AppException', () async {
        final repo = _makeRepo(
          error: const supabase.PostgrestException(message: 'rls violation'),
        );

        expect(
          () => repo.updateLocale('user-1', 'pt'),
          throwsA(isA<app.AppException>()),
        );
      });
    });

    // -------------------------------------------------------------------
    // updateWeightUnit
    // -------------------------------------------------------------------
    group('updateWeightUnit', () {
      test(
        'calls update with weight_unit value and eq filter for userId',
        () async {
          final builder = _builderFor(row: null);
          final repo = ProfileRepository(_FakeSupabaseClient(builder));

          await repo.updateWeightUnit('user-1', 'lbs');

          expect(builder.calledMethods, contains('update'));
          expect(builder.calledMethods, contains('eq:id=user-1'));
          expect(builder.capturedUpdate, isNotNull);
          expect(builder.capturedUpdate!['weight_unit'], 'lbs');
        },
      );

      test('completes without error on success', () async {
        final repo = _makeRepo(row: null);

        await expectLater(
          () => repo.updateWeightUnit('user-1', 'kg'),
          returnsNormally,
        );
      });

      test('maps Supabase exception to AppException', () async {
        final repo = _makeRepo(
          error: const supabase.PostgrestException(message: 'rls violation'),
        );

        expect(
          () => repo.updateWeightUnit('user-1', 'kg'),
          throwsA(isA<app.AppException>()),
        );
      });
    });
  });
}
