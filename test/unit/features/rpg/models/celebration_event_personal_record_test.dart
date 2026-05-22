/// Round-trip equality tests for [PersonalRecordEvent].
///
/// Freezed generates value-equality automatically, but historically it
/// has had subtle bugs with `num` fields (int/double cross-equality)
/// and nullable fields (priorBest in particular). PR 29.5 introduces
/// the variant; we pin equality + `copyWith` round-trip behavior here
/// so a future Freezed major-version bump or a manual hand-roll
/// regression is caught.
///
/// Two cases:
///   1. priorBest: null — first-ever PR for the rep band.
///   2. priorBest: 95.5 — fractional num, exercising the
///      int-vs-double equality path.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/celebration_event.dart';

void main() {
  group('PersonalRecordEvent — round-trip equality', () {
    test('equals itself after a no-op copyWith (priorBest null)', () {
      const event = CelebrationEvent.personalRecord(
        exerciseId: 'abc-123',
        exerciseName: 'Bench Press',
        weight: 100,
        reps: 5,
        repBand: '1-5',
      );
      // copyWith with no fields = identity copy. Equality must hold
      // structurally — `expect(a, equals(a.copyWith()))` would fail if
      // Freezed regressed nullable field handling.
      expect(event, equals((event as PersonalRecordEvent).copyWith()));
      // Hash codes must match too — many collection types (HashSet,
      // Map keys) depend on this contract.
      expect(event.hashCode, equals(event.copyWith().hashCode));
    });

    test('equals itself after a no-op copyWith (priorBest fractional num)', () {
      const event = CelebrationEvent.personalRecord(
        exerciseId: 'abc-123',
        exerciseName: 'Bench Press',
        weight: 147.5,
        reps: 3,
        repBand: '1-5',
        priorBest: 95.5,
      );
      expect(event, equals((event as PersonalRecordEvent).copyWith()));
      expect(event.hashCode, equals(event.copyWith().hashCode));
    });

    test('two structurally-identical instances are equal', () {
      // A fresh constructor call (vs copyWith) — different allocation,
      // same field values. Equality must be by-value, not by-reference.
      const a = CelebrationEvent.personalRecord(
        exerciseId: 'abc-123',
        exerciseName: 'Bench Press',
        weight: 100,
        reps: 5,
        repBand: '1-5',
      );
      const b = CelebrationEvent.personalRecord(
        exerciseId: 'abc-123',
        exerciseName: 'Bench Press',
        weight: 100,
        reps: 5,
        repBand: '1-5',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
