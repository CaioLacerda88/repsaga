import '../../exercises/models/exercise.dart';
import '../../personal_records/models/personal_record.dart';
import '../../personal_records/models/record_type.dart';
import '../models/exercise_set.dart';
import '../models/set_type.dart';
import 'pr_row_state.dart';

/// Resolves per-set [PrRowState] for a single exercise within an active
/// workout (Phase 20).
///
/// **Pure function.** No I/O, no side-effects, no dependencies. The active
/// workout notifier passes in the current set list + the canonical
/// [PersonalRecord]s for the exercise; this function returns a list aligned
/// 1:1 with [sets] giving each row its display state.
///
/// **Why this lives in `workouts/domain` rather than extending
/// `PRDetectionService`.** `PRDetectionService` is record-scoped, write-side
/// logic — it produces the canonical [PersonalRecord] rows to upsert when a
/// workout finishes. This resolver is workout-scoped, read-side logic — it
/// classifies in-progress rows for display. Different lifecycles, different
/// shapes, different consumers. Composing them in one class would tangle two
/// concerns; keeping them separate honours the dependency direction
/// (`workouts` → `personal_records.models`, never the reverse).
///
/// **Standing-vs-superseded contract** (locked design 2026-05-04):
///
/// 1. For each PENDING set: project the row as if completed at its current
///    weight/reps. If the projection would produce a PR (per the same rules
///    canonical detection uses) when compared against the standing record
///    AND any earlier completed sets in this same workout — state is
///    [PrRowState.pendingPredictedPr]. Else [PrRowState.none].
///
/// 2. For each COMPLETED set: determine the set of record types it broke at
///    the moment of completion (same comparison rules as
///    `PRDetectionService` — strict-greater than the standing record and
///    strict-greater than every prior completed set this workout for that
///    record type). If the set broke none, state is
///    [PrRowState.completedNonPr].
///
/// 3. For each COMPLETED set that broke at least one record type: a record
///    type is "still standing" within the workout if no LATER completed set
///    in the same workout reached a strictly-greater value for that same
///    record type. The row is [PrRowState.completedStandingPr] if AT LEAST
///    ONE of its broken types is still standing; otherwise
///    [PrRowState.completedSupersededPr].
///
/// **Bodyweight rule.** Mirrors `PRDetectionService`: an exercise is treated
/// as bodyweight-only when [equipmentType] is [EquipmentType.bodyweight] AND
/// every completed working set carries a non-positive weight. Bodyweight-only
/// exercises check only [RecordType.maxReps]; weighted exercises check
/// [RecordType.maxWeight], [RecordType.maxReps], and [RecordType.maxVolume].
///
/// **Excluded sets.** Warmup, dropset, and failure sets carry different PR
/// semantics — they are not PR-eligible. They get [PrRowState.none] when
/// pending and [PrRowState.completedNonPr] when completed. They are also
/// excluded from comparisons against working sets (a 2-rep warmup at 200kg
/// must not block a working 100x5 from showing as a predicted PR).
///
/// **Empty inputs.** An empty [sets] list returns an empty list. An empty
/// [existingRecords] list (first-ever workout for the exercise) means the
/// first completed working set with positive load becomes the standing PR.
List<PrRowState> resolveRowStates({
  required List<ExerciseSet> sets,
  required List<PersonalRecord> existingRecords,
  required EquipmentType equipmentType,
}) {
  // Thin wrapper over [resolveRowDisplays] preserved as the canonical
  // signature for tests and callers that only need the chrome state. Both
  // walk the same logic; collapsing them avoids drift between the binary
  // state output and the richer per-row accent-type output.
  final displays = resolveRowDisplays(
    sets: sets,
    existingRecords: existingRecords,
    equipmentType: equipmentType,
  );
  return displays.map((d) => d.state).toList(growable: false);
}

