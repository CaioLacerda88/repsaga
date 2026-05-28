import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/core/connectivity/connectivity_provider.dart';
import 'package:repsaga/core/connectivity/connectivity_recovery_provider.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';
import 'package:repsaga/core/offline/health_check_provider.dart';
import 'package:repsaga/core/offline/offline_queue_service.dart';
import 'package:repsaga/core/offline/pending_action.dart';
import 'package:repsaga/core/offline/pending_sync_provider.dart';
import 'package:repsaga/core/offline/sync_service.dart';
import 'package:repsaga/features/analytics/data/analytics_repository.dart';
import 'package:repsaga/features/analytics/data/models/analytics_event.dart';
import 'package:repsaga/features/analytics/providers/analytics_providers.dart';
import 'package:repsaga/features/personal_records/data/pr_repository.dart';
import 'package:repsaga/features/personal_records/models/personal_record.dart';
import 'package:repsaga/features/personal_records/providers/pr_providers.dart';
import 'package:repsaga/features/workouts/data/workout_repository.dart';
import 'package:repsaga/features/workouts/models/exercise_set.dart';
import 'package:repsaga/features/workouts/models/workout.dart';
import 'package:repsaga/features/workouts/models/workout_exercise.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';

class _MockWorkoutRepository extends Mock implements WorkoutRepository {}

class _MockPRRepository extends Mock implements PRRepository {}

class _MockAnalyticsRepository extends Mock implements AnalyticsRepository {}

/// Queue stub whose every read throws — simulates a closed/missing Hive
/// box. Used to pin the defensive guard in `SyncService._hasTransientItems`
/// against future regressions.
///
/// Throws [HiveError] (which `extends Error`) — the same shape the real
/// `OfflineQueueService` raises when the `offline_queue` box hasn't been
/// opened. The guard's `on HiveError` clause must absorb this; the parallel
/// `on Exception` clause covers other transient infrastructure failures.
/// Programming errors (`StateError`, `TypeError`, ...) intentionally fall
/// through so genuine bugs surface loudly.
class _ThrowingQueueService implements OfflineQueueService {
  const _ThrowingQueueService();

  @override
  List<PendingAction> getAll() {
    throw HiveError('Box not found. Did you forget to call Hive.openBox()?');
  }

  @override
  Future<void> enqueue(PendingAction action) async {
    throw HiveError('Box not found. Did you forget to call Hive.openBox()?');
  }

  @override
  Future<void> dequeue(String id) async {
    throw HiveError('Box not found. Did you forget to call Hive.openBox()?');
  }

  @override
  Future<void> updateAction(PendingAction action) async {
    throw HiveError('Box not found. Did you forget to call Hive.openBox()?');
  }

  @override
  int get pendingCount =>
      throw HiveError('Box not found. Did you forget to call Hive.openBox()?');

  @override
  Future<int> purgeRetiredKinds() async {
    // Stub follows the real impl's defensive contract: box-level failures
    // are swallowed and the call returns 0 dropped. This keeps the
    // SyncService cold-launch purge from breaking when the queue box is
    // unavailable in this test harness.
    return 0;
  }
}

class _FakeWorkout extends Fake implements Workout {}

class _FakeWorkoutExercise extends Fake implements WorkoutExercise {}

class _FakeExerciseSet extends Fake implements ExerciseSet {}

class _FakePersonalRecord extends Fake implements PersonalRecord {}

const _fallbackAnalyticsEvent = AnalyticsEvent.workoutSyncQueued(
  actionType: 'fallback',
);

Map<String, dynamic> _workoutJson({String id = 'w-001'}) {
  final now = DateTime.utc(2026, 4, 17, 12, 0, 0);
  return {
    'id': id,
    'user_id': 'user-1',
    'name': 'Push Day',
    'started_at': now.toIso8601String(),
    'finished_at': now.toIso8601String(),
    'duration_seconds': 3600,
    'is_active': false,
    'notes': null,
    'created_at': now.toIso8601String(),
  };
}

PendingSaveWorkout _makeAction({String id = 'w-001', int retryCount = 0}) {
  final now = DateTime.utc(2026, 4, 17, 12, 0, 0);
  return PendingAction.saveWorkout(
        id: id,
        workoutJson: _workoutJson(id: id),
        exercisesJson: const [],
        setsJson: const [],
        userId: 'user-1',
        queuedAt: now,
        retryCount: retryCount,
      )
      as PendingSaveWorkout;
}

