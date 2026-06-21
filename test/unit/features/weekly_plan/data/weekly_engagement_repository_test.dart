/// Unit tests for [WeeklyEngagementRepository].
///
/// cluster: jsonb-payload-vs-typed-dart
///
/// The repository extracts the per-body-part "done" set counts from the
/// nested `sets → workout_exercises → exercises` JSONB join. Pre-fix this
/// logic lived inline in `weeklyEngagementProvider` as raw `as Map` casts with
/// no `mapException` boundary, so a single drifted/null nested object threw a
/// raw `_TypeError` that stormed Riverpod's default retry. These tests pin two
/// user-perceptible contracts:
///   1. Happy path — well-formed rows produce the right per-body-part counts.
///   2. Malformed row — a wrong-typed `xp_attribution` share surfaces as a
///      typed [DatabaseException] (the failure the user CAN recover from /
///      that does NOT storm a retry), never a raw `_TypeError`.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/exceptions/app_exception.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/weekly_plan/data/weekly_engagement_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Fake Supabase client that returns a canned row list from the `sets` query
/// chain. The repo's chain is
/// `from('sets').select(...).eq(...).gte(...).eq(...)` awaited as a list, so
/// the filter builder returns itself for every filter call and resolves to
/// [_rows].
class _FakeSupabaseClient extends Fake implements supabase.SupabaseClient {
  _FakeSupabaseClient(this._rows);
  final List<Map<String, dynamic>> _rows;

  @override
  supabase.SupabaseQueryBuilder from(String table) => _FakeQueryBuilder(_rows);
}

class _FakeQueryBuilder extends Fake implements supabase.SupabaseQueryBuilder {
  _FakeQueryBuilder(this._rows);
  final List<Map<String, dynamic>> _rows;

  @override
  supabase.PostgrestFilterBuilder<supabase.PostgrestList> select([
    String columns = '*',
  ]) {
    return _FakeFilterBuilder(_rows);
  }
}

/// Returns itself for `.eq`/`.gte` and resolves (via [then]) to the canned
/// rows when awaited. Only the methods the repo actually calls are
/// implemented; everything else hits [noSuchMethod] and would fail loudly.
class _FakeFilterBuilder extends Fake
    implements supabase.PostgrestFilterBuilder<supabase.PostgrestList> {
  _FakeFilterBuilder(this._rows);
  final List<Map<String, dynamic>> _rows;

  @override
  supabase.PostgrestFilterBuilder<supabase.PostgrestList> eq(
    String column,
    Object value,
  ) => this;

  @override
  supabase.PostgrestFilterBuilder<supabase.PostgrestList> gte(
    String column,
    Object value,
  ) => this;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(supabase.PostgrestList value) onValue, {
    Function? onError,
  }) {
    // The repo awaits the builder; the awaited value is the row list.
    return Future<supabase.PostgrestList>.value(
      _rows,
    ).then(onValue, onError: onError);
  }
}

Map<String, dynamic> _row({
  String setType = 'working',
  int reps = 8,
  bool completed = true,
  Map<String, dynamic>? exercise,
}) {
  return <String, dynamic>{
    'is_completed': completed,
    'set_type': setType,
    'reps': reps,
    'workout_exercises': <String, dynamic>{
      'workout_id': 'w-1',
      'exercise': exercise,
      'workouts': <String, dynamic>{
        'user_id': 'u-1',
        'finished_at': '2026-06-15T10:00:00Z',
      },
    },
  };
}

Map<String, dynamic> _exercise({
  Map<String, dynamic>? xpAttribution,
  String? muscleGroup,
}) {
  return <String, dynamic>{
    'xp_attribution': xpAttribution,
    'muscle_group': muscleGroup,
  };
}

void main() {
  group('WeeklyEngagementRepository.getDoneCounts — happy path', () {
    test(
      'credits the max-share body part for each completed working set',
      () async {
        final rows = <Map<String, dynamic>>[
          // Two chest-dominant sets.
          _row(
            exercise: _exercise(
              xpAttribution: {'chest': 0.7, 'triceps': 0.3},
              muscleGroup: 'chest',
            ),
          ),
          _row(
            exercise: _exercise(
              xpAttribution: {'chest': 0.6, 'shoulders': 0.4},
              muscleGroup: 'chest',
            ),
          ),
          // One back set (falls back to muscle_group when attribution null).
          _row(exercise: _exercise(muscleGroup: 'back')),
        ];
        final repo = WeeklyEngagementRepository(_FakeSupabaseClient(rows));

        final counts = await repo.getDoneCounts(
          userId: 'u-1',
          mondayStr: '2026-06-15',
        );

        expect(counts[BodyPart.chest], 2);
        expect(counts[BodyPart.back], 1);
        expect(counts[BodyPart.shoulders], isNull);
      },
    );

    test('skips warm-up sets and zero-rep rows', () async {
      final rows = <Map<String, dynamic>>[
        _row(
          setType: 'warmup',
          exercise: _exercise(muscleGroup: 'chest'),
        ),
        _row(reps: 0, exercise: _exercise(muscleGroup: 'chest')),
        _row(exercise: _exercise(muscleGroup: 'chest')), // the only credit
      ];
      final repo = WeeklyEngagementRepository(_FakeSupabaseClient(rows));

      final counts = await repo.getDoneCounts(
        userId: 'u-1',
        mondayStr: '2026-06-15',
      );

      expect(counts[BodyPart.chest], 1);
    });

    test('skips rows with no reachable exercise without crashing', () async {
      final rows = <Map<String, dynamic>>[
        _row(exercise: null), // exercise join absent
        _row(exercise: _exercise(muscleGroup: 'back')),
      ];
      final repo = WeeklyEngagementRepository(_FakeSupabaseClient(rows));

      final counts = await repo.getDoneCounts(
        userId: 'u-1',
        mondayStr: '2026-06-15',
      );

      expect(counts[BodyPart.back], 1);
    });
  });

  group('WeeklyEngagementRepository.getDoneCounts — malformed rows', () {
    test('a non-numeric xp_attribution share surfaces a typed '
        'DatabaseException, not a raw _TypeError', () async {
      final rows = <Map<String, dynamic>>[
        _row(
          exercise: _exercise(
            // Drifted JSONB: a share is a String instead of a number. Pre-fix
            // the inline `v as num` threw a raw _TypeError that stormed the
            // retry; now it is a typed DatabaseException.
            xpAttribution: {'chest': 'not-a-number'},
            muscleGroup: 'chest',
          ),
        ),
      ];
      final repo = WeeklyEngagementRepository(_FakeSupabaseClient(rows));

      await expectLater(
        repo.getDoneCounts(userId: 'u-1', mondayStr: '2026-06-15'),
        throwsA(
          isA<DatabaseException>().having(
            (e) => e.code,
            'code',
            'deserialization',
          ),
        ),
      );
    });

    test(
      'a wrong-typed reps field surfaces a typed DatabaseException',
      () async {
        final rows = <Map<String, dynamic>>[
          // `reps` arrives as a String — json_helpers.optionalField throws a
          // typed DatabaseException (json_wrong_type) instead of an `as int?`
          // _TypeError.
          _row(exercise: _exercise(muscleGroup: 'chest'))..['reps'] = 'eight',
        ];
        final repo = WeeklyEngagementRepository(_FakeSupabaseClient(rows));

        await expectLater(
          repo.getDoneCounts(userId: 'u-1', mondayStr: '2026-06-15'),
          throwsA(isA<DatabaseException>()),
        );
      },
    );
  });
}
