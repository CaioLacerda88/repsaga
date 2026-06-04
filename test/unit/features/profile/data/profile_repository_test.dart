import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/exceptions/app_exception.dart' as app;
import 'package:repsaga/core/observability/sentry_report.dart';
import 'package:repsaga/features/profile/data/profile_repository.dart';
import 'package:repsaga/features/profile/models/profile.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show Breadcrumb;
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
  _FakeSupabaseClient(this._builder, {_FakeGoTrueClient? auth})
    : _auth = auth ?? _FakeGoTrueClient();
  final _FakeQueryBuilder _builder;
  final _FakeGoTrueClient _auth;

  @override
  supabase.SupabaseQueryBuilder from(String table) => _builder;

  @override
  supabase.GoTrueClient get auth => _auth;
}

/// Minimal [supabase.GoTrueClient] stand-in. Tracks `refreshSession` calls
/// and lets the test decide whether the next refresh succeeds or throws.
/// The refresh-retry helper does not read the returned [supabase.AuthResponse]
/// payload, so we can return an empty `AuthResponse` on success (the helper
/// only awaits it for ordering).
class _FakeGoTrueClient extends Fake implements supabase.GoTrueClient {
  _FakeGoTrueClient({this.refreshError});

  /// When non-null, [refreshSession] completes with this error. When null,
  /// it resolves with a no-op `AuthResponse` (the production helper does
  /// not consume the response).
  Exception? refreshError;

  int refreshSessionCallCount = 0;

  @override
  Future<supabase.AuthResponse> refreshSession([String? refreshToken]) async {
    refreshSessionCallCount++;
    if (refreshError != null) throw refreshError!;
    return supabase.AuthResponse(session: null, user: null);
  }
}

// ignore: must_be_immutable
class _FakeQueryBuilder extends Fake implements supabase.SupabaseQueryBuilder {
  _FakeQueryBuilder({
    required this.singleResult,
    this.error,
    List<Exception?>? terminalErrorSequence,
    Map<String, dynamic>? secondSingleResult,
  }) : _terminalErrorSequence = List<Exception?>.of(
         terminalErrorSequence ?? const <Exception?>[],
       ),
       _secondSingleResult = secondSingleResult;

  /// Returned by `.maybeSingle()` and `.single()`.
  final Map<String, dynamic>? singleResult;

  /// Static error applied to every terminal call (legacy path used by the
  /// pre-existing tests). When set, [_terminalErrorSequence] is ignored.
  final Exception? error;

  /// Per-terminal-call error sequence. Used by the refresh-retry tests so
  /// the first terminal call can throw while the second succeeds. Pop one
  /// per `then` invocation on the terminal builder.
  final List<Exception?> _terminalErrorSequence;

  /// Row returned by the second terminal call when the first one throws via
  /// [_terminalErrorSequence]. Defaults to [singleResult] when not set.
  final Map<String, dynamic>? _secondSingleResult;

  /// Counter of how many terminal calls have resolved. Used to pick which
  /// element of [_terminalErrorSequence] applies and to swap in
  /// [_secondSingleResult] for the post-retry call.
  int _terminalCallIndex = 0;

  /// Returns the (error, row) pair that the next terminal call must
  /// resolve with. Drains one slot of [_terminalErrorSequence]; once
  /// drained, falls back to [error] (the legacy single-error mode) and
  /// [singleResult].
  ({Exception? err, Map<String, dynamic>? row}) _nextTerminal() {
    final index = _terminalCallIndex++;
    Exception? err;
    if (index < _terminalErrorSequence.length) {
      err = _terminalErrorSequence[index];
    } else {
      err = error;
    }
    final row = index == 0
        ? singleResult
        : (_secondSingleResult ?? singleResult);
    return (err: err, row: row);
  }

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
    // `update().eq(...)` awaits the filter builder directly with no
    // terminal `.single()` / `.maybeSingle()`. Treat that await as a
    // terminal call so the per-call error sequence applies symmetrically
    // to update-style mutations (used by the 42501 retry tests below).
    final next = _parent._nextTerminal();
    if (next.err != null) {
      return Future<T>.error(next.err!).then<S>(onValue, onError: onError);
    }
    // void coercion: the production `update().eq(...)` chain returns
    // PostgrestFilterBuilder<void>, so `T == void` for every update-style
    // call site in ProfileRepository. Dart's runtime treats `void` as
    // accept-any-value (any expression is assignable to `void`), so the
    // `List<Map<...>> as void` cast succeeds — `onValue` receives the
    // empty list, ignores it (its body is `Future<void>`), and the
    // outer await resolves cleanly. This intentionally only works for
    // the `T = void` (update) and `T = List<Map<...>>` shapes the tests
    // actually exercise; a future caller awaiting a typed scalar
    // directly off the filter builder would surface as `_CastError`
    // and need a richer `_nextTerminal` payload.
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
    final next = _parent._nextTerminal();
    if (next.err != null) {
      return Future<T>.error(next.err!).then<S>(onValue, onError: onError);
    }
    final result = next.row as T;
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

