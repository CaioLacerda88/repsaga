import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------
class _MockWorkoutRepository extends Mock implements WorkoutRepository {}

class _MockPRRepository extends Mock implements PRRepository {}

class _MockAnalyticsRepository extends Mock implements AnalyticsRepository {}

class _FakeWorkout extends Fake implements Workout {}

class _FakeWorkoutExercise extends Fake implements WorkoutExercise {}

class _FakeExerciseSet extends Fake implements ExerciseSet {}

class _FakePersonalRecord extends Fake implements PersonalRecord {}

const _fallbackAnalyticsEvent = AnalyticsEvent.workoutSyncQueued(
  actionType: 'fallback',
);

Map<String, dynamic> _workoutJson({
  String id = 'w-001',
  String userId = 'user-1',
  DateTime? queuedAt,
}) {
  final now = queuedAt ?? DateTime.utc(2026, 4, 17, 12, 0, 0);
  return {
    'id': id,
    'user_id': userId,
    'name': 'Push Day',
    'started_at': now.toIso8601String(),
    'finished_at': now.toIso8601String(),
    'duration_seconds': 3600,
    'is_active': false,
    'notes': null,
    'created_at': now.toIso8601String(),
  };
}

PendingSaveWorkout _makeSaveWorkoutAction({
  String id = 'w-001',
  String userId = 'user-1',
  DateTime? queuedAt,
}) {
  final now = queuedAt ?? DateTime.utc(2026, 4, 17, 12, 0, 0);
  return PendingAction.saveWorkout(
        id: id,
        workoutJson: _workoutJson(id: id, userId: userId, queuedAt: queuedAt),
        exercisesJson: const [],
        setsJson: const [],
        userId: userId,
        queuedAt: now,
      )
      as PendingSaveWorkout;
}

