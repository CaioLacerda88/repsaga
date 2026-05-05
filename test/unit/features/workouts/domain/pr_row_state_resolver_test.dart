/// Unit tests for [resolveRowStates] (Phase 20, commit 3).
///
/// The resolver classifies each set row in an active workout into one of
/// five [PrRowState] variants given the current set list + the canonical
/// historical [PersonalRecord]s for the exercise. It is the pure-domain
/// engine that commit 4 will wire into `set_row.dart` so the gold edge
/// frame, ghost-tinted supersession, and predicted-PR diamond render
/// correctly.
///
/// **Locked semantics** (signed off 2026-05-04, full spec in
/// `PLAN.md` Phase 20 → 5-state row matrix):
///   - "PR" means *currently standing* — best across all history INCLUDING
///     this workout's own earlier sets. A set that briefly held a PR but
///     was later superseded mid-workout drops to
///     [PrRowState.completedSupersededPr].
///   - Multi-recordType per row stays binary: a single set that broke
///     heaviest-weight + max-reps + max-volume simultaneously is one row,
///     [PrRowState.completedStandingPr] if ANY of its broken types is
///     still standing within the workout, else
///     [PrRowState.completedSupersededPr].
///   - Pending rows project against existing records AND any earlier
///     completed working sets in this same workout.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/exercises/models/exercise.dart';
import 'package:repsaga/features/personal_records/models/personal_record.dart';
import 'package:repsaga/features/personal_records/models/record_type.dart';
import 'package:repsaga/features/workouts/domain/pr_row_state.dart';
import 'package:repsaga/features/workouts/domain/pr_row_state_resolver.dart';
import 'package:repsaga/features/workouts/models/exercise_set.dart';
import 'package:repsaga/features/workouts/models/set_type.dart';

ExerciseSet _set({
  required String id,
  required int setNumber,
  double? weight,
  int? reps,
  bool isCompleted = true,
  SetType setType = SetType.working,
}) => ExerciseSet(
  id: id,
  workoutExerciseId: 'we-1',
  setNumber: setNumber,
  weight: weight,
  reps: reps,
  setType: setType,
  isCompleted: isCompleted,
  createdAt: DateTime.utc(2026, 5, 4),
);

PersonalRecord _record({
  required RecordType type,
  required double value,
  int? reps,
}) => PersonalRecord(
  id: 'pr-${type.name}',
  userId: 'user-1',
  exerciseId: 'exercise-1',
  recordType: type,
  value: value,
  achievedAt: DateTime.utc(2026, 4, 1),
  reps: reps,
);

