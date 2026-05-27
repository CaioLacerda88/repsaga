import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/workouts/domain/session_lift_summary.dart';

/// Pins [SessionLiftSummary]'s data-model contract (Phase 31 Pass 1).
///
/// The model is pure data — projection logic (sort + top-K + alphabetical
/// tiebreak) lives on `PostSessionController._buildInitial()` and is
/// covered by its own test suite. These cases pin:
///
///   1. The model holds the 7 fields the S2 Mission Debrief row needs.
///   2. Equality is Freezed-generated structural (`==` matches field-by-field).
///   3. `copyWith` mutates only the requested field.
///   4. Multi-PR sessions can tag multiple rows with `isPR: true`.
///   5. Field semantics (xpContribution is a strict number, peakReps is an
///      int, BP is enum-typed) — no `dynamic` leakage.
void main() {
  group('SessionLiftSummary', () {
    test(
      'single-exercise session row carries every required display field',
      () {
        const row = SessionLiftSummary(
          exerciseId: 'bench',
          exerciseName: 'Bench Press',
          bodyPart: BodyPart.chest,
          peakWeightKg: 95.0,
          peakReps: 5,
          xpContribution: 410,
          isPR: false,
        );

        expect(row.exerciseId, 'bench');
        expect(row.exerciseName, 'Bench Press');
        expect(row.bodyPart, BodyPart.chest);
        expect(row.peakWeightKg, 95.0);
        expect(row.peakReps, 5);
        expect(row.xpContribution, 410);
        expect(row.isPR, isFalse);
      },
    );

    test('multi-exercise session — 5 rows can coexist; model is independent of '
        'sort + top-K policy (those live in the controller)', () {
      const rows = [
        SessionLiftSummary(
          exerciseId: 'bench',
          exerciseName: 'Bench Press',
          bodyPart: BodyPart.chest,
          peakWeightKg: 95,
          peakReps: 5,
          xpContribution: 410,
          isPR: true,
        ),
        SessionLiftSummary(
          exerciseId: 'row',
          exerciseName: 'Barbell Row',
          bodyPart: BodyPart.back,
          peakWeightKg: 70,
          peakReps: 8,
          xpContribution: 320,
          isPR: false,
        ),
        SessionLiftSummary(
          exerciseId: 'squat',
          exerciseName: 'Squat',
          bodyPart: BodyPart.legs,
          peakWeightKg: 120,
          peakReps: 3,
          xpContribution: 280,
          isPR: false,
        ),
        SessionLiftSummary(
          exerciseId: 'ohp',
          exerciseName: 'Overhead Press',
          bodyPart: BodyPart.shoulders,
          peakWeightKg: 50,
          peakReps: 6,
          xpContribution: 180,
          isPR: false,
        ),
        SessionLiftSummary(
          exerciseId: 'curl',
          exerciseName: 'Barbell Curl',
          bodyPart: BodyPart.arms,
          peakWeightKg: 30,
          peakReps: 10,
          xpContribution: 90,
          isPR: false,
        ),
      ];

      // The model is a record — it stores whatever the producer hands it.
      // Order, truncation, and tiebreak rules are the controller's job.
      expect(rows.length, 5);
      expect(rows.map((r) => r.bodyPart).toSet(), {
        BodyPart.chest,
        BodyPart.back,
        BodyPart.legs,
        BodyPart.shoulders,
        BodyPart.arms,
      });
      // xpContribution is preserved at sort precision (int) regardless of
      // source approximation. Spot-check: highest XP row is bench, lowest is
      // curl — relative ordering is what downstream sort logic consumes.
      expect(rows.first.xpContribution, greaterThan(rows.last.xpContribution));
    });

    test('PR session tags exactly the lifts that set a record', () {
      // Single PR — bench is the hero; row + squat are non-PR contributors.
      const rows = [
        SessionLiftSummary(
          exerciseId: 'bench',
          exerciseName: 'Bench Press',
          bodyPart: BodyPart.chest,
          peakWeightKg: 95,
          peakReps: 5,
          xpContribution: 410,
          isPR: true,
        ),
        SessionLiftSummary(
          exerciseId: 'row',
          exerciseName: 'Barbell Row',
          bodyPart: BodyPart.back,
          peakWeightKg: 70,
          peakReps: 8,
          xpContribution: 320,
          isPR: false,
        ),
        SessionLiftSummary(
          exerciseId: 'squat',
          exerciseName: 'Squat',
          bodyPart: BodyPart.legs,
          peakWeightKg: 120,
          peakReps: 3,
          xpContribution: 280,
          isPR: false,
        ),
      ];

      final prRows = rows.where((r) => r.isPR).toList();
      expect(prRows.length, 1);
      expect(prRows.first.exerciseId, 'bench');
      expect(rows.where((r) => !r.isPR).map((r) => r.exerciseId), [
        'row',
        'squat',
      ]);
    });

    test('multi-PR session — multiple rows carry isPR: true', () {
      const rows = [
        SessionLiftSummary(
          exerciseId: 'bench',
          exerciseName: 'Bench Press',
          bodyPart: BodyPart.chest,
          peakWeightKg: 95,
          peakReps: 5,
          xpContribution: 410,
          isPR: true,
        ),
        SessionLiftSummary(
          exerciseId: 'squat',
          exerciseName: 'Squat',
          bodyPart: BodyPart.legs,
          peakWeightKg: 130,
          peakReps: 5,
          xpContribution: 380,
          isPR: true,
        ),
        SessionLiftSummary(
          exerciseId: 'row',
          exerciseName: 'Barbell Row',
          bodyPart: BodyPart.back,
          peakWeightKg: 70,
          peakReps: 8,
          xpContribution: 220,
          isPR: false,
        ),
      ];

      final prRows = rows.where((r) => r.isPR).toList();
      expect(prRows.length, 2);
      expect(prRows.map((r) => r.exerciseId).toSet(), {'bench', 'squat'});
    });

    test('equality is structural — Freezed-generated == matches '
        'field-by-field, copyWith mutates only the requested field', () {
      const a = SessionLiftSummary(
        exerciseId: 'bench',
        exerciseName: 'Bench Press',
        bodyPart: BodyPart.chest,
        peakWeightKg: 95,
        peakReps: 5,
        xpContribution: 410,
        isPR: false,
      );

      // Same field values → equal.
      const b = SessionLiftSummary(
        exerciseId: 'bench',
        exerciseName: 'Bench Press',
        bodyPart: BodyPart.chest,
        peakWeightKg: 95,
        peakReps: 5,
        xpContribution: 410,
        isPR: false,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);

      // copyWith — flip isPR only. Other fields preserved.
      final c = a.copyWith(isPR: true);
      expect(c.isPR, isTrue);
      expect(c.exerciseId, a.exerciseId);
      expect(c.exerciseName, a.exerciseName);
      expect(c.bodyPart, a.bodyPart);
      expect(c.peakWeightKg, a.peakWeightKg);
      expect(c.peakReps, a.peakReps);
      expect(c.xpContribution, a.xpContribution);
      expect(c, isNot(equals(a)));

      // copyWith — change xpContribution only.
      final d = a.copyWith(xpContribution: 500);
      expect(d.xpContribution, 500);
      expect(d.exerciseId, a.exerciseId);
      expect(d, isNot(equals(a)));
    });
  });
}