Future<void> _pumpAsync([int ms = 100]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  // Tight cadence so tests can verify multiple ticks in real wall time
  // without using fake_async (Hive's real I/O futures don't compose with
  // fake_async — see the failed prior iteration of this file).
  const testInterval = Duration(milliseconds: 50);

  group('SyncService health-check timer', () {
    late Directory tempDir;
    late OfflineQueueService queueService;
    late _MockWorkoutRepository mockWorkoutRepo;
    late _MockPRRepository mockPRRepo;
    late _MockAnalyticsRepository mockAnalyticsRepo;
    late StreamController<bool> connectivityController;

    setUpAll(() {
      registerFallbackValue(_FakeWorkout());
      registerFallbackValue(_FakeWorkoutExercise());
      registerFallbackValue(_FakeExerciseSet());
      registerFallbackValue(_FakePersonalRecord());
      registerFallbackValue(_fallbackAnalyticsEvent);
      registerFallbackValue(<WorkoutExercise>[]);
      registerFallbackValue(<ExerciseSet>[]);
      registerFallbackValue(<PersonalRecord>[]);
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_sync_health_');
      Hive.init(tempDir.path);
      await Hive.openBox<dynamic>('offline_queue');
      await Hive.openBox<dynamic>(HiveService.userPrefs);
      queueService = const OfflineQueueService();
      mockWorkoutRepo = _MockWorkoutRepository();
      mockPRRepo = _MockPRRepository();
      mockAnalyticsRepo = _MockAnalyticsRepository();
      connectivityController = StreamController<bool>.broadcast();

      when(
        () => mockAnalyticsRepo.insertEvent(
          userId: any(named: 'userId'),
          event: any(named: 'event'),
          platform: any(named: 'platform'),
          appVersion: any(named: 'appVersion'),
        ),
      ).thenAnswer((_) async {});
    });

    tearDown(() async {
      await connectivityController.close();
      await Hive.close();
      await tempDir.delete(recursive: true);
    });

    ProviderContainer createContainer({
      required HealthCheck healthCheck,
      Duration interval = testInterval,
      bool initialOnline = true,
    }) {
      final container = ProviderContainer(
        overrides: [
          onlineStatusProvider.overrideWith(
            (ref) => connectivityController.stream,
          ),
          isOnlineProvider.overrideWith((ref) {
            return ref.watch(onlineStatusProvider).value ?? initialOnline;
          }),
          offlineQueueServiceProvider.overrideWithValue(queueService),
          workoutRepositoryProvider.overrideWithValue(mockWorkoutRepo),
          prRepositoryProvider.overrideWithValue(mockPRRepo),
          analyticsRepositoryProvider.overrideWithValue(mockAnalyticsRepo),
          healthCheckProvider.overrideWithValue(healthCheck),
          healthCheckIntervalProvider.overrideWithValue(interval),
        ],
      );
      addTearDown(container.dispose);
      container.listen(syncServiceProvider, (_, _) {});
      return container;
    }

    test('does not start health-check when queue is empty', () async {
      var probeCalls = 0;
      Future<bool> probe() async {
        probeCalls++;
        return true;
      }

      final container = createContainer(healthCheck: probe);
      connectivityController.add(true);

      // Wait several intervals — empty queue, no probe should fire.
      await _pumpAsync(testInterval.inMilliseconds * 4);

      expect(probeCalls, 0);
      expect(container.read(pendingSyncProvider), 0);
    });

    test('starts health-check when a transient item enqueues', () async {
      var probeCalls = 0;
      Future<bool> probe() async {
        probeCalls++;
        return false; // Recorded as failure — won't tick recovery on its own.
      }

      final container = createContainer(healthCheck: probe);
      connectivityController.add(true);
      await _pumpAsync();

      final notifier = container.read(pendingSyncProvider.notifier);
      await notifier.enqueue(_makeAction(id: 'w-1'));

      // Wait ~3 intervals — expect at least 2 probes.
      await _pumpAsync(testInterval.inMilliseconds * 4);

      expect(probeCalls, greaterThanOrEqualTo(2));

      // Drain the queue. Timer should stop on next tick.
      await notifier.dismissItem('w-1');

      final calledBefore = probeCalls;
      await _pumpAsync(testInterval.inMilliseconds * 4);
      // At most one more probe could fire from a tick already in flight,
      // but no more after that.
      expect(probeCalls, lessThanOrEqualTo(calledBefore + 1));
    });

    test(
      'success probe with armed failure window ticks recovery and drains',
      () async {
        // Queue has one item. Probe returns false on first call (records
        // a network failure), then true on subsequent calls (records a
        // success that ticks the recovery counter -> drain).
        var probeCalls = 0;
        Future<bool> probe() async {
          probeCalls++;
          return probeCalls > 1; // First false, then true.
        }

        when(
          () => mockWorkoutRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).thenAnswer(
          (_) async => Workout.fromJson(_workoutJson(id: 'w-probe')),
        );

        final container = createContainer(healthCheck: probe);
        connectivityController.add(true);
        await _pumpAsync();

        final notifier = container.read(pendingSyncProvider.notifier);
        await notifier.enqueue(_makeAction(id: 'w-probe'));

        // Wait long enough for first failure probe + second success probe
        // + the resulting drain to complete.
        await _pumpAsync(testInterval.inMilliseconds * 6);

        expect(probeCalls, greaterThanOrEqualTo(2));
        expect(container.read(pendingSyncProvider), 0);
      },
    );

    test(
      'does not start health-check when only terminal items remain',
      () async {
        var probeCalls = 0;
        Future<bool> probe() async {
          probeCalls++;
          return true;
        }

        final container = createContainer(healthCheck: probe);
        connectivityController.add(true);
        await _pumpAsync();

        final notifier = container.read(pendingSyncProvider.notifier);
        await notifier.enqueue(
          _makeAction(id: 'w-terminal', retryCount: kMaxSyncRetries),
        );

        await _pumpAsync(testInterval.inMilliseconds * 4);

        expect(probeCalls, 0);
        expect(container.read(pendingSyncProvider), 1);
      },
    );

    test('probe exception is recorded as failure (timer survives)', () async {
      var probeCalls = 0;
      Future<bool> probe() async {
        probeCalls++;
        throw const SocketException('refused');
      }

      final container = createContainer(healthCheck: probe);
      connectivityController.add(true);
      await _pumpAsync();

      final notifier = container.read(pendingSyncProvider.notifier);
      await notifier.enqueue(_makeAction(id: 'w-throws'));

      await _pumpAsync(testInterval.inMilliseconds * 4);

      // Multiple intervals must have elapsed and the timer must keep
      // firing despite the throw.
      expect(probeCalls, greaterThanOrEqualTo(2));
      // No success ever recorded → recovery counter never ticked.
      expect(container.read(connectivityRecoveryProvider), 0);
    });

    test(
      'queue read failure during build does not propagate (defensive guard)',
      () async {
        // Regression coverage: home-screen widget tests build SyncService
        // without initialising the `offline_queue` Hive box. Pre-fix, the
        // eager `_evaluateHealthCheckTimer` call inside `build()` would
        // throw a `HiveError: Box not found` straight up the widget tree.
        // The defensive try/catch in `_hasTransientItems` collapses an
        // unreadable queue to "no transient items" — the health-check stays
        // off and the build completes cleanly.
        var probeCalls = 0;
        Future<bool> probe() async {
          probeCalls++;
          return true;
        }

        // Override the queue with one that throws on every read.
        final container = ProviderContainer(
          overrides: [
            onlineStatusProvider.overrideWith(
              (ref) => connectivityController.stream,
            ),
            isOnlineProvider.overrideWith((ref) {
              return ref.watch(onlineStatusProvider).value ?? true;
            }),
            offlineQueueServiceProvider.overrideWithValue(
              const _ThrowingQueueService(),
            ),
            workoutRepositoryProvider.overrideWithValue(mockWorkoutRepo),
            prRepositoryProvider.overrideWithValue(mockPRRepo),
            analyticsRepositoryProvider.overrideWithValue(mockAnalyticsRepo),
            healthCheckProvider.overrideWithValue(probe),
            healthCheckIntervalProvider.overrideWithValue(testInterval),
          ],
        );
        addTearDown(container.dispose);

        // Building must not throw. Pre-fix, this line raised through
        // `_evaluateHealthCheckTimer` -> `_hasTransientItems` ->
        // `OfflineQueueService.getAll`.
        expect(
          () => container.listen(syncServiceProvider, (_, _) {}),
          returnsNormally,
        );

        connectivityController.add(true);
        await _pumpAsync(testInterval.inMilliseconds * 3);

        // Health check must not have fired — unreadable queue is treated
        // as "no transient items".
        expect(probeCalls, 0);
      },
    );

    test('canceling the container cancels the health-check timer', () async {
      var probeCalls = 0;
      Future<bool> probe() async {
        probeCalls++;
        return true;
      }

      final container = createContainer(healthCheck: probe);
      connectivityController.add(true);
      await _pumpAsync();

      final notifier = container.read(pendingSyncProvider.notifier);
      await notifier.enqueue(_makeAction(id: 'w-1'));

      await _pumpAsync(testInterval.inMilliseconds * 2);
      final calledBefore = probeCalls;
      expect(calledBefore, greaterThan(0));

      // Dispose the container — timer must be cancelled.
      container.dispose();
      // Run a few intervals after disposal — no further probes.
      await _pumpAsync(testInterval.inMilliseconds * 4);
      expect(probeCalls, calledBefore);
    });
  });
}