void main() {
  group('resolveRowStates', () {
    test('case 1 — all-pending sets, no projected PR yields all none', () {
      // Existing 100x10 standing record. Pending sets are 60x5 / 70x5 / 80x5
      // — none would beat 100kg, 10 reps, OR 1000 volume. All none.
      final sets = [
        _set(id: 's1', setNumber: 1, weight: 60, reps: 5, isCompleted: false),
        _set(id: 's2', setNumber: 2, weight: 70, reps: 5, isCompleted: false),
        _set(id: 's3', setNumber: 3, weight: 80, reps: 5, isCompleted: false),
      ];
      final existing = [
        _record(type: RecordType.maxWeight, value: 100, reps: 10),
        _record(type: RecordType.maxReps, value: 10),
        _record(type: RecordType.maxVolume, value: 1000),
      ];

      final result = resolveRowStates(
        sets: sets,
        existingRecords: existing,
        equipmentType: EquipmentType.barbell,
      );

      expect(result, [PrRowState.none, PrRowState.none, PrRowState.none]);
    });

    test('case 2 — all-pending sets, one would beat existing record yields '
        'pendingPredictedPr', () {
      // Standing 60x8 = 60kg / 8 reps / 480 volume. Pending: 50x5 (no PR),
      // 65x5 (beats weight = 65>60), 55x5 (no PR).
      final sets = [
        _set(id: 's1', setNumber: 1, weight: 50, reps: 5, isCompleted: false),
        _set(id: 's2', setNumber: 2, weight: 65, reps: 5, isCompleted: false),
        _set(id: 's3', setNumber: 3, weight: 55, reps: 5, isCompleted: false),
      ];
      final existing = [
        _record(type: RecordType.maxWeight, value: 60, reps: 8),
        _record(type: RecordType.maxReps, value: 8),
        _record(type: RecordType.maxVolume, value: 480),
      ];

      final result = resolveRowStates(
        sets: sets,
        existingRecords: existing,
        equipmentType: EquipmentType.barbell,
      );

      expect(result, [
        PrRowState.none,
        PrRowState.pendingPredictedPr,
        PrRowState.none,
      ]);
    });

    test('case 3 — pending projection compares against earlier completed sets '
        'in the same workout, not just the historical record', () {
      // Standing 60kg max-weight. Set 1 completes at 70kg (new PR), set 2
      // pending at 65kg. 65 > 60 (would beat history) BUT 65 < 70 (does not
      // beat the bar set by THIS workout's set 1). Expected: set 2 = none.
      // Set 3 pending at 75kg DOES beat 70 -> pendingPredictedPr.
      final sets = [
        _set(id: 's1', setNumber: 1, weight: 70, reps: 5),
        _set(id: 's2', setNumber: 2, weight: 65, reps: 5, isCompleted: false),
        _set(id: 's3', setNumber: 3, weight: 75, reps: 5, isCompleted: false),
      ];
      final existing = [
        _record(type: RecordType.maxWeight, value: 60, reps: 8),
        // Existing reps = 10 so reps PR is already out of reach for these
        // 5-rep sets.
        _record(type: RecordType.maxReps, value: 10),
        // Existing volume large enough that no row breaks volume.
        _record(type: RecordType.maxVolume, value: 1000),
      ];

      final result = resolveRowStates(
        sets: sets,
        existingRecords: existing,
        equipmentType: EquipmentType.barbell,
      );

      // Set 1 is the standing PR for max-weight (70 > 60). Set 3 is a
      // pending predicted PR (75 > 70 running best). Set 2 (65) loses to
      // set 1's 70 — none.
      expect(result, [
        PrRowState.completedStandingPr,
        PrRowState.none,
        PrRowState.pendingPredictedPr,
      ]);
    });

    test('case 4 — all-completed sets, no PRs yields all completedNonPr', () {
      // Standing 100x10 = 100kg / 10 reps / 1000 volume. Completed sets
      // 80x8, 80x8, 80x8 — none break any record.
      final sets = [
        _set(id: 's1', setNumber: 1, weight: 80, reps: 8),
        _set(id: 's2', setNumber: 2, weight: 80, reps: 8),
        _set(id: 's3', setNumber: 3, weight: 80, reps: 8),
      ];
      final existing = [
        _record(type: RecordType.maxWeight, value: 100, reps: 10),
        _record(type: RecordType.maxReps, value: 10),
        _record(type: RecordType.maxVolume, value: 1000),
      ];

      final result = resolveRowStates(
        sets: sets,
        existingRecords: existing,
        equipmentType: EquipmentType.barbell,
      );

      expect(result, [
        PrRowState.completedNonPr,
        PrRowState.completedNonPr,
        PrRowState.completedNonPr,
      ]);
    });

    test('case 5 — all-completed, single PR yields completedStandingPr for '
        'that one and completedNonPr for the rest', () {
      // Standing 60x8 = 60 / 8 / 480. Set 1 = 80x8 (beats weight 80>60 AND
      // volume 640>480). Sets 2 and 3 = 50x8 (no PR).
      final sets = [
        _set(id: 's1', setNumber: 1, weight: 80, reps: 8),
        _set(id: 's2', setNumber: 2, weight: 50, reps: 8),
        _set(id: 's3', setNumber: 3, weight: 50, reps: 8),
      ];
      final existing = [
        _record(type: RecordType.maxWeight, value: 60, reps: 8),
        _record(type: RecordType.maxReps, value: 8),
        _record(type: RecordType.maxVolume, value: 480),
      ];

      final result = resolveRowStates(
        sets: sets,
        existingRecords: existing,
        equipmentType: EquipmentType.barbell,
      );

      expect(result, [
        PrRowState.completedStandingPr,
        PrRowState.completedNonPr,
        PrRowState.completedNonPr,
      ]);
    });

    test('case 6 — bench-press supersession scenario from PLAN.md (the locked '
        'multi-PR example): prior 60x8; sets 65x8, 70x6, 75x5, 60x5', () {
      // Standing PRs: maxWeight 60 (8 reps), maxReps 8, maxVolume 480.
      //
      // Set 1: 65x8 -> weight 65>60 PR, reps 8=8 NO, volume 520>480 PR.
      //   Broken: {maxWeight, maxVolume}. Tentatively standing.
      // Set 2: 70x6 -> weight 70>65 PR, reps 6<8 NO, volume 420<520 NO.
      //   Broken: {maxWeight}. Tentatively standing. Bumps maxWeight bar to 70.
      // Set 3: 75x5 -> weight 75>70 PR, reps 5<8 NO, volume 375<520 NO.
      //   Broken: {maxWeight}. Tentatively standing. Bumps maxWeight to 75.
      // Set 4: 60x5 -> weight 60=60 (existing) NO; but bar is now 75 so NO,
      //   reps 5<8 NO, volume 300<520 NO. completedNonPr.
      //
      // Second pass:
      //   Set 1 broke {maxWeight=65, maxVolume=520}. Later sets:
      //     - maxWeight: set 2 has 70>65 -> superseded for maxWeight.
      //     - maxVolume: set 2's volume 420 < 520, set 3's 375 < 520, set 4's
      //       300 < 520. NOT superseded for maxVolume.
      //   anyStillStanding = true (maxVolume) -> set 1 remains
      //   completedStandingPr.
      //
      //   Set 2 broke {maxWeight=70}. Later: set 3 has 75>70 -> superseded.
      //   anyStillStanding = false -> completedSupersededPr.
      //
      //   Set 3 broke {maxWeight=75}. No later beats it -> standing.
      //
      // Expected:
      //   set 1 = completedStandingPr (maxVolume still standing)
      //   set 2 = completedSupersededPr
      //   set 3 = completedStandingPr
      //   set 4 = completedNonPr
      //
      // NOTE: The PLAN.md example said "set 1 superseded" but that
      // assumed a single-axis (heaviest-weight) view. The locked binary
      // rule explicitly says: "if ANY type still stands, the row stays
      // standing." Set 1's volume was never beaten by sets 2-4 (they all
      // dropped reps), so it correctly stays standing under the binary
      // rule. This is the correct behavior — the test encodes the rule
      // as locked, not the simplified narrative example.
      final sets = [
        _set(id: 's1', setNumber: 1, weight: 65, reps: 8),
        _set(id: 's2', setNumber: 2, weight: 70, reps: 6),
        _set(id: 's3', setNumber: 3, weight: 75, reps: 5),
        _set(id: 's4', setNumber: 4, weight: 60, reps: 5),
      ];
      final existing = [
        _record(type: RecordType.maxWeight, value: 60, reps: 8),
        _record(type: RecordType.maxReps, value: 8),
        _record(type: RecordType.maxVolume, value: 480),
      ];

      final result = resolveRowStates(
        sets: sets,
        existingRecords: existing,
        equipmentType: EquipmentType.barbell,
      );

      expect(result, [
        PrRowState.completedStandingPr,
        PrRowState.completedSupersededPr,
        PrRowState.completedStandingPr,
        PrRowState.completedNonPr,
      ]);
    });

    test('case 6b — single-axis supersession: when only weight is the broken '
        'type and a later set beats it, earlier sets correctly drop to '
        'superseded', () {
      // Same shape as case 6, but volume PR is tuned so sets 1-3 break ONLY
      // weight (volume already exceeds them). This isolates the
      // single-axis supersession path.
      //
      // Existing: maxWeight 60, maxReps 8, maxVolume 600 (high enough that
      // set 1's 520 < 600 = no volume PR).
      //
      // Set 1 65x8 -> {maxWeight=65}; set 2 70x6 -> {maxWeight=70};
      // set 3 75x5 -> {maxWeight=75}; set 4 60x5 -> {}.
      //
      // Second pass:
      //   Set 1: maxWeight=65 superseded by set 2's 70. anyStanding=false
      //     -> completedSupersededPr.
      //   Set 2: maxWeight=70 superseded by set 3's 75 -> superseded.
      //   Set 3: maxWeight=75 not beaten -> standing.
      //   Set 4: not a PR -> completedNonPr.
      final sets = [
        _set(id: 's1', setNumber: 1, weight: 65, reps: 8),
        _set(id: 's2', setNumber: 2, weight: 70, reps: 6),
        _set(id: 's3', setNumber: 3, weight: 75, reps: 5),
        _set(id: 's4', setNumber: 4, weight: 60, reps: 5),
      ];
      final existing = [
        _record(type: RecordType.maxWeight, value: 60, reps: 8),
        _record(type: RecordType.maxReps, value: 8),
        _record(type: RecordType.maxVolume, value: 600),
      ];

      final result = resolveRowStates(
        sets: sets,
        existingRecords: existing,
        equipmentType: EquipmentType.barbell,
      );

      expect(result, [
        PrRowState.completedSupersededPr,
        PrRowState.completedSupersededPr,
        PrRowState.completedStandingPr,
        PrRowState.completedNonPr,
      ]);
    });

    test('case 7 — mixed pending + completed: completed PR followed by '
        'pending values that would beat it', () {
      // Standing 60x5. Set 1 = 80x5 completed (PR). Set 2 pending at 90x5
      // (would beat the 80 bar set by set 1) -> pendingPredictedPr.
      final sets = [
        _set(id: 's1', setNumber: 1, weight: 80, reps: 5),
        _set(id: 's2', setNumber: 2, weight: 90, reps: 5, isCompleted: false),
      ];
      final existing = [
        _record(type: RecordType.maxWeight, value: 60, reps: 5),
        _record(type: RecordType.maxReps, value: 5),
        _record(type: RecordType.maxVolume, value: 300),
      ];

      final result = resolveRowStates(
        sets: sets,
        existingRecords: existing,
        equipmentType: EquipmentType.barbell,
      );

      expect(result, [
        PrRowState.completedStandingPr,
        PrRowState.pendingPredictedPr,
      ]);
    });

    test('case 8 — multi-recordType: heaviest-weight standing but max-reps '
        'superseded -> still completedStandingPr (binary rule)', () {
      // Standing maxWeight 60, maxReps 5, maxVolume 300.
      // Set 1: 100x10 -> breaks ALL three (weight 100>60, reps 10>5,
      //   volume 1000>300). {maxWeight, maxReps, maxVolume}.
      // Set 2: 50x20 -> weight 50<100 NO, reps 20>10 PR, volume 1000=1000 NO.
      //   {maxReps}. Bumps maxReps bar to 20.
      //
      // Second pass:
      //   Set 1: broken {maxWeight=100, maxReps=10, maxVolume=1000}.
      //     - maxWeight 100: set 2's 50 < 100, not superseded -> standing.
      //     - maxReps 10: set 2's 20 > 10, superseded.
      //     - maxVolume 1000: set 2's 1000 = 1000 (NOT strictly greater),
      //       not superseded -> standing.
      //   anyStillStanding = true -> completedStandingPr.
      //
      //   Set 2: broken {maxReps=20}. No later set -> standing.
      //
      // Expected: both completedStandingPr.
      final sets = [
        _set(id: 's1', setNumber: 1, weight: 100, reps: 10),
        _set(id: 's2', setNumber: 2, weight: 50, reps: 20),
      ];
      final existing = [
        _record(type: RecordType.maxWeight, value: 60, reps: 5),
        _record(type: RecordType.maxReps, value: 5),
        _record(type: RecordType.maxVolume, value: 300),
      ];

      final result = resolveRowStates(
        sets: sets,
        existingRecords: existing,
        equipmentType: EquipmentType.barbell,
      );

      expect(result, [
        PrRowState.completedStandingPr,
        PrRowState.completedStandingPr,
      ]);
    });

    test('case 9 — empty sets list returns empty result list', () {
      final result = resolveRowStates(
        sets: const <ExerciseSet>[],
        existingRecords: const <PersonalRecord>[],
        equipmentType: EquipmentType.barbell,
      );

      expect(result, isEmpty);
    });

    test(
      'case 10 — empty existingRecords (first-ever workout for the exercise) '
      'makes the first completed working set with positive load the '
      'standing PR',
      () {
        // Brand-new exercise: no historical records. First set 80x5 wins all
        // three record types. Sets 2 and 3 (60x5) lose to set 1's bars.
        final sets = [
          _set(id: 's1', setNumber: 1, weight: 80, reps: 5),
          _set(id: 's2', setNumber: 2, weight: 60, reps: 5),
          _set(id: 's3', setNumber: 3, weight: 60, reps: 5),
        ];

        final result = resolveRowStates(
          sets: sets,
          existingRecords: const <PersonalRecord>[],
          equipmentType: EquipmentType.barbell,
        );

        expect(result, [
          PrRowState.completedStandingPr,
          PrRowState.completedNonPr,
          PrRowState.completedNonPr,
        ]);
      },
    );

    // --- Bonus coverage for design corners explicitly called out in PLAN.md
    // and the PrRowState dartdoc. These aren't in the 10 cases the brief
    // mandated but encode the locked rules so future changes don't drift. ---

    test('warmup and dropset sets never carry a PR state', () {
      // A 200x1 warmup must not block a 100x5 working set's predicted PR,
      // and the warmup row itself stays none/completedNonPr.
      final sets = [
        _set(
          id: 'w1',
          setNumber: 1,
          weight: 200,
          reps: 1,
          setType: SetType.warmup,
        ),
        _set(id: 's1', setNumber: 2, weight: 100, reps: 5, isCompleted: false),
      ];
      // Empty records: a 100x5 working set IS a first-ever PR.
      final result = resolveRowStates(
        sets: sets,
        existingRecords: const <PersonalRecord>[],
        equipmentType: EquipmentType.barbell,
      );

      expect(result, [
        // Completed warmup -> non-PR (PR-ineligible by setType).
        PrRowState.completedNonPr,
        // Working set unaffected by the warmup -> predicted PR.
        PrRowState.pendingPredictedPr,
      ]);
    });

    test('bodyweight-only exercise tracks only maxReps; weight is ignored', () {
      // No historical records. Bodyweight pull-ups: set 1 = 0kg x 10
      // (maxReps PR = 10), set 2 = 0kg x 8 (no PR), set 3 = 0kg x 12 (PR,
      // supersedes set 1).
      final sets = [
        _set(id: 's1', setNumber: 1, weight: 0, reps: 10),
        _set(id: 's2', setNumber: 2, weight: 0, reps: 8),
        _set(id: 's3', setNumber: 3, weight: 0, reps: 12),
      ];

      final result = resolveRowStates(
        sets: sets,
        existingRecords: const <PersonalRecord>[],
        equipmentType: EquipmentType.bodyweight,
      );

      expect(result, [
        // Set 1 broke maxReps=10. Set 3's 12 > 10 -> superseded.
        // Bodyweight-only mode tracks ONLY maxReps, so once it's gone, no
        // other axis can keep set 1 standing.
        PrRowState.completedSupersededPr,
        PrRowState.completedNonPr,
        PrRowState.completedStandingPr,
      ]);
    });

    test('completed working set with zero reps is treated as completedNonPr '
        'and excluded from comparisons (zero-rep is noise)', () {
      // Standing 60x5. Set 1 = 100x0 (zero reps — completedNonPr, must
      // not bump the bar). Set 2 = 70x5 (real PR).
      final sets = [
        _set(id: 's1', setNumber: 1, weight: 100, reps: 0),
        _set(id: 's2', setNumber: 2, weight: 70, reps: 5),
      ];
      final existing = [
        _record(type: RecordType.maxWeight, value: 60, reps: 5),
        _record(type: RecordType.maxReps, value: 5),
        _record(type: RecordType.maxVolume, value: 300),
      ];

      final result = resolveRowStates(
        sets: sets,
        existingRecords: existing,
        equipmentType: EquipmentType.barbell,
      );

      expect(result, [
        PrRowState.completedNonPr,
        PrRowState.completedStandingPr,
      ]);
    });

    test('pending set with zero or null values yields none', () {
      // A pending row with empty inputs (user hasn't typed anything yet)
      // must stay none — no PR projection from blank values.
      final sets = [
        _set(id: 's1', setNumber: 1, isCompleted: false),
        _set(id: 's2', setNumber: 2, weight: 0, reps: 0, isCompleted: false),
      ];

      final result = resolveRowStates(
        sets: sets,
        existingRecords: const <PersonalRecord>[],
        equipmentType: EquipmentType.barbell,
      );

      expect(result, [PrRowState.none, PrRowState.none]);
    });
  });

  group('resolveRowDisplays', () {
    // [resolveRowDisplays] returns the same per-row state classification as
    // [resolveRowStates] PLUS a per-row [Set] of [RecordType]s that drive the
    // SetRow widget's per-cell value accent (gold for predicted/standing,
    // cream-700 for superseded). These tests pin the [accentTypes] semantic
    // so commit 4's SetRow widget can rely on it without re-deriving the set
    // from raw set data.
    test(
      'predicted-PR row exposes the projected broken types as accentTypes',
      () {
        // Standing 60kg / 8reps / 480 volume. Pending 65x5 beats only the
        // weight axis (65>60); 5 reps and 325 volume both stay below.
        final sets = [
          _set(id: 's1', setNumber: 1, weight: 65, reps: 5, isCompleted: false),
        ];
        final existing = [
          _record(type: RecordType.maxWeight, value: 60, reps: 8),
          _record(type: RecordType.maxReps, value: 8),
          _record(type: RecordType.maxVolume, value: 480),
        ];

        final result = resolveRowDisplays(
          sets: sets,
          existingRecords: existing,
          equipmentType: EquipmentType.barbell,
        );

        expect(result, hasLength(1));
        final d = result.single;
        expect(d.state, PrRowState.pendingPredictedPr);
        expect(d.accentTypes, {RecordType.maxWeight});
        expect(d.isWeightAccented, isTrue);
        expect(d.isRepsAccented, isFalse);
      },
    );

    test('standing-PR row with partial supersession narrows accentTypes to '
        'still-standing types only', () {
      // Standing 60kg / 8reps / 480 volume, then row 1 = 65x9 (breaks all
      // three: weight 65>60, reps 9>8, volume 585>480), then row 2 = 65x10
      // (no new weight PR — 65 not > 65 — but reps 10>9 supersedes the
      // reps and 650>585 supersedes the volume). Row 1 keeps its weight
      // PR, the others were superseded.
      final sets = [
        _set(id: 's1', setNumber: 1, weight: 65, reps: 9),
        _set(id: 's2', setNumber: 2, weight: 65, reps: 10),
      ];
      final existing = [
        _record(type: RecordType.maxWeight, value: 60, reps: 8),
        _record(type: RecordType.maxReps, value: 8),
        _record(type: RecordType.maxVolume, value: 480),
      ];

      final result = resolveRowDisplays(
        sets: sets,
        existingRecords: existing,
        equipmentType: EquipmentType.barbell,
      );

      expect(result, hasLength(2));
      // Row 1 stays standing — weight is still the best at 65kg.
      expect(result[0].state, PrRowState.completedStandingPr);
      expect(
        result[0].accentTypes,
        {RecordType.maxWeight},
        reason:
            'still-standing types only — reps + volume were superseded by '
            'the later 65x10 set, only the 65kg weight remains the best.',
      );
      // Row 2 is completedStandingPr with reps + volume as accent (it
      // didn't break weight — 65 not > 65 — only reps and volume).
      expect(result[1].state, PrRowState.completedStandingPr);
      expect(result[1].accentTypes, {RecordType.maxReps, RecordType.maxVolume});
    });

    test(
      'superseded-PR row keeps the FULL original broken set as accentTypes '
      '(cream-700 visualizes "you got there, but a later set went further")',
      () {
        // Row 1 breaks weight (50>40); row 2 supersedes weight (60>50). Row 1
        // becomes superseded with weight in its accent set so the SetRow's
        // weight cell renders cream-700, not dim/grey.
        final sets = [
          _set(id: 's1', setNumber: 1, weight: 50, reps: 5),
          _set(id: 's2', setNumber: 2, weight: 60, reps: 5),
        ];
        final existing = [
          _record(type: RecordType.maxWeight, value: 40, reps: 5),
          _record(type: RecordType.maxReps, value: 5),
          _record(type: RecordType.maxVolume, value: 200),
        ];

        final result = resolveRowDisplays(
          sets: sets,
          existingRecords: existing,
          equipmentType: EquipmentType.barbell,
        );

        expect(result[0].state, PrRowState.completedSupersededPr);
        // Row 1 originally broke weight (50>40) AND volume (250>200); both
        // were superseded by row 2 (60kg + 300 volume), so both stay in the
        // accent set for the cream-700 visual.
        expect(result[0].accentTypes, {
          RecordType.maxWeight,
          RecordType.maxVolume,
        });
        expect(result[1].state, PrRowState.completedStandingPr);
      },
    );

    test('plain rows (none and completedNonPr) carry empty accentTypes', () {
      final sets = [
        _set(id: 's1', setNumber: 1, weight: 30, reps: 3, isCompleted: false),
        _set(id: 's2', setNumber: 2, weight: 30, reps: 3),
      ];
      final existing = [
        _record(type: RecordType.maxWeight, value: 100, reps: 10),
        _record(type: RecordType.maxReps, value: 10),
        _record(type: RecordType.maxVolume, value: 1000),
      ];

      final result = resolveRowDisplays(
        sets: sets,
        existingRecords: existing,
        equipmentType: EquipmentType.barbell,
      );

      expect(result[0].state, PrRowState.none);
      expect(result[0].accentTypes, isEmpty);
      expect(result[1].state, PrRowState.completedNonPr);
      expect(result[1].accentTypes, isEmpty);
    });

    test(
      'maxVolume-only PR accents BOTH weight and reps cells (compound rule)',
      () {
        // No weight PR (50 = standing 50), no reps PR (5 = standing 5), but
        // a NEW volume PR is impossible if both inputs match. Force a volume
        // PR via an existing record that's lower than the row's volume but
        // weight + reps individually match the standing best for those types.
        // Concretely: standing 50kg / 5 reps / 200 volume. A new set 50x5 =
        // 250 volume beats volume but ties weight + reps.
        final sets = [_set(id: 's1', setNumber: 1, weight: 50, reps: 5)];
        final existing = [
          _record(type: RecordType.maxWeight, value: 50, reps: 5),
          _record(type: RecordType.maxReps, value: 5),
          _record(type: RecordType.maxVolume, value: 200),
        ];

        final result = resolveRowDisplays(
          sets: sets,
          existingRecords: existing,
          equipmentType: EquipmentType.barbell,
        );

        expect(result.single.state, PrRowState.completedStandingPr);
        expect(result.single.accentTypes, {RecordType.maxVolume});
        // Volume folds into BOTH per-cell accents — this is the compound
        // rule that lets a volume-only PR still light up the row visually.
        expect(result.single.isWeightAccented, isTrue);
        expect(result.single.isRepsAccented, isTrue);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Commit 6: Supersession transition tests
  //
  // These tests pin the STATE TRANSITIONS explicitly — the before/after pairs
  // that verify the resolver correctly updates classification as the set list
  // grows mid-workout. They complement the commit-3 static-state tests above.
  // ---------------------------------------------------------------------------

  group('supersession transitions (commit 6)', () {
    test(
      'transition: standing → superseded when a later set beats the PR type',
      () {
        // Phase 1: single completed set 70x5 with existing 60x5. Set 1 is the
        // standing PR for maxWeight (70>60).
        final existing = [
          _record(type: RecordType.maxWeight, value: 60, reps: 5),
          _record(type: RecordType.maxReps, value: 5),
          _record(type: RecordType.maxVolume, value: 300),
        ];
        final phase1Sets = [_set(id: 's1', setNumber: 1, weight: 70, reps: 5)];

        final phase1 = resolveRowStates(
          sets: phase1Sets,
          existingRecords: existing,
          equipmentType: EquipmentType.barbell,
        );
        expect(phase1, [
          PrRowState.completedStandingPr,
        ], reason: 'before: 70x5 with historical 60x5 → standing');

        // Phase 2: add set 2 (80x5) that strictly beats set 1's maxWeight.
        // Set 1 must now drop to superseded.
        final phase2Sets = [
          _set(id: 's1', setNumber: 1, weight: 70, reps: 5),
          _set(id: 's2', setNumber: 2, weight: 80, reps: 5),
        ];

        final phase2 = resolveRowStates(
          sets: phase2Sets,
          existingRecords: existing,
          equipmentType: EquipmentType.barbell,
        );
        expect(
          phase2[0],
          PrRowState.completedSupersededPr,
          reason: 'after: set 1 demoted — 80x5 superseded 70x5 for maxWeight',
        );
        expect(
          phase2[1],
          PrRowState.completedStandingPr,
          reason: 'set 2 is now the standing PR for maxWeight',
        );
      },
    );

    test('transition: pendingPredictedPr → completedStandingPr when the set is '
        'completed at the same weight/reps that triggered the prediction', () {
      // Historical 60x5. Pending set 70x5 is predicted-PR.
      final existing = [
        _record(type: RecordType.maxWeight, value: 60, reps: 5),
        _record(type: RecordType.maxReps, value: 5),
        _record(type: RecordType.maxVolume, value: 300),
      ];
      final pendingSets = [
        _set(id: 's1', setNumber: 1, weight: 70, reps: 5, isCompleted: false),
      ];

      final pendingResult = resolveRowStates(
        sets: pendingSets,
        existingRecords: existing,
        equipmentType: EquipmentType.barbell,
      );
      expect(
        pendingResult,
        [PrRowState.pendingPredictedPr],
        reason: 'before completion: 70>60 historical → predicted PR',
      );

      // Mark the set complete at the same values.
      final completedSets = [
        _set(id: 's1', setNumber: 1, weight: 70, reps: 5, isCompleted: true),
      ];

      final completedResult = resolveRowStates(
        sets: completedSets,
        existingRecords: existing,
        equipmentType: EquipmentType.barbell,
      );
      expect(completedResult, [
        PrRowState.completedStandingPr,
      ], reason: 'after completion: committed 70x5 → standing PR');
    });

    test('transition: pendingPredictedPr → none when the user reduces weight '
        'below the PR threshold before completing', () {
      // Historical 60x5. Pending 70x5 is predicted-PR.
      final existing = [
        _record(type: RecordType.maxWeight, value: 60, reps: 5),
        _record(type: RecordType.maxReps, value: 5),
        _record(type: RecordType.maxVolume, value: 300),
      ];
      final predictedSets = [
        _set(id: 's1', setNumber: 1, weight: 70, reps: 5, isCompleted: false),
      ];

      final predicted = resolveRowStates(
        sets: predictedSets,
        existingRecords: existing,
        equipmentType: EquipmentType.barbell,
      );
      expect(predicted, [
        PrRowState.pendingPredictedPr,
      ], reason: 'before reduction: 70>60 → predicted PR');

      // User reduces weight to 55 — below historical 60.
      final reducedSets = [
        _set(id: 's1', setNumber: 1, weight: 55, reps: 5, isCompleted: false),
      ];

      final reduced = resolveRowStates(
        sets: reducedSets,
        existingRecords: existing,
        equipmentType: EquipmentType.barbell,
      );
      expect(reduced, [
        PrRowState.none,
      ], reason: 'after reduction to 55<60: prediction revoked → none');
    });

    test('transition: pendingPredictedPr → completedNonPr when user reduces '
        'weight then completes — no PR committed', () {
      // Historical 60x5. Pending row that was previously predicted-PR (70x5)
      // is now reduced to 55x5 and then completed. The committed value does
      // not beat the record.
      final existing = [
        _record(type: RecordType.maxWeight, value: 60, reps: 5),
        _record(type: RecordType.maxReps, value: 5),
        _record(type: RecordType.maxVolume, value: 300),
      ];
      final completedBelowPr = [
        _set(id: 's1', setNumber: 1, weight: 55, reps: 5, isCompleted: true),
      ];

      final result = resolveRowStates(
        sets: completedBelowPr,
        existingRecords: existing,
        equipmentType: EquipmentType.barbell,
      );
      expect(result, [
        PrRowState.completedNonPr,
      ], reason: 'completed at 55x5 < historical 60x5 → completedNonPr');
    });

    test('bench-press cascade (binary rule) from PLAN.md: prior 60x8; '
        'sets 65x8, 70x6, 75x5, then a 5th set that supersedes set 3', () {
      // This is the canonical Phase 20 cascade scenario, extended by one
      // more set to verify that set 3 transitions from standing to superseded
      // when a 5th set (80x5) beats its maxWeight.
      //
      // After sets 1–4 (mirrors commit-3 case 6):
      //   set 1 = completedStandingPr (volume 520 still unbeaten)
      //   set 2 = completedSupersededPr (weight 70 beaten by 75)
      //   set 3 = completedStandingPr  (weight 75 still best)
      //   set 4 = completedNonPr
      //
      // After adding set 5 (80x5):
      //   set 3 → completedSupersededPr (weight 75 beaten by 80)
      //   set 5 → completedStandingPr   (weight 80 is new best)
      //   set 1 still standing (volume 520 > all later volumes)
      final existing = [
        _record(type: RecordType.maxWeight, value: 60, reps: 8),
        _record(type: RecordType.maxReps, value: 8),
        _record(type: RecordType.maxVolume, value: 480),
      ];

      // Before set 5 — confirm base state matches case 6.
      final fourSets = [
        _set(id: 's1', setNumber: 1, weight: 65, reps: 8),
        _set(id: 's2', setNumber: 2, weight: 70, reps: 6),
        _set(id: 's3', setNumber: 3, weight: 75, reps: 5),
        _set(id: 's4', setNumber: 4, weight: 60, reps: 5),
      ];

      final fourResult = resolveRowStates(
        sets: fourSets,
        existingRecords: existing,
        equipmentType: EquipmentType.barbell,
      );
      expect(fourResult, [
        PrRowState.completedStandingPr,
        PrRowState.completedSupersededPr,
        PrRowState.completedStandingPr,
        PrRowState.completedNonPr,
      ], reason: 'four-set baseline must match commit-3 case 6 result');

      // Add set 5 (80x5): supersedes set 3's maxWeight (75→80).
      final fiveSets = [
        _set(id: 's1', setNumber: 1, weight: 65, reps: 8),
        _set(id: 's2', setNumber: 2, weight: 70, reps: 6),
        _set(id: 's3', setNumber: 3, weight: 75, reps: 5),
        _set(id: 's4', setNumber: 4, weight: 60, reps: 5),
        _set(id: 's5', setNumber: 5, weight: 80, reps: 5),
      ];

      final fiveResult = resolveRowStates(
        sets: fiveSets,
        existingRecords: existing,
        equipmentType: EquipmentType.barbell,
      );
      // Set 1: volume 520 = 65×8 still unbeaten (set 5 = 80×5 = 400 < 520).
      expect(
        fiveResult[0],
        PrRowState.completedStandingPr,
        reason: 'set 1 still standing — maxVolume 520 not beaten by set 5',
      );
      expect(
        fiveResult[1],
        PrRowState.completedSupersededPr,
        reason: 'set 2 still superseded (70 beaten by 75 and now 80)',
      );
      // Set 3 transitioned from standing to superseded: 75 beaten by 80.
      expect(
        fiveResult[2],
        PrRowState.completedSupersededPr,
        reason:
            'set 3 TRANSITION: standing→superseded when set 5 (80) beats 75',
      );
      expect(
        fiveResult[3],
        PrRowState.completedNonPr,
        reason: 'set 4 still non-PR',
      );
      expect(
        fiveResult[4],
        PrRowState.completedStandingPr,
        reason: 'set 5 is the new standing PR for maxWeight (80)',
      );
    });

    test(
      'case_single_axis_cascade_matches_plan_narrative: when volume PR is '
      'out of reach, cascade correctly supersedes weight-axis sets in order',
      () {
        // Seed with a high pre-existing maxVolume (700) so none of the
        // in-workout sets can beat volume — the cascade is purely weight-axis.
        // This is the intuitive "Plan.md narrative" scenario.
        //
        // Existing: maxWeight 60, maxReps 8, maxVolume 700 (high baseline).
        //
        // Set 1: 65x8 → weight 65>60 PR. Volume 520<700 → no volume PR.
        //   {maxWeight=65}. Standing.
        // Set 2: 70x6 → weight 70>65 PR. Volume 420<700 → no volume PR.
        //   {maxWeight=70}. Standing. Supersedes set 1.
        // Set 3: 75x5 → weight 75>70 PR. Volume 375<700 → no volume PR.
        //   {maxWeight=75}. Standing. Supersedes set 2.
        //
        // Second pass:
        //   Set 1: maxWeight 65 → set 2's 70>65 → superseded.
        //   Set 2: maxWeight 70 → set 3's 75>70 → superseded.
        //   Set 3: maxWeight 75 → nothing beats it → standing.
        final existing = [
          _record(type: RecordType.maxWeight, value: 60, reps: 8),
          _record(type: RecordType.maxReps, value: 8),
          _record(type: RecordType.maxVolume, value: 700),
        ];
        final sets = [
          _set(id: 's1', setNumber: 1, weight: 65, reps: 8),
          _set(id: 's2', setNumber: 2, weight: 70, reps: 6),
          _set(id: 's3', setNumber: 3, weight: 75, reps: 5),
        ];

        final result = resolveRowStates(
          sets: sets,
          existingRecords: existing,
          equipmentType: EquipmentType.barbell,
        );

        expect(
          result,
          [
            PrRowState.completedSupersededPr,
            PrRowState.completedSupersededPr,
            PrRowState.completedStandingPr,
          ],
          reason:
              'single-axis cascade: sets 1 and 2 superseded in order, set 3 '
              'stands — matches the intuitive PLAN.md narrative',
        );
      },
    );

    test('pre-fill / partial completion: pending set with weight=0 yields none '
        '(no PR projection from incomplete weighted data)', () {
      // User added a row but hasn't filled in weight yet. Weight=0 with
      // any reps must not project a PR — zero-weight rows are noise.
      final existing = [
        _record(type: RecordType.maxWeight, value: 60, reps: 5),
        _record(type: RecordType.maxReps, value: 5),
        _record(type: RecordType.maxVolume, value: 300),
      ];
      final sets = [
        _set(id: 's1', setNumber: 1, weight: 0, reps: 5, isCompleted: false),
      ];

      final result = resolveRowStates(
        sets: sets,
        existingRecords: existing,
        equipmentType: EquipmentType.barbell,
      );

      expect(
        result,
        [PrRowState.none],
        reason:
            'pending set with weight=0 on a weighted exercise must not '
            'project a PR — zero weight is incomplete data, not a new '
            'record',
      );
    });

    test('pre-fill / partial completion: pending set with reps=0 yields none '
        'regardless of weight value', () {
      // User filled in weight but not reps. Reps=0 must never project a PR.
      final existing = [
        _record(type: RecordType.maxWeight, value: 60, reps: 5),
        _record(type: RecordType.maxReps, value: 5),
        _record(type: RecordType.maxVolume, value: 300),
      ];
      final sets = [
        // weight=100 > 60, but reps=0 → no projection.
        _set(id: 's1', setNumber: 1, weight: 100, reps: 0, isCompleted: false),
      ];

      final result = resolveRowStates(
        sets: sets,
        existingRecords: existing,
        equipmentType: EquipmentType.barbell,
      );

      expect(
        result,
        [PrRowState.none],
        reason:
            'pending set with reps=0 must not project a PR — reps=0 is '
            'incomplete data',
      );
    });

    test('bodyweight equipment with at least one weighted set flips '
        'isBodyweightOnly to false and tracks all three record types '
        '(weighted pull-ups / dip-belt scenario)', () {
      // The resolver's isBodyweightOnly check requires that EVERY completed
      // working set on a bodyweight exercise carry weight ≤ 0. As soon as
      // ONE completed set has weight > 0 (e.g. a dip belt or weighted-vest
      // pull-up), the mode flips to weighted and all three record types
      // (maxWeight, maxReps, maxVolume) become trackable for every set —
      // including earlier zero-weight sets retroactively.
      //
      // Set 1: bodyweight × 8 reps (weight=0). With isBodyweightOnly=false,
      //   _typesBrokenByValues short-circuits on `weight <= 0` →
      //   completedNonPr. runningBest unchanged.
      // Set 2: bodyweight + 5kg × 6 reps. weight=5>0 / reps=6>0 / vol=30>0
      //   beat all three running bests (still 0/0/0). Tentatively
      //   completedStandingPr with all three. runningBest = {5, 6, 30}.
      // Set 3: bodyweight + 10kg × 5 reps. weight=10>5 (PR), reps=5 not > 6
      //   (no PR), volume=50>30 (PR). Broken {maxWeight, maxVolume}.
      //   Tentatively completedStandingPr with {maxWeight, maxVolume}.
      //
      // Pass 2:
      //   Set 2: broke {maxWeight=5, maxReps=6, maxVolume=30}.
      //     - maxWeight: set 3's 10>5 → superseded.
      //     - maxReps: set 3's 5 not > 6 → still standing.
      //     - maxVolume: set 3's 50>30 → superseded.
      //   stillStanding = {maxReps}, partial supersession → keep
      //   completedStandingPr but narrow accent to {maxReps} only.
      //   Set 3: broke {maxWeight=10, maxVolume=50}. No later set → both
      //   still standing → already completedStandingPr with full broken set
      //   from pass 1.
      //
      // Expected:
      //   set 1 = completedNonPr (zero weight on a now-weighted exercise)
      //   set 2 = completedStandingPr, accent {maxReps}
      //   set 3 = completedStandingPr, accent {maxWeight, maxVolume}
      final sets = [
        _set(id: 's1', setNumber: 1, weight: 0, reps: 8),
        _set(id: 's2', setNumber: 2, weight: 5, reps: 6),
        _set(id: 's3', setNumber: 3, weight: 10, reps: 5),
      ];

      final result = resolveRowDisplays(
        sets: sets,
        existingRecords: const <PersonalRecord>[],
        equipmentType: EquipmentType.bodyweight,
      );

      expect(result, hasLength(3));
      expect(
        result[0].state,
        PrRowState.completedNonPr,
        reason:
            'set 1 (weight=0) on a now-weighted bodyweight exercise: '
            '_typesBrokenByValues short-circuits on weight≤0 because '
            'isBodyweightOnly=false (set 2 + set 3 carry positive weight)',
      );
      expect(
        result[0].accentTypes,
        isEmpty,
        reason: 'completedNonPr carries no accent',
      );

      expect(
        result[1].state,
        PrRowState.completedStandingPr,
        reason:
            'set 2 broke all three records initially; reps still standing '
            'after set 3 (5 not > 6) — binary rule keeps it standing',
      );
      expect(
        result[1].accentTypes,
        {RecordType.maxReps},
        reason:
            'partial supersession: maxWeight + maxVolume superseded by '
            'set 3, only maxReps remains standing → accent narrows to it',
      );

      expect(
        result[2].state,
        PrRowState.completedStandingPr,
        reason: 'set 3 holds maxWeight=10 and maxVolume=50; no later sets',
      );
      expect(
        result[2].accentTypes,
        {RecordType.maxWeight, RecordType.maxVolume},
        reason:
            'set 3 broke weight + volume, not reps (5<6); both still '
            'standing because no later sets exist',
      );
    });

    test('multi-exercise non-interference: resolver is called per exercise and '
        'each call is independent — exercise B records do not contaminate '
        'exercise A resolution', () {
      // Simulate two independent resolver calls (one per exercise) with
      // identical set values but different historical records. The sets
      // are structurally the same but the existing records differ so the
      // PR states differ — proving the resolver does not carry cross-exercise
      // state.
      //
      // Exercise A historical: maxWeight 60. Set 70x5 → standing PR.
      // Exercise B historical: maxWeight 80. Set 70x5 → completedNonPr.
      final sets = [_set(id: 's1', setNumber: 1, weight: 70, reps: 5)];

      final existingA = [
        _record(type: RecordType.maxWeight, value: 60, reps: 5),
        _record(type: RecordType.maxReps, value: 5),
        _record(type: RecordType.maxVolume, value: 300),
      ];
      final existingB = [
        _record(type: RecordType.maxWeight, value: 80, reps: 5),
        _record(type: RecordType.maxReps, value: 5),
        _record(type: RecordType.maxVolume, value: 400),
      ];

      final resultA = resolveRowStates(
        sets: sets,
        existingRecords: existingA,
        equipmentType: EquipmentType.barbell,
      );
      final resultB = resolveRowStates(
        sets: sets,
        existingRecords: existingB,
        equipmentType: EquipmentType.barbell,
      );

      expect(resultA, [
        PrRowState.completedStandingPr,
      ], reason: 'exercise A: 70>60 → standing PR');
      expect(
        resultB,
        [PrRowState.completedNonPr],
        reason: 'exercise B: 70<80 → completedNonPr (no cross-contamination)',
      );
    });
  });
}
