import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/workouts/models/cardio_session.dart';

void main() {
  final session = CardioSession(
    id: 'cardio-001',
    workoutId: 'workout-001',
    exerciseId: 'exercise-treadmill',
    durationSeconds: 1725, // 28:45
    distanceM: 5200.0,
    rpe: 7,
    isCompleted: true,
    createdAt: DateTime.utc(2026, 6, 12, 10, 30),
  );

  group('CardioSession JSON round-trip (Hive crash-recovery contract)', () {
    test('toJson → fromJson preserves every field', () {
      final restored = CardioSession.fromJson(session.toJson());
      expect(restored, equals(session));
    });

    test('optional fields survive as null (empty distance / RPE)', () {
      final minimal = CardioSession(
        id: 'cardio-002',
        workoutId: 'workout-001',
        exerciseId: 'exercise-treadmill',
        durationSeconds: 1800,
        isCompleted: false,
        createdAt: DateTime.utc(2026, 6, 12),
      );
      final restored = CardioSession.fromJson(minimal.toJson());
      expect(restored.distanceM, isNull);
      expect(restored.rpe, isNull);
      expect(restored, equals(minimal));
    });

    test('missing is_completed key defaults to false (pre-38b payloads / '
        'rpc-shape maps never carry it)', () {
      final json = session.toJson()..remove('is_completed');
      final restored = CardioSession.fromJson(json);
      expect(restored.isCompleted, isFalse);
    });
  });

  group('toRpcJson (save_workout p_cardio element / offline cardioJson)', () {
    test('emits exactly the cardio_sessions column set — snake_case, ISO '
        'created_at, NO is_completed (no such column)', () {
      final rpc = session.toRpcJson();
      expect(rpc, {
        'id': 'cardio-001',
        'workout_id': 'workout-001',
        'exercise_id': 'exercise-treadmill',
        'duration_seconds': 1725,
        'distance_m': 5200.0,
        'rpe': 7,
        'created_at': '2026-06-12T10:30:00.000Z',
      });
      expect(
        rpc.containsKey('is_completed'),
        isFalse,
        reason:
            'cardio_sessions has no is_completed column — only completed '
            'entries are ever sent, so the flag must not leak into the '
            'RPC payload.',
      );
    });

    test('offline replay round-trip: fromJson(toRpcJson) re-serializes '
        'byte-identically (BUG-001 drift guard)', () {
      // The drain does CardioSession.fromJson(cardioJson) then the repo
      // re-serializes via toRpcJson() — the payload that reaches the RPC
      // after a queue round-trip must be identical to the online one.
      final replayed = CardioSession.fromJson(session.toRpcJson());
      expect(replayed.toRpcJson(), equals(session.toRpcJson()));
    });
  });
}