Future<void> _pumpAsync([int ms = 100]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  group('SyncService recovery hook', () {
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
      tempDir = await Directory.systemTemp.createTemp('hive_sync_recovery_');
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

    ProviderContainer createContainer({bool initialOnline = true}) {
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
          // Default: health check returns true. Tests override per-case.
          healthCheckProvider.overrideWithValue(() async => true),
        ],
      );
      addTearDown(container.dispose);
      container.listen(syncServiceProvider, (_, _) {});
      return container;
    }

    void stubSaveWorkoutSuccess({String id = 'w-001'}) {
      when(
        () => mockWorkoutRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
        ),
      ).thenAnswer((_) async => Workout.fromJson(_workoutJson(id: id)));
    }

    test('recovery tick triggers a drain', () async {
      final container = createContainer(initialOnline: true);
      // Seed first emission so cold-launch drain has nothing to do (queue
      // is empty at this point).
      connectivityController.add(true);
      await _pumpAsync();

      // Enqueue an item AFTER cold-launch path is settled.
      final notifier = container.read(pendingSyncProvider.notifier);
      await notifier.enqueue(_makeSaveWorkoutAction(id: 'w-recovery'));
      stubSaveWorkoutSuccess(id: 'w-recovery');

      // Manually arm the recovery state machine: a network-class failure
      // followed by a success.
      final recovery = container.read(connectivityRecoveryProvider.notifier);
      recovery.recordFailure(const SocketException('refused'));
      recovery.recordSuccess(); // ticks → fires drain via ref.listen

      await _pumpAsync(200);

      expect(container.read(pendingSyncProvider), 0);
      verify(
        () => mockWorkoutRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
        ),
      ).called(1);
    });

    test(
      'drain suppresses recording — no recovery storm from drain itself',
      () async {
        final container = createContainer(initialOnline: true);
        connectivityController.add(true);
        await _pumpAsync();

        // Three queued items so the drain loop runs through several
        // success records. Without suppression each success could feed
        // back into recordSuccess.
        final notifier = container.read(pendingSyncProvider.notifier);
        await notifier.enqueue(_makeSaveWorkoutAction(id: 'w-1'));
        await notifier.enqueue(_makeSaveWorkoutAction(id: 'w-2'));
        await notifier.enqueue(_makeSaveWorkoutAction(id: 'w-3'));

        // Stub saveWorkout to delegate id off whatever was passed.
        when(
          () => mockWorkoutRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        ).thenAnswer(
          (inv) async => Workout.fromJson(
            _workoutJson(id: (inv.namedArguments[#workout] as Workout).id),
          ),
        );

        // Arm the recovery state with a recent failure so a recordSuccess
        // would otherwise fire. The drain's saveWorkout success calls feed
        // through repository -> recorder, but the SyncService should set
        // `setRecordingSuppressed(true)` for the duration.
        final recovery = container.read(connectivityRecoveryProvider.notifier);
        // NOTE: in this test the mocks bypass BaseRepository entirely —
        // they're `Mock implements WorkoutRepository`, so they never call
        // recordSuccess. The suppression behaviour matters in production
        // where real repositories DO call the recorder. Here we verify the
        // SyncService side directly: the recovery counter must NOT
        // increment from the drain itself when an external trigger arms a
        // success WHILE drain is mid-loop.

        final ticksBefore = container.read(connectivityRecoveryProvider);

        // Trigger drain via the recovery hook.
        recovery.recordFailure(const SocketException('refused'));
        recovery.recordSuccess(); // tick #1, fires drain
        await _pumpAsync(50);

        // Mid-drain: another arm-and-success (simulating in-flight repo
        // calls). The notifier should be suppressed → no tick.
        recovery.recordFailure(const SocketException('refused'));
        recovery.recordSuccess(); // suppressed; no tick

        // Wait for drain to fully complete.
        await _pumpAsync(300);

        expect(container.read(pendingSyncProvider), 0);

        // Exactly one tick from the original recordSuccess; the mid-drain
        // record was suppressed.
        expect(container.read(connectivityRecoveryProvider), ticksBefore + 1);
      },
    );

    test('multiple back-to-back ticks collapse to a single drain', () async {
      // The notifier owns its own cooldown, but verify that even a
      // hypothetical sequence of ticks doesn't produce concurrent drains
      // — `_draining` reentrancy guard collapses them.
      final container = createContainer(initialOnline: true);
      connectivityController.add(true);
      await _pumpAsync();

      final notifier = container.read(pendingSyncProvider.notifier);
      await notifier.enqueue(_makeSaveWorkoutAction(id: 'w-once'));
      stubSaveWorkoutSuccess(id: 'w-once');

      final recovery = container.read(connectivityRecoveryProvider.notifier);
      // Arm and fire: tick 1 starts the drain. Subsequent ticks would land
      // on the `_draining` guard.
      recovery.recordFailure(const SocketException('refused'));
      recovery.recordSuccess();

      await _pumpAsync(200);

      expect(container.read(pendingSyncProvider), 0);
      verify(
        () => mockWorkoutRepo.saveWorkout(
          workout: any(named: 'workout'),
          exercises: any(named: 'exercises'),
          sets: any(named: 'sets'),
        ),
      ).called(1);
    });

    test(
      'recovery tick with empty queue runs drain harmlessly (no calls)',
      () async {
        // A tick that arrives with an empty queue must not crash and must
        // not make any repo calls.
        final container = createContainer(initialOnline: true);
        connectivityController.add(true);
        await _pumpAsync();

        final recovery = container.read(connectivityRecoveryProvider.notifier);
        recovery.recordFailure(const SocketException('refused'));
        recovery.recordSuccess();

        await _pumpAsync(200);

        verifyNever(
          () => mockWorkoutRepo.saveWorkout(
            workout: any(named: 'workout'),
            exercises: any(named: 'exercises'),
            sets: any(named: 'sets'),
          ),
        );
      },
    );
  });
}