/// Richer counterpart to [resolveRowStates] that ALSO returns, for each
/// accent-eligible row, the [RecordType] set the row should color (Phase 20
/// commit 4).
///
/// Same contract as [resolveRowStates] — pure function, idempotent, no I/O.
/// Returns a list aligned 1:1 with [sets].
///
/// **Why this exists separately from [resolveRowStates]:** the SetRow widget
/// needs to know not only the row's display state but also WHICH value(s) on
/// the row to color (gold for predicted/standing, cream for superseded). A
/// single set can simultaneously break heaviest-weight, max-reps and
/// max-volume; the widget composes the per-cell text color from the
/// [PrRowDisplay.accentTypes] set. Per-cell `[isWeightAccented]` /
/// `[isRepsAccented]` getters fold maxVolume into BOTH so a volume-only PR
/// is visible on the row.
List<PrRowDisplay> resolveRowDisplays({
  required List<ExerciseSet> sets,
  required List<PersonalRecord> existingRecords,
  required EquipmentType equipmentType,
}) {
  if (sets.isEmpty) return const <PrRowDisplay>[];

  // Determine bodyweight-only mode using the same rule as PRDetectionService:
  // bodyweight equipment AND every completed working set has non-positive
  // weight. We deliberately look only at completed working sets — pending
  // sets and non-working sets must not flip the mode.
  final completedWorkingSets = sets
      .where(
        (s) =>
            s.isCompleted && s.setType == SetType.working && (s.reps ?? 0) > 0,
      )
      .toList();
  final isBodyweightOnly =
      equipmentType == EquipmentType.bodyweight &&
      completedWorkingSets.every((s) => (s.weight ?? 0) <= 0);

  // Per record type, the running "best value to beat" — starts at the
  // standing historical record (if any) and rises only when an EARLIER
  // completed working set this workout exceeds it. Used both for
  // moment-of-completion candidacy AND for pending-set projection.
  final recordTypes = isBodyweightOnly
      ? const [RecordType.maxReps]
      : const [RecordType.maxWeight, RecordType.maxReps, RecordType.maxVolume];

  final runningBest = <RecordType, double>{
    for (final rt in recordTypes) rt: _existingRecordValue(existingRecords, rt),
  };

  // First pass: classify each row in order, recording for each completed PR
  // row WHICH record types it broke. Pending rows project against the
  // current `runningBest` snapshot (which reflects all earlier sets).
  final result = List<PrRowDisplay>.filled(
    sets.length,
    const PrRowDisplay.plain(PrRowState.none),
  );
  // Maps row index -> set of record types that row broke at completion.
  // Used in pass 2 to decide superseded vs standing AND to derive the
  // per-row accent set the SetRow widget colours.
  final brokenTypesByIndex = <int, Set<RecordType>>{};

  for (var i = 0; i < sets.length; i++) {
    final s = sets[i];

    // Non-working sets: never PR-eligible. completedNonPr if completed (with
    // positive reps), none if pending. They also don't update runningBest.
    if (s.setType != SetType.working) {
      result[i] = PrRowDisplay.plain(
        s.isCompleted ? PrRowState.completedNonPr : PrRowState.none,
      );
      continue;
    }

    if (!s.isCompleted) {
      // Pending: project against current runningBest snapshot. The same set
      // of would-break types becomes the row's accent set, so the widget
      // gold-ifies the value(s) the projection identifies.
      final wouldBreak = _typesBrokenByValues(
        weight: s.weight ?? 0,
        reps: s.reps ?? 0,
        runningBest: runningBest,
        isBodyweightOnly: isBodyweightOnly,
      );
      result[i] = wouldBreak.isEmpty
          ? const PrRowDisplay.plain(PrRowState.none)
          : PrRowDisplay(
              state: PrRowState.pendingPredictedPr,
              accentTypes: wouldBreak,
            );
      continue;
    }

    // Completed working set. Reps must be positive to be PR-eligible
    // (mirrors `isCompletedWorkingSet`); otherwise it counts as completedNonPr
    // and is excluded from comparisons (zero-rep is noise).
    final reps = s.reps ?? 0;
    if (reps <= 0) {
      result[i] = const PrRowDisplay.plain(PrRowState.completedNonPr);
      continue;
    }

    final brokenTypes = _typesBrokenByValues(
      weight: s.weight ?? 0,
      reps: reps,
      runningBest: runningBest,
      isBodyweightOnly: isBodyweightOnly,
    );

    if (brokenTypes.isEmpty) {
      result[i] = const PrRowDisplay.plain(PrRowState.completedNonPr);
    } else {
      // Tentatively mark as standing with the broken set as accent — pass 2
      // will demote to superseded (with the same broken set as cream-accent)
      // if every type was later beaten, OR shrink the accent set to only the
      // still-standing types if some were superseded but not all.
      result[i] = PrRowDisplay(
        state: PrRowState.completedStandingPr,
        accentTypes: brokenTypes,
      );
      brokenTypesByIndex[i] = brokenTypes;
      for (final rt in brokenTypes) {
        runningBest[rt] = _valueFor(rt, weight: s.weight ?? 0, reps: reps);
      }
    }
  }

  // Second pass: walk the broken rows again. For each broken record type,
  // determine whether ANY later completed working set beat the value. The
  // row's display is determined by:
  //   - If NO broken type is still standing → demote to
  //     [PrRowState.completedSupersededPr]; accent = the FULL original
  //     broken set (cream-700 on every value the row broke at completion).
  //   - If SOME broken types are still standing → keep
  //     [PrRowState.completedStandingPr]; accent = ONLY the still-standing
  //     types so the gold visually tracks "what's currently the best".
  for (final entry in brokenTypesByIndex.entries) {
    final i = entry.key;
    final brokenTypes = entry.value;
    final valuesAtBreak = <RecordType, double>{
      for (final rt in brokenTypes)
        rt: _valueFor(rt, weight: sets[i].weight ?? 0, reps: sets[i].reps ?? 0),
    };

    final stillStanding = <RecordType>{};
    for (final rt in brokenTypes) {
      final brokenValue = valuesAtBreak[rt]!;
      var supersededByLater = false;
      for (var j = i + 1; j < sets.length; j++) {
        final later = sets[j];
        if (!later.isCompleted) continue;
        if (later.setType != SetType.working) continue;
        final laterReps = later.reps ?? 0;
        if (laterReps <= 0) continue;
        final laterValue = _valueFor(
          rt,
          weight: later.weight ?? 0,
          reps: laterReps,
        );
        if (laterValue > brokenValue) {
          supersededByLater = true;
          break;
        }
      }
      if (!supersededByLater) stillStanding.add(rt);
    }

    if (stillStanding.isEmpty) {
      // All broken types were superseded. Demote to superseded, but keep the
      // ORIGINAL broken set as the accent — those are the values the row
      // surpassed at completion and the cream-700 visual marks them as
      // "you got there, but a later set went further".
      result[i] = PrRowDisplay(
        state: PrRowState.completedSupersededPr,
        accentTypes: brokenTypes,
      );
    } else if (stillStanding.length != brokenTypes.length) {
      // Partial supersession: some types still standing. Stay
      // [completedStandingPr] (the row currently holds at least one
      // standing record), but narrow the gold accent to ONLY the
      // still-standing types so the visual is honest about what's still
      // the best.
      result[i] = PrRowDisplay(
        state: PrRowState.completedStandingPr,
        accentTypes: stillStanding,
      );
    }
    // else: every broken type still standing — already correctly set in
    // pass 1 with the full broken set as accent.
  }

  return result;
}

