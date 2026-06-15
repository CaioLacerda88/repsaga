import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/offline/pending_action.dart';

void main() {
  group('PendingAction serialization', () {
    final now = DateTime.utc(2026, 4, 17, 12, 0, 0);

    group('PendingSaveWorkout', () {
      test('roundtrips through toJson/fromJson', () {
        final action = PendingAction.saveWorkout(
          id: 'w-001',
          workoutJson: {'id': 'w-001', 'user_id': 'u-1', 'name': 'Push Day'},
          exercisesJson: [
            {'id': 'we-1', 'exercise_id': 'e-1', 'order': 0},
          ],
          setsJson: [
            {
              'id': 's-1',
              'workout_exercise_id': 'we-1',
              'set_number': 1,
              'weight': 60.0,
            },
          ],
          userId: 'u-1',
          queuedAt: now,
        );

        final json = action.toJson();
        final restored = PendingAction.fromJson(json);

        expect(restored, isA<PendingSaveWorkout>());
        final typed = restored as PendingSaveWorkout;
        expect(typed.id, 'w-001');
        expect(typed.workoutJson['name'], 'Push Day');
        expect(typed.exercisesJson.length, 1);
        expect(typed.setsJson.length, 1);
        expect(typed.userId, 'u-1');
        expect(typed.queuedAt, now);
        expect(typed.retryCount, 0);
        expect(typed.lastError, isNull);
      });

      test('preserves retryCount and lastError', () {
        final action = PendingAction.saveWorkout(
          id: 'w-002',
          workoutJson: {'id': 'w-002'},
          exercisesJson: const [],
          setsJson: const [],
          userId: 'u-1',
          queuedAt: now,
          retryCount: 3,
          lastError: 'NetworkException: timeout',
        );

        final json = action.toJson();
        final restored = PendingAction.fromJson(json);

        final typed = restored as PendingSaveWorkout;
        expect(typed.retryCount, 3);
        expect(typed.lastError, 'NetworkException: timeout');
      });

      // Phase 38b: a queue entry written by a PRE-38b build (no cardio
      // concept) and read back AFTER the app upgrades has no `cardio_json`
      // key in its Hive blob. The factory always writes the key, so the
      // round-trip tests above never exercise the missing-key path — this
      // pins it directly. Missing key must default to an empty list (not
      // throw, not null), keeping legacy save-workout replays valid.
      test(
        'deserializes a legacy blob WITHOUT cardio_json to an empty list',
        () {
          final legacyJson = <String, dynamic>{
            'type': 'saveWorkout',
            'id': 'w-legacy',
            'workout_json': {'id': 'w-legacy', 'user_id': 'u-1'},
            'exercises_json': <Map<String, dynamic>>[
              {'id': 'we-1', 'exercise_id': 'e-1', 'order': 0},
            ],
            'sets_json': <Map<String, dynamic>>[
              {'id': 's-1', 'workout_exercise_id': 'we-1', 'set_number': 1},
            ],
            // NO 'cardio_json' key — this is the pre-38b shape.
            'user_id': 'u-1',
            'queued_at': now.toIso8601String(),
          };

          final restored = PendingAction.fromJson(legacyJson);

          expect(restored, isA<PendingSaveWorkout>());
          final typed = restored as PendingSaveWorkout;
          expect(typed.cardioJson, const <Map<String, dynamic>>[]);
          // The rest of the legacy payload still deserializes unchanged.
          expect(typed.id, 'w-legacy');
          expect(typed.exercisesJson.length, 1);
          expect(typed.setsJson.length, 1);
        },
      );
    });

    group('PendingUpsertRecords', () {
      test('roundtrips through toJson/fromJson', () {
        final action = PendingAction.upsertRecords(
          id: 'pr-action-1',
          recordsJson: [
            {
              'id': 'pr-1',
              'user_id': 'u-1',
              'exercise_id': 'e-1',
              'record_type': 'max_weight',
              'value': 100.0,
              'achieved_at': now.toIso8601String(),
            },
          ],
          userId: 'u-1',
          queuedAt: now,
        );

        final json = action.toJson();
        final restored = PendingAction.fromJson(json);

        expect(restored, isA<PendingUpsertRecords>());
        final typed = restored as PendingUpsertRecords;
        expect(typed.id, 'pr-action-1');
        expect(typed.recordsJson.length, 1);
        expect(typed.recordsJson.first['value'], 100.0);
        expect(typed.queuedAt, now);
        expect(typed.retryCount, 0);
      });

      // Phase 14d: userId must survive JSON round-trip so SyncService can
      // pass it to _reconcilePrCache after a successful upsertRecords drain.
      test('userId field round-trips correctly through toJson/fromJson', () {
        final action = PendingAction.upsertRecords(
          id: 'pr-action-userId',
          recordsJson: const [],
          userId: 'user-xyz-789',
          queuedAt: now,
        );

        final json = action.toJson();
        final restored = PendingAction.fromJson(json);

        final typed = restored as PendingUpsertRecords;
        expect(typed.userId, 'user-xyz-789');
      });

      test('preserves retryCount and lastError through toJson/fromJson', () {
        final action = PendingAction.upsertRecords(
          id: 'pr-action-retry',
          recordsJson: const [],
          userId: 'u-1',
          queuedAt: now,
          retryCount: 4,
          lastError: 'RPC failed',
        );

        final json = action.toJson();
        final restored = PendingAction.fromJson(json) as PendingUpsertRecords;

        expect(restored.retryCount, 4);
        expect(restored.lastError, 'RPC failed');
      });
    });

    group('PendingMarkRoutineComplete', () {
      test('roundtrips through toJson/fromJson', () {
        final action = PendingAction.markRoutineComplete(
          id: 'rc-action-1',
          planId: 'plan-1',
          routineId: 'routine-1',
          workoutId: 'w-001',
          queuedAt: now,
        );

        final json = action.toJson();
        final restored = PendingAction.fromJson(json);

        expect(restored, isA<PendingMarkRoutineComplete>());
        final typed = restored as PendingMarkRoutineComplete;
        expect(typed.id, 'rc-action-1');
        expect(typed.planId, 'plan-1');
        expect(typed.routineId, 'routine-1');
        expect(typed.workoutId, 'w-001');
        expect(typed.queuedAt, now);
      });
    });

    test('discriminator field is set correctly', () {
      expect(
        PendingAction.saveWorkout(
          id: '1',
          workoutJson: const {},
          exercisesJson: const [],
          setsJson: const [],
          userId: 'u',
          queuedAt: now,
        ).toJson()['type'],
        'saveWorkout',
      );
      expect(
        PendingAction.upsertRecords(
          id: '2',
          recordsJson: const [],
          userId: 'u',
          queuedAt: now,
        ).toJson()['type'],
        'upsertRecords',
      );
      expect(
        PendingAction.markRoutineComplete(
          id: '3',
          planId: 'p',
          routineId: 'r',
          workoutId: 'w',
          queuedAt: now,
        ).toJson()['type'],
        'markRoutineComplete',
      );
    });
  });
}
