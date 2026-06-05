import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/analytics/data/analytics_repository.dart';
import 'package:repsaga/features/analytics/data/models/analytics_event.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

// ---------------------------------------------------------------------------
// Fake Supabase infrastructure — records insert payloads
// ---------------------------------------------------------------------------

class _FakeClient extends Fake implements supabase.SupabaseClient {
  _FakeClient(this.builder);
  final _FakeInsertBuilder builder;

  @override
  supabase.SupabaseQueryBuilder from(String table) {
    builder.lastTable = table;
    return builder;
  }
}

// ignore: must_be_immutable
class _FakeInsertBuilder extends Fake implements supabase.SupabaseQueryBuilder {
  _FakeInsertBuilder({this.error});

  String? lastTable;
  final List<Map<String, dynamic>> insertedRows = [];
  Object? error;

  @override
  supabase.PostgrestFilterBuilder<dynamic> insert(
    Object values, {
    bool defaultToNull = true,
  }) {
    if (error != null) {
      return _FakeErrorFilterBuilder(error!);
    }
    if (values is Map<String, dynamic>) {
      insertedRows.add(values);
    } else if (values is List) {
      for (final v in values) {
        insertedRows.add(Map<String, dynamic>.from(v as Map));
      }
    }
    return _FakeOkFilterBuilder();
  }
}

class _FakeOkFilterBuilder extends Fake
    implements supabase.PostgrestFilterBuilder<dynamic> {
  @override
  Future<S> then<S>(
    FutureOr<S> Function(dynamic) onValue, {
    Function? onError,
  }) {
    return Future.value(onValue(null));
  }
}

class _FakeErrorFilterBuilder extends Fake
    implements supabase.PostgrestFilterBuilder<dynamic> {
  _FakeErrorFilterBuilder(this._error);
  final Object _error;

  @override
  Future<S> then<S>(
    FutureOr<S> Function(dynamic) onValue, {
    Function? onError,
  }) {
    // Simulate an errored future. We call onError if provided (as `await`
    // does internally) so the error propagates through the caller's
    // try/catch correctly.
    if (onError != null) {
      if (onError is Function(Object, StackTrace)) {
        return Future.sync(() => onError(_error, StackTrace.current) as S);
      }
      if (onError is Function(Object)) {
        return Future.sync(() => onError(_error) as S);
      }
    }
    return Future<S>.error(_error);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('AnalyticsRepository.insertEvent', () {
    test('writes to analytics_events table with correct payload', () async {
      final builder = _FakeInsertBuilder();
      final repo = AnalyticsRepository(_FakeClient(builder));

      await repo.insertEvent(
        userId: 'user-abc',
        event: const AnalyticsEvent.workoutFinished(
          durationSeconds: 3420,
          exerciseCount: 6,
          totalSets: 24,
          completedSets: 22,
          incompleteSetsSkipped: 2,
          hadPr: true,
          source: 'planned_bucket',
          workoutNumber: 5,
        ),
        platform: 'android',
        appVersion: '1.2.3+45',
      );

      expect(builder.lastTable, 'analytics_events');
      expect(builder.insertedRows, hasLength(1));
      final row = builder.insertedRows.first;
      expect(row['user_id'], 'user-abc');
      expect(row['name'], 'workout_finished');
      expect(row['platform'], 'android');
      expect(row['app_version'], '1.2.3+45');
      expect(row['props'], isA<Map>());
      expect((row['props'] as Map)['workout_number'], 5);
      expect((row['props'] as Map)['had_pr'], true);
    });

    test('accepts null platform and app_version', () async {
      final builder = _FakeInsertBuilder();
      final repo = AnalyticsRepository(_FakeClient(builder));

      await repo.insertEvent(
        userId: 'user-abc',
        event: const AnalyticsEvent.onboardingCompleted(
          fitnessLevel: 'beginner',
          trainingFrequency: 3,
        ),
        platform: null,
        appVersion: null,
      );

      final row = builder.insertedRows.first;
      expect(row['platform'], null);
      expect(row['app_version'], null);
    });

    test('swallows insert errors without throwing (fire-and-forget)', () async {
      final builder = _FakeInsertBuilder(error: Exception('network down'));
      final repo = AnalyticsRepository(_FakeClient(builder));

      // Should NOT throw — analytics is best-effort.
      await expectLater(
        repo.insertEvent(
          userId: 'user-abc',
          event: const AnalyticsEvent.onboardingCompleted(
            fitnessLevel: 'beginner',
            trainingFrequency: 3,
          ),
          platform: 'android',
          appVersion: '1.0.0',
        ),
        completes,
      );
    });

    // Legal PR 2 — opt-out gate at the insert level.
    // Cluster: `data-protection-compliance`. The `_enabled` flag is the
    // gate that prevents any Supabase write when the user has opted out.
    // This test pins that the gate-at-insert behavior is correct,
    // complementing the provider-level tests in analytics_enabled_provider_test
    // which assert the static flag's Hive sync.
    test(
      'skips Supabase write when _enabled is false (analytics opt-out)',
      () async {
        final builder = _FakeInsertBuilder();
        final repo = AnalyticsRepository(_FakeClient(builder));

        // Set the static gate to disabled (simulates user opt-out).
        AnalyticsRepository.setEnabled(false);
        addTearDown(() => AnalyticsRepository.debugResetEnabled());

        await repo.insertEvent(
          userId: 'user-abc',
          event: const AnalyticsEvent.onboardingCompleted(
            fitnessLevel: 'beginner',
            trainingFrequency: 3,
          ),
          platform: 'android',
          appVersion: '1.0.0',
        );

        // No rows must reach the fake client — the `if (!_enabled) return;`
        // short-circuit at line 68 of analytics_repository.dart must fire
        // before any `_client.from(...)` call.
        expect(
          builder.insertedRows,
          isEmpty,
          reason: 'insertEvent must not write when analytics opt-out is active',
        );
      },
    );

    test('resumes Supabase write after re-enabling', () async {
      final builder = _FakeInsertBuilder();
      final repo = AnalyticsRepository(_FakeClient(builder));

      // Opt out then opt back in.
      AnalyticsRepository.setEnabled(false);
      AnalyticsRepository.setEnabled(true);
      addTearDown(() => AnalyticsRepository.debugResetEnabled());

      await repo.insertEvent(
        userId: 'user-abc',
        event: const AnalyticsEvent.onboardingCompleted(
          fitnessLevel: 'beginner',
          trainingFrequency: 3,
        ),
        platform: 'android',
        appVersion: '1.0.0',
      );

      expect(
        builder.insertedRows,
        hasLength(1),
        reason: 're-enabling analytics must restore insert behaviour',
      );
    });
  });
}
