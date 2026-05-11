# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `PLAN.md` step or backlog entry, check items off
as work lands, and remove the section after the merge condenses to PLAN.md.

---

## Active Workout Audit — PR-4: Set defaults + edge cases

**Branch:** `fix/active-workout-pr4-set-defaults-and-edge-cases`
**Source:** Per `BUGS.md` PR-4 OPEN cluster + `PLAN.md` Phase 22 cluster ledger.

**Goal:** correctness in pre-fill defaults (Q2 warmup filtering) + 2 latent
edge cases in propagation and cascading undo. All in the notifier and
`exercise_card._computeNewSetDefaults`.

### Acceptance criteria

1. **M1 / Q2 — Warmup filter on previous-session pre-fill**
   (`lib/features/workouts/ui/widgets/exercise_card.dart` `_computeNewSetDefaults`,
   `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` `startFromRoutine`).
   `_computeNewSetDefaults` Priority 1 (previous-session at matching index)
   currently includes warmups. `startFromRoutine` clamps `previousSets[setIndex]`
   without filtering warmups too. Filter `lastSets` (and `previousSets` in
   the routine path) by `setType != warmup` BEFORE index-matching. Per Q2
   decision (FitNotes/Hevy benchmarks; warmup ≠ performance data).
2. **M2 — `propagateWeight` null vs 0 edge case**
   (`active_workout_notifier.dart` `propagateWeight` ~line 494).
   `(s.weight ?? 0) != oldWeight` treats `null` as `0`. When `oldWeight==0`
   and a follower has `weight: null` (e.g. routine-prefilled with no
   weight history), the walk continues past it and overwrites — could
   produce false PRs. Distinguish `null` from `0`: treat null as
   customized → stop walk.
3. **M3 — Cascading undo restores in wrong order**
   (`active_workout_notifier.dart` `restoreSet`).
   Delete set #2, delete set #3 (now renumbered to #2), undo each → original
   set #4 ends up at position 2 instead of 3 because `setNumber` was
   renumbered between deletes. Fix: `restoreSet` should insert based on the
   ORIGINAL position captured at delete time, with a stable sort over
   current sets — not the post-delete renumbered position.

### Files to modify

- `lib/features/workouts/ui/widgets/exercise_card.dart` — `_computeNewSetDefaults`: filter `lastSets` by `setType != warmup` before index-matching (M1)
- `lib/features/workouts/providers/notifiers/active_workout_notifier.dart`:
  - `startFromRoutine`: filter `previousSets` by `setType != warmup` before clamping (M1)
  - `propagateWeight`: distinguish `null` weight from `0` weight (M2)
  - `restoreSet`: insert by ORIGINAL captured position (M3)

### Tests to add (widget + E2E per the user's coverage directive)

**Widget/unit tests** in `active_workout_notifier_test.dart`:
- M1 — `_computeNewSetDefaults` skips warmup-typed previous-session sets when picking the matching-index default (parameterized: previous session has [warmup@40, working@100], adding new set defaults to working not warmup)
- M1 — `startFromRoutine` filters previous-session warmups before clamping (cover the edge case where previous session was warmup-heavy)
- M2 — `propagateWeight` stops walk on follower with `weight: null` (does NOT overwrite)
- M2 — `propagateWeight` continues walk on follower with `weight: 0` when oldWeight is 0 (current behavior preserved for the actually-zero case)
- M3 — Cascading delete-then-undo restores ORIGINAL order (delete #2, delete #3-renumbered-to-#2, undo each → final order matches initial [1,2,3,4])
- M3 — Single delete-undo still works (no regression)

**E2E tests in `test/e2e/specs/workouts.spec.ts`:**
- `Set defaults filtering warmups (PR4 — Q2/M1)` describe block:
  - "should pre-fill working-set default from previous working set, skipping previous warmups" (M1)
  - "should pre-fill routine-start working sets ignoring previous warmups" (M1, requires routine seed)
- `Cascading undo restores order (PR4 — M3)` describe block:
  - "should restore deleted sets in original order across cascading deletes" (M3, drives delete + undo sequence)

E2E selectors should be reusable from prior PRs (set rows, snackbar undo). Add new fixture user(s) with seeded warmup history if needed for M1.

### Pipeline checklist

- [x] `tech-lead` reads PLAN.md Phase 22 + this WIP + the BUGS.md PR-4 entries (M1, M2, M3), then implements with TDD.
- [x] M1 — `_computeNewSetDefaults` + `startFromRoutine` filter previous-session warmups before index-matching.
- [x] M2 — `propagateWeight` distinguishes `null` follower weight from `0` and stops the walk on null.
- [x] M3 — `restoreSet` uses an original-index map (id-keyed) maintained on every `deleteSet`. Stable across cascading deletes.
- [x] After each fix: `dart format .` + `dart analyze --fatal-infos` clean.
- [x] All new tests pass; existing tests still pass.
- [x] E2E coverage added (warmup default + cascading undo flows). Selector / fixture-user additions land in `helpers/selectors.ts` + `fixtures/test-users.ts` + `global-setup.ts` as needed.
- [ ] `qa-engineer` reviews coverage, runs full E2E suite locally.
- [ ] Orchestrator runs CI verification — 0 failures, full output read.
- [ ] PR opened with copy of acceptance criteria and "Closes BUGS.md M1/Q2, M2, M3."
- [ ] `reviewer` flags addressed in same cycle (no deferral, per memory rule).
- [ ] Squash merge to `main`; no DB migration; close WIP section in a follow-up docs PR; update BUGS.md to mark items RESOLVED with PR ref.

### M3 implementation note

Chose **Option B (stable insertion key by id)** over **Option A (out-of-band index parameter)**.

Reason: Option A pushes orchestration concerns into the swipe handler (caller has to remember the original index across consecutive deletes). Option B keeps `restoreSet`'s public contract unchanged — the notifier owns the bookkeeping internally via a `Map<String, int> _originalSetIndices` keyed by set id. `deleteSet` records the to-be-deleted set's CURRENT index BEFORE renumbering (or reuses an already-recorded original index if the set was previously renumbered by an earlier cascading delete). `restoreSet` looks up the id and inserts at that original index, then drops the entry from the map. This is a structural guarantee — there's no "did the caller remember?" question, the notifier always knows.