    // -------------------------------------------------------------------
    // refresh-and-retry on stale token (PR 2 — fix(auth): refresh session
    // before authenticated mutations on stale token)
    //
    // Spec: BaseRepository.refreshAndRetry intercepts a PostgrestException
    // with code '42501' (RLS rejected anon JWT) or an AuthException with
    // code '401' on a mutation, calls GoTrueClient.refreshSession() once,
    // and retries the action once. Second failure rethrows the ORIGINAL
    // error (no double-wrap). Non-42501 / non-401 errors do NOT retry.
    // Successful retry emits an `auth.session_refreshed_inline` Sentry
    // breadcrumb so the trail tells us "this user dodged a 42501".
    //
    // These tests use the `_FakeQueryBuilder.terminalErrorSequence` channel
    // to control per-call failure shape, and a `_FakeGoTrueClient` to
    // observe the refresh call. Test seam `SentryReport.debugSetBreadcrumbFn`
    // intercepts the breadcrumb path (mirrors the existing
    // `debugSetCaptureFn` seam — added in this PR alongside the helper).
    // -------------------------------------------------------------------
    group('refresh-and-retry on stale token', () {
      late List<Breadcrumb> breadcrumbs;

      setUp(() {
        breadcrumbs = <Breadcrumb>[];
        SentryReport.setEnabled(true);
        SentryReport.debugSetBreadcrumbFn(breadcrumbs.add);
      });

      tearDown(() {
        SentryReport.debugSetBreadcrumbFn(null);
      });

      test('upsertProfile retries once on 42501 and returns the row from the '
          'second attempt; refreshSession called exactly once; '
          '`auth.session_refreshed_inline` breadcrumb fires', () async {
        final auth = _FakeGoTrueClient();
        final secondRow = _profileRow(id: 'user-1', displayName: 'Alice');
        final builder = _FakeQueryBuilder(
          singleResult: null,
          terminalErrorSequence: const [
            supabase.PostgrestException(message: 'rls', code: '42501'),
            null,
          ],
          secondSingleResult: secondRow,
        );
        final repo = ProfileRepository(
          _FakeSupabaseClient(builder, auth: auth),
        );

        final result = await repo.upsertProfile(
          userId: 'user-1',
          displayName: 'Alice',
        );

        expect(result.id, 'user-1');
        expect(result.displayName, 'Alice');
        // EXACT counts — first throws 42501, refresh fires once, second
        // call returns the row. No third attempt.
        expect(auth.refreshSessionCallCount, 1);
        expect(builder._terminalCallIndex, 2);
        // Breadcrumb fired exactly once on the successful retry, with
        // the contract-pinned category + message.
        expect(breadcrumbs, hasLength(1));
        expect(breadcrumbs.single.category, 'auth');
        expect(breadcrumbs.single.message, 'session_refreshed_inline');
      });

      test('upsertProfile rethrows ORIGINAL 42501 (no double-wrap) when '
          'refreshSession itself fails', () async {
        final auth = _FakeGoTrueClient(
          refreshError: supabase.AuthApiException(
            'refresh token revoked',
            statusCode: '401',
          ),
        );
        final builder = _FakeQueryBuilder(
          singleResult: null,
          terminalErrorSequence: const [
            supabase.PostgrestException(
              message: 'permission denied for table profiles',
              code: '42501',
            ),
          ],
        );
        final repo = ProfileRepository(
          _FakeSupabaseClient(builder, auth: auth),
        );

        await expectLater(
          () => repo.upsertProfile(userId: 'user-1', displayName: 'Alice'),
          throwsA(
            isA<app.DatabaseException>()
                .having((e) => e.code, 'code', '42501')
                .having(
                  (e) => e.message,
                  'message',
                  'permission denied for table profiles',
                ),
          ),
        );

        expect(auth.refreshSessionCallCount, 1);
        // Original action was NOT retried — only the first attempt fired.
        expect(builder._terminalCallIndex, 1);
        // No success breadcrumb because the retry never completed.
        expect(breadcrumbs, isEmpty);
      });

      test('upsertProfile does NOT retry on a non-42501 PostgrestException '
          '(e.g. 23505 unique violation)', () async {
        final auth = _FakeGoTrueClient();
        final builder = _FakeQueryBuilder(
          singleResult: null,
          terminalErrorSequence: const [
            supabase.PostgrestException(
              message: 'duplicate key',
              code: '23505',
            ),
          ],
        );
        final repo = ProfileRepository(
          _FakeSupabaseClient(builder, auth: auth),
        );

        await expectLater(
          () => repo.upsertProfile(userId: 'user-1', displayName: 'Alice'),
          throwsA(
            isA<app.DatabaseException>().having((e) => e.code, 'code', '23505'),
          ),
        );

        // The non-RLS path must not call refreshSession at all — pinning
        // an EXACT zero count protects the contract against accidental
        // broadening of the retry trigger.
        expect(auth.refreshSessionCallCount, 0);
        expect(builder._terminalCallIndex, 1);
        expect(breadcrumbs, isEmpty);
      });

      test(
        'upsertProfile rethrows ORIGINAL 42501 when the retried call ALSO '
        'fails with 42501 (bounded — exactly one retry, no infinite loop)',
        () async {
          final auth = _FakeGoTrueClient();
          final builder = _FakeQueryBuilder(
            singleResult: null,
            terminalErrorSequence: const [
              supabase.PostgrestException(
                message: 'permission denied (first)',
                code: '42501',
              ),
              supabase.PostgrestException(
                message: 'permission denied (second)',
                code: '42501',
              ),
            ],
          );
          final repo = ProfileRepository(
            _FakeSupabaseClient(builder, auth: auth),
          );

          await expectLater(
            () => repo.upsertProfile(userId: 'user-1', displayName: 'Alice'),
            throwsA(
              isA<app.DatabaseException>()
                  .having((e) => e.code, 'code', '42501')
                  // Original error surfaces — NOT the retry's error.
                  .having(
                    (e) => e.message,
                    'message',
                    'permission denied (first)',
                  ),
            ),
          );

          expect(auth.refreshSessionCallCount, 1);
          // Exactly two terminal calls — no third attempt.
          expect(builder._terminalCallIndex, 2);
          expect(breadcrumbs, isEmpty);
        },
      );

      test('upsertProfile retries once on AuthException 401 (mirrors the 42501 '
          'path — same single-shot refresh + retry contract)', () async {
        final auth = _FakeGoTrueClient();
        final secondRow = _profileRow(id: 'user-1', displayName: 'Alice');
        final builder = _FakeQueryBuilder(
          singleResult: null,
          terminalErrorSequence: [
            supabase.AuthApiException('JWT expired', statusCode: '401'),
            null,
          ],
          secondSingleResult: secondRow,
        );
        final repo = ProfileRepository(
          _FakeSupabaseClient(builder, auth: auth),
        );

        final result = await repo.upsertProfile(
          userId: 'user-1',
          displayName: 'Alice',
        );

        expect(result.id, 'user-1');
        expect(auth.refreshSessionCallCount, 1);
        expect(builder._terminalCallIndex, 2);
        expect(breadcrumbs.single.message, 'session_refreshed_inline');
      });

      test(
        'upsertProfile happy path — no error, no retry, no refresh, no '
        'breadcrumb (refresh path is strictly opt-in on RLS/401 failure)',
        () async {
          final auth = _FakeGoTrueClient();
          final repo = ProfileRepository(
            _FakeSupabaseClient(
              _builderFor(
                row: _profileRow(id: 'user-1', displayName: 'Alice'),
              ),
              auth: auth,
            ),
          );

          final result = await repo.upsertProfile(
            userId: 'user-1',
            displayName: 'Alice',
          );

          expect(result.id, 'user-1');
          expect(auth.refreshSessionCallCount, 0);
          expect(breadcrumbs, isEmpty);
        },
      );

      test('updateTrainingFrequency retries once on 42501 — same contract as '
          'upsertProfile applies to every mutation method', () async {
        final auth = _FakeGoTrueClient();
        final builder = _FakeQueryBuilder(
          singleResult: null,
          terminalErrorSequence: const [
            supabase.PostgrestException(message: 'rls', code: '42501'),
            null,
          ],
        );
        final repo = ProfileRepository(
          _FakeSupabaseClient(builder, auth: auth),
        );

        await repo.updateTrainingFrequency('user-1', 4);

        expect(auth.refreshSessionCallCount, 1);
        expect(builder._terminalCallIndex, 2);
        expect(breadcrumbs.single.message, 'session_refreshed_inline');
      });

      test('updateWeightUnit retries once on 42501 — same contract as '
          'upsertProfile applies to every mutation method', () async {
        final auth = _FakeGoTrueClient();
        final builder = _FakeQueryBuilder(
          singleResult: null,
          terminalErrorSequence: const [
            supabase.PostgrestException(message: 'rls', code: '42501'),
            null,
          ],
        );
        final repo = ProfileRepository(
          _FakeSupabaseClient(builder, auth: auth),
        );

        await repo.updateWeightUnit('user-1', 'lbs');

        expect(auth.refreshSessionCallCount, 1);
        expect(builder._terminalCallIndex, 2);
        expect(breadcrumbs.single.message, 'session_refreshed_inline');
      });

      test(
        'updateLocale retries once on 42501 — same contract as upsertProfile '
        'applies to every mutation method',
        () async {
          final auth = _FakeGoTrueClient();
          final builder = _FakeQueryBuilder(
            singleResult: null,
            terminalErrorSequence: const [
              supabase.PostgrestException(message: 'rls', code: '42501'),
              null,
            ],
          );
          final repo = ProfileRepository(
            _FakeSupabaseClient(builder, auth: auth),
          );

          await repo.updateLocale('user-1', 'pt');

          expect(auth.refreshSessionCallCount, 1);
          expect(builder._terminalCallIndex, 2);
          expect(breadcrumbs.single.message, 'session_refreshed_inline');
        },
      );

      test('upsertProfile does NOT retry on a non-401 AuthException '
          '(e.g. AuthSessionMissingException with statusCode 400) — '
          'only statusCode=="401" triggers the refresh path', () async {
        final auth = _FakeGoTrueClient();
        final builder = _FakeQueryBuilder(
          singleResult: null,
          terminalErrorSequence: const [
            // AuthSessionMissingException has statusCode '400'. This must
            // NOT trigger the refresh path — the gate is strictly '401'.
            supabase.AuthException('Auth session missing!', statusCode: '400'),
          ],
        );
        final repo = ProfileRepository(
          _FakeSupabaseClient(builder, auth: auth),
        );

        await expectLater(
          () => repo.upsertProfile(userId: 'user-1', displayName: 'Alice'),
          throwsA(isA<app.AppException>()),
        );

        // Non-401 AuthException must NOT call refreshSession at all — pinning
        // an EXACT zero count guards the boundary value adjacent to '401'.
        expect(auth.refreshSessionCallCount, 0);
        // Exactly one terminal call — no retry attempted.
        expect(builder._terminalCallIndex, 1);
        expect(breadcrumbs, isEmpty);
      });

      test('getProfile (read) is NOT wrapped — a 42501 surfaces immediately '
          'with no refresh attempt (RLS on SELECT just returns no rows in '
          'practice; refresh-retry only applies to mutations)', () async {
        final auth = _FakeGoTrueClient();
        final builder = _FakeQueryBuilder(
          singleResult: null,
          terminalErrorSequence: const [
            supabase.PostgrestException(message: 'rls', code: '42501'),
          ],
        );
        final repo = ProfileRepository(
          _FakeSupabaseClient(builder, auth: auth),
        );

        await expectLater(
          () => repo.getProfile('user-1'),
          throwsA(isA<app.DatabaseException>()),
        );

        expect(auth.refreshSessionCallCount, 0);
        expect(builder._terminalCallIndex, 1);
        expect(breadcrumbs, isEmpty);
      });
    });
  });
}
