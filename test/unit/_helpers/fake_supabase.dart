/// Shared fake Supabase infrastructure for unit tests.
///
/// Provides lightweight fakes that record method calls and return preset data,
/// matching the pattern used across all repository tests in this project.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// A fake SupabaseClient that routes `from(table)` to a single builder.
///
/// **`rpc(...)` support (Phase 32 PR 32f):** an optional [rpcResponses] map
/// keyed by function name lets callers seed RPC results without touching
/// `from(...)`. When [fakeBuilder] carries an `error`, [rpc] propagates that
/// error too — same offline-simulation pattern used by `.from().select()`
/// callers — so cache fallback paths in `WorkoutRepository.getWorkoutHistory`
/// (which calls `_client.rpc(...)` post-Phase-32) still exercise the
/// existing offline-throw branch. Unseeded RPC names fall back to
/// [fakeBuilder]'s `.data` list — keeping existing single-source tests
/// working without per-test rewiring.
class FakeSupabaseClient extends Fake implements supabase.SupabaseClient {
  FakeSupabaseClient(this.fakeBuilder, {Map<String, Object?>? rpcResponses})
    : rpcResponses = rpcResponses ?? const {};

  final FakeQueryBuilder fakeBuilder;
  final Map<String, Object?> rpcResponses;

  @override
  supabase.SupabaseQueryBuilder from(String table) => fakeBuilder;

  @override
  supabase.PostgrestFilterBuilder<T> rpc<T>(
    String fn, {
    Map<String, dynamic>? params,
    dynamic get,
  }) {
    return _FakeRpcResultBuilder<T>(() async {
          if (fakeBuilder.error != null) {
            throw fakeBuilder.error!;
          }
          if (rpcResponses.containsKey(fn)) {
            return rpcResponses[fn];
          }
          // Fallback: surface the FakeQueryBuilder's `data` list so legacy tests
          // that don't seed `rpcResponses` keep returning the same workout
          // payload they were seeded with.
          return fakeBuilder.data;
        })
        as supabase.PostgrestFilterBuilder<T>;
  }
}

/// Terminal future for rpc() chains used by [FakeSupabaseClient]. Mirrors
/// the simpler shape used by `test/fixtures/rpc_fakes.dart` but accepts
/// `Object?` so callers can return either a list or a single map (e.g.
/// `get_workout_xp` returns a single row).
class _FakeRpcResultBuilder<T> extends Fake
    implements supabase.PostgrestFilterBuilder<T> {
  _FakeRpcResultBuilder(this._produce);

  final FutureOr<Object?> Function() _produce;

  Future<T> _resolve() async {
    final result = await _produce();
    return result as T;
  }

  @override
  Future<S> then<S>(FutureOr<S> Function(T) onValue, {Function? onError}) {
    return _resolve().then<S>(onValue, onError: onError);
  }
}

/// A fake client that routes `from(table)` to different builders per table.
///
/// **`rpc(...)` support (PR #285 Blocker 3):** mirrors the same shim added to
/// [FakeSupabaseClient]. An optional [rpcResponses] map seeds RPC results by
/// function name; unseeded names fall back to [routedBuilder]'s `data`, with
/// a `routedBuilder.error` short-circuiting both paths so cache-fallback
/// tests behave the same way they do for the single-builder fake. Without
/// this shim, any repository test that wires a `FakeRoutingSupabaseClient`
/// + a code path that now calls `_client.rpc(...)` (Phase 32 PR 32f
/// `getWorkoutHistory`, future RPC migrations) crashes with
/// `UnimplementedError` from `Fake`.
class FakeRoutingSupabaseClient extends Fake
    implements supabase.SupabaseClient {
  FakeRoutingSupabaseClient(
    this.builders, {
    this.routedBuilder,
    Map<String, Object?>? rpcResponses,
  }) : rpcResponses = rpcResponses ?? const {};

  final Map<String, FakeQueryBuilder> builders;

  /// Optional fallback builder consulted by [rpc] when an unseeded function
  /// name is requested. Defaults to the first entry in [builders] if
  /// callers don't pass one explicitly. Same convenience the single-builder
  /// fake offers — keeps existing tests that already exercise `from(...)`
  /// working without a per-test rewire.
  final FakeQueryBuilder? routedBuilder;
  final Map<String, Object?> rpcResponses;

  @override
  supabase.SupabaseQueryBuilder from(String table) =>
      builders[table] ?? (throw StateError('Unexpected table: $table'));

  @override
  supabase.PostgrestFilterBuilder<T> rpc<T>(
    String fn, {
    Map<String, dynamic>? params,
    dynamic get,
  }) {
    final fallback =
        routedBuilder ?? (builders.isNotEmpty ? builders.values.first : null);
    return _FakeRpcResultBuilder<T>(() async {
          if (fallback?.error != null) {
            throw fallback!.error!;
          }
          if (rpcResponses.containsKey(fn)) {
            return rpcResponses[fn];
          }
          return fallback?.data;
        })
        as supabase.PostgrestFilterBuilder<T>;
  }
}

