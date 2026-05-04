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
}
