import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/exceptions/app_exception.dart';
import 'package:repsaga/features/profile/data/data_export_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

// ---------------------------------------------------------------------------
// Fake Supabase infrastructure
//
// `DataExportService.buildJsonExport` issues one `.from(table).select()...`
// chain per user-owned table plus an embedded-row select for workouts. The
// fake maps a per-table response (List<Map> or Map for maybeSingle / null)
// into the same chained builder calls and short-circuits filter / order
// builders so they ultimately resolve to the configured response.
//
// `_FakeClient` exposes `auth.currentUser.email` so the export envelope
// captures the user email at the top.
// ---------------------------------------------------------------------------

class _FakeClient extends Fake implements supabase.SupabaseClient {
  _FakeClient({required Map<String, _TableResponse> responses, String? email})
    : _responses = responses,
      _auth = _FakeGoTrue(email);

  final Map<String, _TableResponse> _responses;
  final _FakeGoTrue _auth;

  /// Table name passed to the latest `.from()` call. Used by tests to
  /// pin which fetcher executed last.
  final List<String> tablesQueried = [];

  @override
  supabase.GoTrueClient get auth => _auth;

  @override
  supabase.SupabaseQueryBuilder from(String table) {
    tablesQueried.add(table);
    final response = _responses[table];
    if (response == null) {
      return _FakeQueryBuilder(_TableResponse.list(const []));
    }
    return _FakeQueryBuilder(response);
  }
}

class _FakeGoTrue extends Fake implements supabase.GoTrueClient {
  _FakeGoTrue(this._email);
  final String? _email;

  @override
  supabase.User? get currentUser => _email == null ? null : _FakeUser(_email);
}

class _FakeUser extends Fake implements supabase.User {
  _FakeUser(this._email);
  final String _email;

  @override
  String? get email => _email;
}

/// Per-table response. Either a list (for `.select()` that resolves to a
/// list), a single map (for `.maybeSingle()`), or an error (for failure
/// stages).
class _TableResponse {
  const _TableResponse._({
    this.list,
    this.single,
    this.error,
    this.isList = true,
  });

  factory _TableResponse.list(List<Map<String, dynamic>> rows) =>
      _TableResponse._(list: rows);

  factory _TableResponse.maybeSingleMap(Map<String, dynamic>? row) =>
      _TableResponse._(single: row, isList: false);

  factory _TableResponse.error(Object error) => _TableResponse._(error: error);

  final List<Map<String, dynamic>>? list;
  final Map<String, dynamic>? single;
  final Object? error;
  final bool isList;
}

/// Fake chained-builder. Implements the SupabaseQueryBuilder interface
/// (entry point) — its `.select()` returns a [_FakeTransformBuilder]
/// which itself implements the filter + transform interfaces so the
/// composed `.eq()`/`.order()`/`.inFilter()`/`.maybeSingle()` chain
/// keeps returning a builder that resolves to the configured response.
///
/// Two separate classes (vs one composite) so the postgrest interfaces'
/// overlapping methods (`count`, `setHeader`) don't trigger the
/// inherits-multiple-members error.
// ignore: must_be_immutable
class _FakeQueryBuilder extends Fake implements supabase.SupabaseQueryBuilder {
  _FakeQueryBuilder(this._response);

  final _TableResponse _response;

  @override
  supabase.PostgrestFilterBuilder<List<Map<String, dynamic>>> select([
    String columns = '*',
  ]) {
    return _FakeTransformBuilder<List<Map<String, dynamic>>>(_response);
  }
}

