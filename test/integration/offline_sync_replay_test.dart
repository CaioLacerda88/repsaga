/// Integration test for the offline-sync REPLAY path (Phase 38.9 T1.4).
///
/// Audit gap #2: the 4,347-LOC offline-sync stack (`lib/core/offline/`) was
/// exercised only by mock-backed unit tests. No test drove the REAL
/// local-store (Hive) → real `SyncService` drain → real Supabase replay. This
/// test closes that gap with the canonical hard case: replay-under-partial-
/// failure (one structurally-invalid action mid-batch).
///
/// What it pins (behavior, not wiring — every assertion is a persisted /
/// queue-observable outcome against REAL Supabase + a REAL Hive box):
///   (a) the VALID queued workouts are persisted server-side (queried back
///       via the service-role client),
///   (b) the structurally-broken action is FLAGGED (errorCategory.structural)
///       and classified TERMINAL on the first attempt (SQLSTATE 22P02 → pinned
///       to the retry-count ceiling, never re-drained) — NOT silently dropped,
///       and NOT wastefully retried kMaxSyncRetries times,
///   (c) the queue ends in the expected state (valid ones removed, broken one
///       retained for the user's dismiss/retry CTA),
///   (d) NO valid action is lost behind the failing one (partial-failure
///       isolation — the FIFO drain continues past the failure).
///
/// Requires local Supabase running: `npx supabase start`.
///
/// Run:
///   export PATH="/c/flutter/bin:$PATH"
///   flutter test --tags integration test/integration/offline_sync_replay_test.dart
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:repsaga/core/connectivity/connectivity_provider.dart';
import 'package:repsaga/core/local_storage/cache_service.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:repsaga/core/offline/offline_queue_service.dart';
import 'package:repsaga/core/offline/pending_action.dart';
import 'package:repsaga/core/offline/sync_service.dart';
import 'package:repsaga/features/exercises/data/exercise_repository.dart';
import 'package:repsaga/features/exercises/providers/exercise_providers.dart';
import 'package:repsaga/features/personal_records/data/pr_repository.dart';
import 'package:repsaga/features/personal_records/providers/pr_providers.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';

import 'rpg_integration_setup.dart';

