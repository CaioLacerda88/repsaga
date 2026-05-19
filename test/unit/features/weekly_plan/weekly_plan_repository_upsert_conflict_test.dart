/// Regression test for the weekly_plans upsert conflict target.
///
/// `weekly_plans` carries `UNIQUE (user_id, week_start)` (migration 00011)
/// but the table's primary key is the surrogate `id`. PostgREST's default
/// conflict target is the primary key, so the upsert payload — which does
/// not include `id` — silently behaves as a plain INSERT and violates the
/// unique constraint on every save after the first one of the week. The
/// repo MUST pass `onConflict: 'user_id,week_start'` so PostgREST emits
/// `ON CONFLICT (user_id, week_start) DO UPDATE`.
///
/// This test pins the call-site contract at the SDK boundary. The
/// behavioral consequence (the editor's "saved" toast lying and edits
/// silently reverting on re-mount) is unreachable from a unit test because
/// it lives in the Postgres ↔ Dart roundtrip; the closest surface we can
/// pin is "did the repo pass the right `onConflict` argument."
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/weekly_plan/data/models/weekly_plan.dart';
import 'package:repsaga/features/weekly_plan/data/weekly_plan_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class _ProbeException implements Exception {
  const _ProbeException();
}

class _FakeSupabaseClient extends Fake implements supabase.SupabaseClient {
  _FakeSupabaseClient(this._builder);
  final _FakeQueryBuilder _builder;

  @override
  supabase.SupabaseQueryBuilder from(String table) => _builder;
}

// ignore: must_be_immutable
class _FakeQueryBuilder extends Fake implements supabase.SupabaseQueryBuilder {
  String? capturedOnConflict;

  @override
  Never upsert(
    Object values, {
    String? onConflict,
    bool ignoreDuplicates = false,
    bool defaultToNull = true,
  }) {
    capturedOnConflict = onConflict;
    // Short-circuit the chain — we only need the args, not the roundtrip.
    // The thrown exception is caught by [WeeklyPlanRepository.mapException]
    // and rethrown as an AppException, which the test catches and ignores.
    throw const _ProbeException();
  }
}

void main() {
  test('upsertPlan passes onConflict: user_id,week_start so PostgREST uses '
      'the UNIQUE constraint instead of the primary key', () async {
    final builder = _FakeQueryBuilder();
    final client = _FakeSupabaseClient(builder);
    final repo = WeeklyPlanRepository(client);

    try {
      await repo.upsertPlan(
        userId: 'user-001',
        weekStart: DateTime(2026, 5, 18),
        routines: [const BucketRoutine(routineId: 'r1', order: 1)],
      );
    } on Object {
      // mapException rewraps the probe throw; we don't care about the
      // shape since we only need to verify the args captured before it.
    }

    // The user-visible bug: without onConflict, PostgREST resolves the
    // upsert against the primary key (`id`), which is auto-generated and
    // never present in the payload — so every save after the first
    // INSERTs and fails on UNIQUE (user_id, week_start). Pinning the
    // exact conflict target catches a regression where a maintainer
    // refactors the call and drops the argument.
    expect(builder.capturedOnConflict, 'user_id,week_start');
  });
}