/// Records chained query calls and returns preset data or error.
// ignore: must_be_immutable
class FakeQueryBuilder extends Fake implements supabase.SupabaseQueryBuilder {
  FakeQueryBuilder({this.data = const [], this.error});

  final List<Map<String, dynamic>> data;
  final Exception? error;
  final List<String> calledMethods = [];

  /// Captures the payload passed to the most recent `update(...)` call so
  /// tests can assert the persisted values (behavior, not just "update was
  /// called"). Null until `update` runs.
  Map<dynamic, dynamic>? lastUpdateValues;

  @override
  FakeFilterBuilder select([String columns = '*']) {
    calledMethods.add('select');
    return FakeFilterBuilder(this);
  }

  @override
  FakeFilterBuilder insert(dynamic values, {bool defaultToNull = true}) {
    calledMethods.add('insert');
    return FakeFilterBuilder(this);
  }

  @override
  FakeFilterBuilder update(Map values) {
    calledMethods.add('update');
    lastUpdateValues = values;
    return FakeFilterBuilder(this);
  }

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
  FakeFilterBuilder isFilter(String column, Object? value) {
    _parent.calledMethods.add('isFilter:$column');
    return this;
  }

  @override
  FakeFilterBuilder eq(String column, Object value) {
    _parent.calledMethods.add('eq:$column=$value');
    return this;
  }

  @override
  FakeFilterBuilder ilike(String column, Object value) {
    _parent.calledMethods.add('ilike:$column=$value');
    return this;
  }

  @override
  FakeFilterBuilder or(String filter, {String? referencedTable}) {
    _parent.calledMethods.add('or:$filter');
    return this;
  }

  @override
  FakeFilterBuilder inFilter(String column, List values) {
    _parent.calledMethods.add('inFilter:$column');
    return this;
  }

  @override
  FakeFilterBuilder not(String column, String operator, Object? value) {
    _parent.calledMethods.add('not:$column.$operator=$value');
    return this;
  }

  @override
  FakeFilterBuilder select([String columns = '*']) {
    _parent.calledMethods.add('chainSelect');
    return this;
  }

  @override
  FakeTransformBuilder<Map<String, dynamic>> single() {
    _parent.calledMethods.add('single');
    return FakeTransformBuilder<Map<String, dynamic>>(
      _parent,
      _parent.data.isEmpty ? <String, dynamic>{} : _parent.data.first,
    );
  }

  @override
  FakeTransformBuilder<List<Map<String, dynamic>>> order(
    String column, {
    bool ascending = false,
    bool nullsFirst = false,
    String? referencedTable,
  }) {
    _parent.calledMethods.add('order:$column');
    return FakeTransformBuilder<List<Map<String, dynamic>>>(
      _parent,
      _parent.data,
    );
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
    return Future.value(onValue(_parent.data));
  }
}

class FakeTransformBuilder<T> extends Fake
    implements supabase.PostgrestTransformBuilder<T> {
  FakeTransformBuilder(this._parent, this._result);

  final FakeQueryBuilder _parent;
  final T _result;

  @override
  FakeFilterBuilder select([String columns = '*']) =>
      FakeFilterBuilder(_parent);

  @override
  FakeTransformBuilder<T> limit(int count, {String? referencedTable}) {
    _parent.calledMethods.add('limit:$count');
    return this;
  }

  @override
  FakeTransformBuilder<T> range(int from, int to, {String? referencedTable}) {
    _parent.calledMethods.add('range:$from-$to');
    return this;
  }

  @override
  Future<S> then<S>(FutureOr<S> Function(T) onValue, {Function? onError}) {
    if (_parent.error != null) {
      return Future<T>.error(_parent.error!).then<S>(onValue, onError: onError);
    }
    return Future.value(onValue(_result));
  }
}