void main() {
  final runId = DateTime.now().millisecondsSinceEpoch;
  var testIdx = 0;

  TestUser? currentUser;
  Directory? tempDir;
  StreamController<bool>? connectivityController;

  /// Builds a [PendingSaveWorkout] whose raw JSON survives the drain's
  /// `Workout.fromJson` / `WorkoutExercise.fromJson` / `ExerciseSet.fromJson`
  /// round-trip and then the real `save_workout` RPC. Mirrors the shapes in
  /// `rpg_integration_setup.saveWorkoutRpc`.
  ///
  /// [seed] MUST come from `seedWorkout` so the workout/exercise/set rows
  /// already exist server-side: `save_workout` is a *finalize* RPC that
  /// raises `P0002` ("Workout not found or does not belong to user") when the
  /// workout id isn't already present for the authenticated user — exactly the
  /// online path (start active workout → save). The pending action carries the
  /// same ids so the drain's replay commits against the seeded rows.
  PendingSaveWorkout buildValidAction({
    required String id,
    required String userId,
    required SeedResult seed,
    required DateTime queuedAt,
    double weightKg = 60.0,
    int reps = 5,
  }) {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    return PendingSaveWorkout(
      id: id,
      userId: userId,
      queuedAt: queuedAt,
      workoutJson: {
        'id': seed.workoutId,
        'user_id': userId,
        'name': 'Replay Integration Workout',
        'started_at': nowIso,
        'finished_at': nowIso,
        'duration_seconds': 3600,
        'is_active': false,
        'notes': null,
        'created_at': nowIso,
        'routine_id': null,
      },
      exercisesJson: [
        {
          'id': seed.workoutExerciseId,
          'workout_id': seed.workoutId,
          'exercise_id': seed.exerciseId,
          'order': 1,
          'rest_seconds': null,
        },
      ],
      setsJson: [
        {
          'id': seed.setIds.first,
          'workout_exercise_id': seed.workoutExerciseId,
          'set_number': 1,
          'reps': reps,
          'weight': weightKg,
          'rpe': null,
          'set_type': 'working',
          'notes': null,
          'is_completed': true,
          'created_at': nowIso,
        },
      ],
    );
  }

  /// Builds an action that fails TERMINALLY/structurally against real
  /// Supabase: a malformed UUID in the workout id yields Postgres
  /// `invalid input syntax for type uuid` (SQLSTATE 22P02). `ErrorMapper`
  /// copies the SQLSTATE onto `app.DatabaseException(code: '22P02')`, which
  /// `SyncErrorMapper` classifies as `SyncErrorCategory.structural` AND
  /// `SyncErrorClassifier.isTerminal` recognises as terminal (the code is the
  /// SQLSTATE, NOT an HTTP int) — a permanent, retry-won't-fix data-shape
  /// error.
  PendingSaveWorkout buildStructurallyBrokenAction({
    required String id,
    required String userId,
    required DateTime queuedAt,
  }) {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    return PendingSaveWorkout(
      id: id,
      userId: userId,
      queuedAt: queuedAt,
      workoutJson: {
        'id': 'NOT-A-VALID-UUID', // → 22P02 invalid_text_representation
        'user_id': userId,
        'name': 'Broken Replay Workout',
        'started_at': nowIso,
        'finished_at': nowIso,
        'duration_seconds': 60,
        'is_active': false,
        'notes': null,
        'created_at': nowIso,
        'routine_id': null,
      },
      exercisesJson: const [],
      setsJson: const [],
    );
  }

  /// Real repository providers wired to an authenticated test client, plus a
  /// controllable connectivity stream. This is the production provider graph
  /// minus the `Supabase.instance` singleton (the three repos read it
  /// directly), so the drain runs the real replay code against real Supabase.
  ProviderContainer buildContainer(TestUser user) {
    final client = authenticatedClient(user);
    const cache = CacheService();
    final exerciseRepo = ExerciseRepository(client, cache);

    final controller = StreamController<bool>.broadcast();
    connectivityController = controller;

    final container = ProviderContainer(
      overrides: [
        // Drive connectivity transitions deterministically — start offline so
        // the build-time `_lastOnline` is false, then push `true` to fire the
        // real `ref.listen(isOnlineProvider)` drain trigger.
        onlineStatusProvider.overrideWith((ref) => controller.stream),
        isOnlineProvider.overrideWith(
          (ref) => ref.watch(onlineStatusProvider).value ?? false,
        ),
        offlineQueueServiceProvider.overrideWithValue(
          const OfflineQueueService(),
        ),
        workoutRepositoryProvider.overrideWithValue(
          WorkoutRepository(client, cache, exerciseRepo),
        ),
        prRepositoryProvider.overrideWithValue(
          PRRepository(client, cache, exerciseRepo),
        ),
        exerciseRepositoryProvider.overrideWithValue(exerciseRepo),
      ],
    );
    addTearDown(container.dispose);

    // Subscribe so SyncService.build() runs and its ref.listen chain is live
    // (in production a widget watching the provider does this).
    container.listen(syncServiceProvider, (_, _) {});
    return container;
  }

  setUp(() async {
    final idx = testIdx++;
    currentUser = await createTestUser('offline-replay-$runId-$idx@test.local');

    // Real Hive box on a temp dir — the offline queue persists to disk and the
    // drain reads it back exactly as on device.
    tempDir = await Directory.systemTemp.createTemp('hive_offline_replay_');
    Hive.init(tempDir!.path);
    await Hive.openBox<dynamic>(HiveService.offlineQueue);
    await Hive.openBox<dynamic>(HiveService.userPrefs);
  });

  tearDown(() async {
    await connectivityController?.close();
    connectivityController = null;
    await Hive.close();
    if (tempDir != null) {
      await tempDir!.delete(recursive: true);
      tempDir = null;
    }
    if (currentUser != null) {
      await deleteTestUser(currentUser!.userId);
      currentUser = null;
    }
  });

  /// Count finished workouts owned by [userId] on the server.
  Future<List<Map<String, dynamic>>> serverWorkouts(String userId) async {
    final admin = serviceRoleClient();
    final rows = await admin
        .from('workouts')
        .select('id, name')
        .eq('user_id', userId);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Poll the real `_drain()` outcome: it's kicked by the connectivity
  /// transition listener (fire-and-forget), so we wait until the queue
  /// stabilises at the expected residual size rather than racing it.
  Future<void> waitForQueueToSettle(
    OfflineQueueService queue, {
    required int expectedRemaining,
  }) async {
    const timeout = Duration(seconds: 30);
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (queue.getAll().length == expectedRemaining) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    fail(
      'Queue did not settle to $expectedRemaining items within '
      '${timeout.inSeconds}s (current: ${queue.getAll().length})',
    );
  }

  group('Offline sync replay', () {
    test('should persist valid workouts and flag the structurally-broken one '
        'without losing any valid action behind the failure', () async {
      final user = currentUser!;
      final admin = serviceRoleClient();
      final container = buildContainer(user);
      final queue = container.read(offlineQueueServiceProvider);

      // Pre-seed the server-side rows for the two valid workouts (the
      // `save_workout` RPC finalizes existing rows — see buildValidAction).
      final seedBefore = await seedWorkout(
        adminClient: admin,
        userId: user.userId,
        exerciseSlug: 'barbell_bench_press',
        weightKg: 60.0,
        reps: 5,
        numSets: 1,
      );
      final seedAfter = await seedWorkout(
        adminClient: admin,
        userId: user.userId,
        exerciseSlug: 'deadlift',
        weightKg: 80.0,
        reps: 5,
        numSets: 1,
      );
      final beforeWorkoutId = seedBefore.workoutId;
      final afterWorkoutId = seedAfter.workoutId;

      // queuedAt drives FIFO order — space them so the broken action sits
      // strictly BETWEEN valid actions, proving isolation in both
      // directions.
      final base = DateTime.now().toUtc();
      final validBefore = buildValidAction(
        id: 'valid-before',
        userId: user.userId,
        seed: seedBefore,
        queuedAt: base,
      );
      final broken = buildStructurallyBrokenAction(
        id: 'broken-middle',
        userId: user.userId,
        queuedAt: base.add(const Duration(seconds: 1)),
      );
      final validAfter = buildValidAction(
        id: 'valid-after',
        userId: user.userId,
        seed: seedAfter,
        weightKg: 80.0,
        queuedAt: base.add(const Duration(seconds: 2)),
      );

      await queue.enqueue(validBefore);
      await queue.enqueue(broken);
      await queue.enqueue(validAfter);
      expect(
        queue.getAll(),
        hasLength(3),
        reason: 'all three actions enqueued to the real Hive box',
      );

      // Trigger the REAL drain via an offline→online transition.
      connectivityController!.add(true);

      // Both valid actions dequeue on success; the broken one is retained
      // (structural, not auto-dropped) → queue settles at 1.
      await waitForQueueToSettle(queue, expectedRemaining: 1);

      // (a) + (d): BOTH valid workouts persisted server-side — the one after
      // the failure is NOT lost behind it.
      final saved = await serverWorkouts(user.userId);
      final savedIds = saved.map((w) => w['id'] as String).toSet();
      expect(
        savedIds,
        containsAll(<String>[beforeWorkoutId, afterWorkoutId]),
        reason:
            'both valid workouts must be persisted; the post-failure one '
            'proves FIFO drain continues past a mid-batch failure',
      );

      // (c): valid actions removed from the queue.
      final remaining = queue.getAll();
      expect(
        remaining.map((a) => a.id),
        isNot(contains('valid-before')),
        reason: 'committed action must be dequeued',
      );
      expect(
        remaining.map((a) => a.id),
        isNot(contains('valid-after')),
        reason: 'committed action must be dequeued',
      );

      // (b): the broken action is retained AND flagged structural — handled
      // per the classifier, not silently dropped, so the pending-sync sheet
      // can offer "Dispensar". Crucially it is classified TERMINAL on the
      // FIRST attempt (malformed UUID → SQLSTATE 22P02, a deterministic
      // data-shape error that an identical replay always reproduces) and
      // pinned to the retry-count ceiling so it is NEVER re-drained — the dead
      // HTTP-code fast-path (cluster: classifier-keyed-on-http-not-sqlstate)
      // would have wastefully retried it kMaxSyncRetries times first.
      expect(remaining, hasLength(1));
      final brokenAfter = remaining.single;
      expect(brokenAfter.id, 'broken-middle');
      expect(
        brokenAfter.retryCount,
        kMaxSyncRetries,
        reason:
            'a deterministic terminal error (22P02) is pinned to the '
            'retry-count ceiling on the FIRST failure — not retried 6×',
      );
      expect(
        brokenAfter.errorCategory,
        SyncErrorCategory.structural,
        reason:
            'malformed-UUID (SQLSTATE 22P02) is a permanent data-shape '
            'error → structural category drives the dismiss CTA',
      );
      expect(
        brokenAfter.lastError,
        isNotNull,
        reason: 'failure detail captured for diagnostics',
      );

      // The post-drain terminal sweep counts the pinned action so the UI's
      // terminal badge / retry-all affordance reflects it.
      expect(
        container.read(syncServiceProvider).terminalFailureCount,
        1,
        reason: 'terminal-on-first-attempt counted in terminalFailureCount',
      );

      // The broken workout id must NOT exist server-side (it never
      // committed) — and crucially the malformed UUID could never be a real
      // row, so the valid set is exactly the two we expect (no partial
      // garbage).
      expect(
        saved,
        hasLength(2),
        reason: 'exactly the two valid workouts committed — no orphans',
      );
    });

    test(
      'should leave a fully-valid batch with an empty queue after replay',
      () async {
        // Control case: with no failure the entire FIFO drains clean. Pins the
        // happy replay path so the partial-failure test above is contrasted
        // against a known-good baseline (guards against a false green where
        // the drain silently no-ops).
        final user = currentUser!;
        final admin = serviceRoleClient();
        final container = buildContainer(user);
        final queue = container.read(offlineQueueServiceProvider);

        final base = DateTime.now().toUtc();
        final ids = <String>[];
        for (var i = 0; i < 3; i++) {
          final seed = await seedWorkout(
            adminClient: admin,
            userId: user.userId,
            exerciseSlug: 'barbell_bench_press',
            weightKg: 60.0,
            reps: 5,
            numSets: 1,
          );
          ids.add(seed.workoutId);
          await queue.enqueue(
            buildValidAction(
              id: 'valid-$i',
              userId: user.userId,
              seed: seed,
              queuedAt: base.add(Duration(seconds: i)),
            ),
          );
        }
        expect(queue.getAll(), hasLength(3));

        connectivityController!.add(true);
        await waitForQueueToSettle(queue, expectedRemaining: 0);

        final saved = await serverWorkouts(user.userId);
        expect(
          saved.map((w) => w['id'] as String).toSet(),
          containsAll(ids),
          reason: 'every valid workout in the batch committed server-side',
        );
        expect(
          queue.getAll(),
          isEmpty,
          reason: 'a clean batch fully drains the queue',
        );
      },
    );
  });
}
