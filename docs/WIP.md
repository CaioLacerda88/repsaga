# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Routine builder — usability pass v2 (ui-ux-critic review)

**Branch:** `feature/routine-builder-usability`
**Source:** User asks + ui-ux-critic analysis of `CreateRoutineScreen`. **No migration / no model change**
(all touched fields already exist).
**Pipeline:** mockups (bodyweight pill + reorder + weight) → user sign-off → tech-lead TDD → reviewer
→ QA (E2E selector audit — reorder selectors + dropped top-Save) → visual gate → ship.

### Scope (user-confirmed)
- [x] **#1 Bodyweight pills** (Important) — bodyweight pill currently REPLACES the muscle chip (info loss: a
      pull-up is a Back exercise). **User-approved: TWO pills side by side** — neutral grey `Bodyweight`
      (`_IdentityPill.bodyweight`) + a muscle pill (`_IdentityPill.strength(muscleGroup)`), no glyph. Bodyweight
      branch in `_buildStrengthBody`/`_header` renders both (Row, ~6dp gap) instead of the single neutral tag.
      No model change (muscleGroup ⊥ equipmentType, both on the Exercise).
- [x] **#2 Reorder mode** (Important) — PORT the active-workout pattern (AppBar `Icons.reorder ↔ Icons.done`
      toggle + per-card up/down arrows replacing × in `_header`), NOT `ReorderableListView` (lazy → would break
      the eager-render E2E fix; keep the `SingleChildScrollView`). `_ExerciseCard` gains `reorderMode`/`isFirst`/
      `isLast` + onMoveUp/Down; parent does an index swap. Order persists via JSONB array order — no migration.
      Reuse existing `reorderExercisesTooltip`/`exitReorderModeTooltip` l10n. Gate on `_exercises.length > 1`.
- [x] **#3a Undo on remove** (Important) — remove shows a "Removed — Undo" SnackBar (4s, capture entry+index,
      reinsert at original index). Cluster-aware: `persist: false` explicit + real `SnackBarAction`. New ARB keys.
- [x] **#3b "Targets optional" helper** — one muted line under the cardio target slots. 1 ARB key.
- [x] **#3e Drop redundant top Save** — remove AppBar Save; bottom CTA is sole. **E2E:** move the
      `create-routine-save` selector → `create-routine-save-cta` + re-run routines spec (flow change).
- [x] **#3c Duplicates: allow + soft hint** — adding an exercise already in the routine still adds it but shows a
      one-shot "already in this routine" SnackBar. New ARB key.
- [x] **#4 Per-exercise target weight + reps** (Important) — the builder never sets `targetReps`/`targetWeight`,
      so a started routine seeds from `prev-session ?? equipment-default` (the "nebulous" number). Add a **TARGET
      block** to the strength/bodyweight card body: reuse `WeightStepper` (keyboard-safe — exact entry is a modal
      dialog, so `resizeToAvoidBottomInset:false` is respected) for weight + the existing `−/+` idiom for reps.
      Per-exercise uniform (one target → all generated configs). `initState` must also READ `firstCfg.targetReps`/
      `targetWeight` for strength (currently reads neither).
      **⚠️ SEED-PATH GAP (phantom-field risk):** `targetReps` is honored by the seed already, but **`targetWeight`
      is NOT** — `RoutineStartExercise` has no `targetWeight` field and the seed weight line has no target term.
      Must: (1) add `double? targetWeight` to `RoutineStartExercise` (Freezed regen, **no DB**), (2) pass it in
      `start_routine_action.dart`, (3) fix the seed to `re.targetWeight ?? prev?.weight ?? equipDefaults.weight`
      (`active_workout_notifier.dart:458`, mirroring the reps precedence at :459). **No Postgres migration**
      (JSONB round-trips `target_weight`), but a 1-field Freezed addition + 3-line seed wiring — NOT "no model change."
      **Bodyweight:** reps is the hero; weight = optional "Added weight" (belt +20 / assist −15), default hidden
      behind a "+ Add weight" reveal (mockup decides always-show vs reveal). Label "Added weight"/"Peso adicional".

### Steps
- [x] Mockup sections in `docs/phase-38-mockups.html` ("Phase 38h-v2") → **user sign-off** ✅ approved 2026-06-19 (bodyweight = two pills grey+muscle; reorder body collapses; added-weight reveal)
- [x] tech-lead TDD (code+tests done; awaiting reviewer) → reviewer → QA (E2E selector audit) → visual gate → ship
- [ ] PROJECT.md row on merge

Phase 38 ✅ COMPLETE + post-38 shipped (#352 CI job, #353 routine cards, #355 polish). Open §2: post-launch cardio recalibration.