/// Returns the standing historical value for [type] from [existingRecords],
/// or `0` when no record exists (first-ever for this exercise + type).
double _existingRecordValue(
  List<PersonalRecord> existingRecords,
  RecordType type,
) {
  for (final r in existingRecords) {
    if (r.recordType == type) return r.value;
  }
  return 0;
}

/// Per-record-type value for a given (weight, reps) pair.
double _valueFor(RecordType type, {required double weight, required int reps}) {
  switch (type) {
    case RecordType.maxWeight:
      return weight;
    case RecordType.maxReps:
      return reps.toDouble();
    case RecordType.maxVolume:
      return weight * reps;
  }
}

/// Returns the set of record types a (weight, reps) row would break given
/// the current [runningBest] snapshot. A type is "broken" iff the row's
/// value for that type is strictly greater than the running best AND the row
/// has positive contributing values (zero weight or zero reps cannot break a
/// weighted record; bodyweight-only mode skips the weight check).
Set<RecordType> _typesBrokenByValues({
  required double weight,
  required int reps,
  required Map<RecordType, double> runningBest,
  required bool isBodyweightOnly,
}) {
  if (reps <= 0) return const <RecordType>{};
  if (!isBodyweightOnly && weight <= 0) return const <RecordType>{};

  final broken = <RecordType>{};
  for (final entry in runningBest.entries) {
    final rt = entry.key;
    final candidate = _valueFor(rt, weight: weight, reps: reps);
    if (candidate <= 0) continue;
    if (candidate > entry.value) broken.add(rt);
  }
  return broken;
}