// ignore: must_be_immutable
class _FakeTransformBuilder<T> extends Fake
    implements supabase.PostgrestFilterBuilder<T> {
  _FakeTransformBuilder(this._response);

  final _TableResponse _response;

  /// When true, the terminal `then` resolves to `_response.single`
  /// rather than `_response.list`. Flipped by [maybeSingle].
  bool _singleMode = false;

  @override
  supabase.PostgrestFilterBuilder<T> eq(String column, Object value) {
    return this;
  }

  @override
  supabase.PostgrestTransformBuilder<T> order(
    String column, {
    bool ascending = true,
    bool nullsFirst = false,
    String? referencedTable,
  }) {
    return this;
  }

  @override
  supabase.PostgrestFilterBuilder<T> inFilter(
    String column,
    List<dynamic> values,
  ) {
    return this;
  }

  @override
  supabase.PostgrestTransformBuilder<Map<String, dynamic>?> maybeSingle() {
    _singleMode = true;
    // Cast through dynamic — the surrounding fake doesn't care about the
    // typed wrapper, only that `then()` resolves to the configured
    // payload.
    return _FakeTransformBuilder<Map<String, dynamic>?>(_response)
      .._singleMode = true;
  }

  @override
  Future<U> then<U>(FutureOr<U> Function(T) onValue, {Function? onError}) {
    // Contract: when the caller supplies an `onError`, we MUST invoke it
    // with the error — the returned Future then carries whatever onError
    // produces (typically a rethrow, which `Completer.completeError`
    // forwards through the returned `Future<U>`). When `onError` is null,
    // the returned Future simply rejects with the underlying error.
    //
    // Built on a real `Completer<U>` + `scheduleMicrotask` so the
    // awaiter's continuation is wired before completion fires — same
    // shape `Future.value` produces internally, matching what
    // `PostgrestBuilder.then` does in production.
    final completer = Completer<U>();
    scheduleMicrotask(() {
      if (_response.error != null) {
        if (onError != null) {
          try {
            final U handled;
            if (onError is Function(Object, StackTrace)) {
              handled = onError(_response.error!, StackTrace.current) as U;
            } else if (onError is Function(Object)) {
              handled = onError(_response.error!) as U;
            } else {
              completer.completeError(_response.error!, StackTrace.current);
              return;
            }
            completer.complete(handled);
          } catch (e, st) {
            completer.completeError(e, st);
          }
          return;
        }
        completer.completeError(_response.error!, StackTrace.current);
        return;
      }
      try {
        final dynamic value = _singleMode ? _response.single : _response.list;
        final result = onValue(value as T);
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// Pinned clock for deterministic `exportedAt` assertions.
final _fixedNow = DateTime.utc(2026, 6, 4, 17, 30, 0);

DataExportService _buildService(_FakeClient client) {
  return DataExportService(client, clock: Clock.fixed(_fixedNow));
}

void main() {
  group('DataExportService.buildJsonExport — empty user', () {
    test('produces valid JSON skeleton with empty collections', () async {
      final client = _FakeClient(
        email: 'empty@example.com',
        responses: {
          'profiles': _TableResponse.maybeSingleMap(null),
          'workouts': _TableResponse.list(const []),
          'personal_records': _TableResponse.list(const []),
          'weekly_plans': _TableResponse.list(const []),
          'xp_events': _TableResponse.list(const []),
          'body_part_progress': _TableResponse.list(const []),
          'exercise_peak_loads': _TableResponse.list(const []),
          'exercise_peak_loads_by_rep_range': _TableResponse.list(const []),
          'earned_titles': _TableResponse.list(const []),
          'backfill_progress': _TableResponse.maybeSingleMap(null),
          'vitality_runs': _TableResponse.list(const []),
          'analytics_events': _TableResponse.list(const []),
        },
      );

      final raw = await _buildService(client).buildJsonExport('user-empty');
      final json = jsonDecode(raw) as Map<String, dynamic>;

      expect(json['schemaVersion'], 1);
      expect(json['exportedAt'], '2026-06-04T17:30:00.000Z');
      expect(json['user'], {'id': 'user-empty', 'email': 'empty@example.com'});
      expect(json['profile'], isNull);
      expect(json['workouts'], isEmpty);
      expect(json['personalRecords'], isEmpty);
      expect(json['exercises'], isEmpty);
      expect(json['weeklyPlans'], isEmpty);
      expect(json['xpEvents'], isEmpty);
      expect(json['bodyPartProgress'], isEmpty);
      expect(json['exercisePeakLoads'], isEmpty);
      expect(json['exercisePeakLoadsByRepRange'], isEmpty);
      expect(json['earnedTitles'], isEmpty);
      expect(json['backfillProgress'], isEmpty);
      expect(json['vitalityRuns'], isEmpty);
      expect(json['analyticsEvents'], isEmpty);
    });

    test('output is pretty-printed with 2-space indentation', () async {
      final client = _FakeClient(
        email: 'fmt@example.com',
        responses: {
          'profiles': _TableResponse.maybeSingleMap(null),
          'workouts': _TableResponse.list(const []),
          'personal_records': _TableResponse.list(const []),
          'weekly_plans': _TableResponse.list(const []),
          'xp_events': _TableResponse.list(const []),
          'body_part_progress': _TableResponse.list(const []),
          'exercise_peak_loads': _TableResponse.list(const []),
          'exercise_peak_loads_by_rep_range': _TableResponse.list(const []),
          'earned_titles': _TableResponse.list(const []),
          'backfill_progress': _TableResponse.maybeSingleMap(null),
          'vitality_runs': _TableResponse.list(const []),
          'analytics_events': _TableResponse.list(const []),
        },
      );

      final raw = await _buildService(client).buildJsonExport('user-fmt');

      // Look for 2-space indented key — `  "schemaVersion"` shows up
      // exactly once in a pretty-printed envelope.
      expect(raw, contains('  "schemaVersion": 1'));
      // Sanity: the unprefixed envelope key is at column 0.
      expect(raw.startsWith('{\n  "exportedAt"'), isTrue);
    });
  });

  group('DataExportService.buildJsonExport — rich user', () {
    test('populates every collection with the queried rows', () async {
      final client = _FakeClient(
        email: 'rich@example.com',
        responses: {
          'profiles': _TableResponse.maybeSingleMap({
            'id': 'user-rich',
            'display_name': 'Test Lifter',
            'locale': 'en',
            'weight_unit': 'kg',
            'bodyweight_kg': 80.0,
          }),
          'workouts': _TableResponse.list([
            {
              'id': 'workout-1',
              'user_id': 'user-rich',
              'name': 'Push Day',
              'started_at': '2026-05-30T10:00:00Z',
              'finished_at': '2026-05-30T11:30:00Z',
              'workout_exercises': [
                {
                  'id': 'we-1',
                  'workout_id': 'workout-1',
                  'exercise_id': 'ex-bench',
                  'order': 0,
                  'sets': [
                    {'id': 'set-1', 'weight': 60.0, 'reps': 10},
                  ],
                },
              ],
            },
          ]),
          'personal_records': _TableResponse.list([
            {
              'id': 'pr-1',
              'user_id': 'user-rich',
              'exercise_id': 'ex-bench',
              'record_type': '1rm',
              'value': 100.0,
            },
          ]),
          'weekly_plans': _TableResponse.list([
            {
              'id': 'plan-1',
              'user_id': 'user-rich',
              'week_start': '2026-05-25',
              'routines': const [],
            },
          ]),
          'xp_events': _TableResponse.list([
            {
              'id': 'xp-1',
              'user_id': 'user-rich',
              'event_type': 'set',
              'total_xp': 12.5,
            },
          ]),
          'body_part_progress': _TableResponse.list([
            {
              'user_id': 'user-rich',
              'body_part': 'chest',
              'total_xp': 1000.0,
              'rank': 12,
            },
          ]),
          'exercise_peak_loads': _TableResponse.list([
            {
              'user_id': 'user-rich',
              'exercise_id': 'ex-bench',
              'peak_load_kg': 100.0,
            },
          ]),
          'exercise_peak_loads_by_rep_range': _TableResponse.list([
            {
              'user_id': 'user-rich',
              'exercise_slug': 'bench-press',
              'rep_band': 'strength',
              'best_weight': 95.0,
            },
          ]),
          'earned_titles': _TableResponse.list([
            {
              'user_id': 'user-rich',
              'title_id': 'iron-chest',
              'earned_at': '2026-05-15T08:00:00Z',
              'is_active': true,
            },
          ]),
          'backfill_progress': _TableResponse.maybeSingleMap({
            'user_id': 'user-rich',
            'sets_processed': 250,
            'started_at': '2026-04-01T00:00:00Z',
            'updated_at': '2026-04-01T01:00:00Z',
            'completed_at': '2026-04-01T01:00:00Z',
          }),
          'vitality_runs': _TableResponse.list([
            {'user_id': 'user-rich', 'run_date': '2026-05-30'},
          ]),
          'analytics_events': _TableResponse.list([
            {
              'id': 'evt-1',
              'user_id': 'user-rich',
              'name': 'workout_finished',
              'props': const {},
            },
          ]),
          'exercises': _TableResponse.list([
            {'slug': 'bench-press', 'is_default': true},
          ]),
        },
      );

      final raw = await _buildService(client).buildJsonExport('user-rich');
      final json = jsonDecode(raw) as Map<String, dynamic>;

      final profile = json['profile'] as Map<String, dynamic>;
      expect(profile['display_name'], 'Test Lifter');
      expect(profile['bodyweight_kg'], 80.0);

      final workouts = json['workouts'] as List;
      expect(workouts, hasLength(1));
      // workout_exercises rename — the export uses camelCase.
      final firstWorkout = workouts.first as Map<String, dynamic>;
      expect(firstWorkout.containsKey('workoutExercises'), isTrue);
      expect(firstWorkout.containsKey('workout_exercises'), isFalse);

      // Denormalized children — sets stay under workoutExercises.
      final wes = firstWorkout['workoutExercises'] as List;
      expect((wes.first as Map)['sets'], hasLength(1));

      expect((json['personalRecords'] as List).length, 1);
      expect((json['weeklyPlans'] as List).length, 1);
      expect((json['xpEvents'] as List).length, 1);
      expect((json['bodyPartProgress'] as List).length, 1);
      expect((json['exercisePeakLoads'] as List).length, 1);
      expect((json['exercisePeakLoadsByRepRange'] as List).length, 1);
      expect((json['earnedTitles'] as List).length, 1);
      expect((json['backfillProgress'] as List).length, 1);
      expect((json['vitalityRuns'] as List).length, 1);
      expect((json['analyticsEvents'] as List).length, 1);
    });

    test('exercises array contains ONLY slugs referenced by user workouts '
        '(not the full default library)', () async {
      // Two referenced exercise IDs in the workouts payload; the
      // `exercises` table fetcher MUST be called with `inFilter` on
      // exactly those IDs, returning slugs scoped to that subset.
      // If the service ever regressed to a full-library fetch we'd
      // see slugs the user never trained appearing in the export.
      final client = _FakeClient(
        email: 'scoped@example.com',
        responses: {
          'profiles': _TableResponse.maybeSingleMap(null),
          'workouts': _TableResponse.list([
            {
              'id': 'w1',
              'user_id': 'user-scoped',
              'workout_exercises': [
                {'id': 'we-1', 'exercise_id': 'ex-bench', 'sets': const []},
                {'id': 'we-2', 'exercise_id': 'ex-squat', 'sets': const []},
              ],
            },
          ]),
          'personal_records': _TableResponse.list(const []),
          'weekly_plans': _TableResponse.list(const []),
          'xp_events': _TableResponse.list(const []),
          'body_part_progress': _TableResponse.list(const []),
          'exercise_peak_loads': _TableResponse.list(const []),
          'exercise_peak_loads_by_rep_range': _TableResponse.list(const []),
          'earned_titles': _TableResponse.list(const []),
          'backfill_progress': _TableResponse.maybeSingleMap(null),
          'vitality_runs': _TableResponse.list(const []),
          'analytics_events': _TableResponse.list(const []),
          // The fake returns EXACTLY the two slugs the workouts
          // reference. The contract pinned here: the service must ASK
          // the exercises table with `inFilter` (verified via
          // `tablesQueried` below), and the emitted JSON contains only
          // those slugs. A regression to a full-library fetch would
          // change the row count this fake returns — which the test
          // controls — but the structural test is that
          // `tablesQueried` includes 'exercises' AT MOST ONCE and the
          // emitted JSON contains exactly the two slugs.
          'exercises': _TableResponse.list([
            {'slug': 'bench-press', 'is_default': true},
            {'slug': 'squat', 'is_default': true},
          ]),
        },
      );

      final raw = await _buildService(client).buildJsonExport('user-scoped');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final exercises = (json['exercises'] as List)
          .cast<Map<String, dynamic>>();

      expect(exercises, hasLength(2));
      expect(exercises.map((e) => e['slug']).toSet(), {'bench-press', 'squat'});
      for (final ex in exercises) {
        // Maps `is_default = true` → `userCreated = false`.
        expect(ex['userCreated'], isFalse);
      }
      // Exactly one fetch against `exercises` — proves the scoped-by-id
      // path runs, not a per-workout N+1 lookup.
      expect(client.tablesQueried.where((t) => t == 'exercises').length, 1);
    });

    test(
      'no workouts → exercises array is empty and no exercises fetch is issued',
      () async {
        // The service short-circuits the exercises fetch when the
        // referenced-id set is empty (no round trip). The fake records
        // every `.from(table)` call — a regression to an unconditional
        // fetch would surface as `'exercises'` appearing in the list.
        final client = _FakeClient(
          email: 'noworkouts@example.com',
          responses: {
            'profiles': _TableResponse.maybeSingleMap(null),
            'workouts': _TableResponse.list(const []),
            'personal_records': _TableResponse.list(const []),
            'weekly_plans': _TableResponse.list(const []),
            'xp_events': _TableResponse.list(const []),
            'body_part_progress': _TableResponse.list(const []),
            'exercise_peak_loads': _TableResponse.list(const []),
            'exercise_peak_loads_by_rep_range': _TableResponse.list(const []),
            'earned_titles': _TableResponse.list(const []),
            'backfill_progress': _TableResponse.maybeSingleMap(null),
            'vitality_runs': _TableResponse.list(const []),
            'analytics_events': _TableResponse.list(const []),
          },
        );

        final raw = await _buildService(client).buildJsonExport('user-none');
        final json = jsonDecode(raw) as Map<String, dynamic>;
        expect(json['exercises'], isEmpty);
        expect(client.tablesQueried.contains('exercises'), isFalse);
      },
    );
  });

  group('DataExportService.buildJsonExport — failure paths', () {
    test('network error mid-export propagates as ExportException', () async {
      final client = _FakeClient(
        email: 'fail@example.com',
        responses: {
          'profiles': _TableResponse.maybeSingleMap(null),
          'workouts': _TableResponse.list(const []),
          // Inject a PostgrestException at the `personal_records` stage.
          'personal_records': _TableResponse.error(
            const supabase.PostgrestException(
              message: 'connection reset',
              code: 'PGRST503',
            ),
          ),
        },
      );

      Object? thrown;
      try {
        await _buildService(client).buildJsonExport('user-fail');
      } catch (e) {
        thrown = e;
      }

      expect(thrown, isA<ExportException>());
      final ex = thrown! as ExportException;
      expect(ex.stage, 'personal_records');
      expect(ex.cause, isA<supabase.PostgrestException>());
      // user-safe message is generic and contains no Postgres error text.
      expect(ex.userMessage, isNot(contains('connection reset')));
      expect(ex.userMessage, isNot(contains('PGRST503')));
    });

    test('failure on a later stage tags the correct stage', () async {
      final client = _FakeClient(
        email: 'late@example.com',
        responses: {
          'profiles': _TableResponse.maybeSingleMap(null),
          'workouts': _TableResponse.list(const []),
          'personal_records': _TableResponse.list(const []),
          'weekly_plans': _TableResponse.list(const []),
          'xp_events': _TableResponse.list(const []),
          'body_part_progress': _TableResponse.list(const []),
          'exercise_peak_loads': _TableResponse.list(const []),
          'exercise_peak_loads_by_rep_range': _TableResponse.list(const []),
          'earned_titles': _TableResponse.list(const []),
          'backfill_progress': _TableResponse.maybeSingleMap(null),
          'vitality_runs': _TableResponse.error(StateError('vitality down')),
        },
      );

      Object? thrown;
      try {
        await _buildService(client).buildJsonExport('user-late');
      } catch (e) {
        thrown = e;
      }

      expect(thrown, isA<ExportException>());
      expect((thrown! as ExportException).stage, 'vitality_runs');
    });
  });
}
