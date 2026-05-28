import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/observability/sentry_report.dart';
import 'package:repsaga/core/offline/offline_queue_service.dart';
import 'package:repsaga/core/offline/pending_action.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  group('OfflineQueueService', () {
    late Directory tempDir;
    const service = OfflineQueueService();
    final now = DateTime.utc(2026, 4, 17, 12, 0, 0);

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_offline_queue_');
      Hive.init(tempDir.path);
      await Hive.openBox<dynamic>('offline_queue');
    });

    tearDown(() async {
      await Hive.close();
      await tempDir.delete(recursive: true);
    });

    PendingAction makeSaveWorkout(String id, {DateTime? queuedAt}) {
      return PendingAction.saveWorkout(
        id: id,
        workoutJson: {'id': id},
        exercisesJson: const [],
        setsJson: const [],
        userId: 'user-1',
        queuedAt: queuedAt ?? now,
      );
    }

    test('enqueue stores action and increments pendingCount', () async {
      expect(service.pendingCount, 0);

      await service.enqueue(makeSaveWorkout('w-1'));

      expect(service.pendingCount, 1);
    });

    test('dequeue removes action and decrements pendingCount', () async {
      await service.enqueue(makeSaveWorkout('w-1'));
      expect(service.pendingCount, 1);

      await service.dequeue('w-1');

      expect(service.pendingCount, 0);
    });

    test('dequeue does not throw for nonexistent key', () async {
      await expectLater(service.dequeue('nonexistent'), completes);
    });

    test('getAll returns actions sorted by queuedAt', () async {
      final later = now.add(const Duration(hours: 1));
      final earlier = now.subtract(const Duration(hours: 1));

      await service.enqueue(makeSaveWorkout('w-now', queuedAt: now));
      await service.enqueue(makeSaveWorkout('w-later', queuedAt: later));
      await service.enqueue(makeSaveWorkout('w-earlier', queuedAt: earlier));

      final all = service.getAll();

      expect(all.length, 3);
      expect(all[0].id, 'w-earlier');
      expect(all[1].id, 'w-now');
      expect(all[2].id, 'w-later');
    });

    test('getAll skips corrupt entries silently', () async {
      // Write valid action
      await service.enqueue(makeSaveWorkout('w-valid'));
      // Write corrupt data directly
      await Hive.box<dynamic>('offline_queue').put('bad', 'not valid json');

      final all = service.getAll();

      expect(all.length, 1);
      expect(all.first.id, 'w-valid');
    });

    test('updateAction overwrites existing entry', () async {
      final original = makeSaveWorkout('w-1');
      await service.enqueue(original);

      final updated = (original as PendingSaveWorkout).copyWith(
        retryCount: 2,
        lastError: 'timeout',
      );
      await service.updateAction(updated);

      final all = service.getAll();
      expect(all.length, 1);
      final restored = all.first as PendingSaveWorkout;
      expect(restored.retryCount, 2);
      expect(restored.lastError, 'timeout');
    });

    test('pendingCount reflects all item types', () async {
      await service.enqueue(makeSaveWorkout('w-1'));
      await service.enqueue(
        PendingAction.upsertRecords(
          id: 'pr-1',
          recordsJson: const [],
          userId: 'user-1',
          queuedAt: now,
        ),
      );
      await service.enqueue(
        PendingAction.markRoutineComplete(
          id: 'rc-1',
          planId: 'p-1',
          routineId: 'r-1',
          workoutId: 'w-1',
          queuedAt: now,
        ),
      );

      expect(service.pendingCount, 3);
    });

    // ----------------------------------------------------------------
    // BUG-007: Hive failures must rethrow + capture to Sentry. Without
    // these guarantees: a silently-swallowed enqueue loses user data, a
    // swallowed dequeue causes duplicate replays, a swallowed
    // updateAction breaks retryCount monotonicity (loops forever past
    // kMaxSyncRetries). `getAll` keeps its skip-corrupt behavior — one
    // bad row must not block the whole queue — but must capture too so
    // we get production rates on corruption.
    // ----------------------------------------------------------------
    group('BUG-007: Hive failures rethrow and capture to Sentry', () {
      late int captureCount;
      late Object? lastCapturedError;

      setUp(() {
        captureCount = 0;
        lastCapturedError = null;
        SentryReport.debugSetCaptureFn((error, {stackTrace}) async {
          captureCount++;
          lastCapturedError = error;
          return const SentryId.empty();
        });
      });

      tearDown(() {
        SentryReport.debugSetCaptureFn(null);
      });

      test(
        'enqueue rethrows when the queue box is closed and captures to Sentry',
        () async {
          // Close the box so the underlying Hive call throws.
          await Hive.box<dynamic>('offline_queue').close();

          await expectLater(
            service.enqueue(makeSaveWorkout('w-fail-enqueue')),
            throwsA(isA<Object>()),
          );

          // Sentry forwarding must have fired exactly once.
          expect(captureCount, 1);
          expect(lastCapturedError, isNotNull);
        },
      );

      test(
        'dequeue rethrows when the queue box is closed and captures to Sentry',
        () async {
          // Pre-populate so dequeue has something to attempt.
          await service.enqueue(makeSaveWorkout('w-stale'));
          await Hive.box<dynamic>('offline_queue').close();

          await expectLater(service.dequeue('w-stale'), throwsA(isA<Object>()));
          expect(captureCount, 1);
        },
      );

      test(
        'updateAction rethrows when the queue box is closed and captures',
        () async {
          final original =
              makeSaveWorkout('w-update-fail') as PendingSaveWorkout;
          await service.enqueue(original);
          await Hive.box<dynamic>('offline_queue').close();

          final updated = original.copyWith(
            retryCount: 1,
            lastError: 'attempt 1',
          );

          await expectLater(
            service.updateAction(updated),
            throwsA(isA<Object>()),
          );
          expect(captureCount, 1);
        },
      );

      test(
        'getAll skips corrupt rows AND captures each skip to Sentry',
        () async {
          // Two corrupt rows + one valid.
          await service.enqueue(makeSaveWorkout('w-valid-2'));
          await Hive.box<dynamic>('offline_queue').put('bad-1', 'not json');
          await Hive.box<dynamic>('offline_queue').put('bad-2', '{not:valid}');

          final all = service.getAll();

          // Skip-corrupt invariant intact — one valid row only.
          expect(all.length, 1);
          expect(all.first.id, 'w-valid-2');

          // BUG-007: each corrupt skip must capture to Sentry so we get
          // production rates on corruption.
          expect(captureCount, 2);
        },
      );
    });

    test('getAll deserializes every supported action type', () async {
      await service.enqueue(makeSaveWorkout('w-1'));
      await service.enqueue(
        PendingAction.upsertRecords(
          id: 'pr-1',
          recordsJson: const [],
          userId: 'user-1',
          queuedAt: now.add(const Duration(seconds: 1)),
        ),
      );
      await service.enqueue(
        PendingAction.markRoutineComplete(
          id: 'rc-1',
          planId: 'p-1',
          routineId: 'r-1',
          workoutId: 'w-1',
          queuedAt: now.add(const Duration(seconds: 2)),
        ),
      );

      final all = service.getAll();
      expect(all.length, 3);
      expect(all[0], isA<PendingSaveWorkout>());
      expect(all[1], isA<PendingUpsertRecords>());
      expect(all[2], isA<PendingMarkRoutineComplete>());
    });

    // -----------------------------------------------------------------
    // purgeRetiredKinds: defensive cleanup for queue entries whose
    // discriminator was removed from the PendingAction sealed union.
    // Currently covers the retired `createExercise` kind (Phase 32 PR
    // 32h). Without this purge, a legacy local-dev Hive box from before
    // the retirement would throw on PendingAction.fromJson — Freezed
    // raises on an unknown `type` union key. The purge string-matches
    // raw JSON BEFORE deserialization so it sidesteps that crash.
    // -----------------------------------------------------------------
    group('purgeRetiredKinds', () {
      test('drops legacy createExercise rows and returns the count', () async {
        // Mix one healthy save_workout with two legacy createExercise blobs
        // shaped exactly as Freezed would have serialized them pre-deletion.
        await service.enqueue(makeSaveWorkout('w-healthy'));
        const legacyA =
            '{"type":"createExercise","id":"ce-old-1",'
            '"exercise_id":"ex-1","user_id":"u-1","locale":"en",'
            '"name":"Custom Bench","muscle_group":"chest",'
            '"equipment_type":"barbell","queued_at":"2026-04-17T10:00:00.000Z"}';
        const legacyB =
            '{"type":"createExercise","id":"ce-old-2",'
            '"exercise_id":"ex-2","user_id":"u-1","locale":"pt",'
            '"name":"Supino","muscle_group":"chest",'
            '"equipment_type":"barbell","queued_at":"2026-04-17T11:00:00.000Z"}';
        await Hive.box<dynamic>('offline_queue').put('ce-old-1', legacyA);
        await Hive.box<dynamic>('offline_queue').put('ce-old-2', legacyB);

        expect(service.pendingCount, 3);

        final dropped = service.purgeRetiredKinds();

        expect(dropped, 2);
        expect(service.pendingCount, 1);
        // The healthy entry survives — deserializing it works as before.
        final all = service.getAll();
        expect(all, hasLength(1));
        expect(all.first.id, 'w-healthy');
      });

      test('is idempotent: a second call drops nothing', () async {
        const legacy =
            '{"type":"createExercise","id":"ce-old","exercise_id":"e",'
            '"user_id":"u","locale":"en","name":"X","muscle_group":"chest",'
            '"equipment_type":"barbell","queued_at":"2026-04-17T10:00:00.000Z"}';
        await Hive.box<dynamic>('offline_queue').put('ce-old', legacy);

        expect(service.purgeRetiredKinds(), 1);
        expect(service.purgeRetiredKinds(), 0);
        expect(service.pendingCount, 0);
      });

      test('leaves healthy queues untouched', () async {
        await service.enqueue(makeSaveWorkout('w-1'));
        await service.enqueue(
          PendingAction.upsertRecords(
            id: 'pr-1',
            recordsJson: const [],
            userId: 'user-1',
            queuedAt: now,
          ),
        );

        final dropped = service.purgeRetiredKinds();

        expect(dropped, 0);
        expect(service.pendingCount, 2);
      });

      test('swallows unparseable rows without aborting the sweep', () async {
        // One unparseable blob plus a legitimate legacy entry. The bad blob
        // must not block the purge of the legacy entry that follows it.
        await Hive.box<dynamic>('offline_queue').put('bad', 'not json{');
        const legacy =
            '{"type":"createExercise","id":"ce-old","exercise_id":"e",'
            '"user_id":"u","locale":"en","name":"X","muscle_group":"chest",'
            '"equipment_type":"barbell","queued_at":"2026-04-17T10:00:00.000Z"}';
        await Hive.box<dynamic>('offline_queue').put('ce-old', legacy);

        final dropped = service.purgeRetiredKinds();

        // Only the legacy entry was dropped; the malformed row stays for
        // `getAll`'s corrupt-row guard to surface via Sentry.
        expect(dropped, 1);
      });
    });
  });
}
