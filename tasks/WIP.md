# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `PLAN.md` step or backlog entry, check items off
as work lands, and remove the section after the merge condenses to PLAN.md.

---

## Active Workout Audit — PR-1: State-machine integrity

**Branch:** `fix/active-workout-pr1-state-integrity`
**PR:** [#195](https://github.com/CaioLacerda88/repsaga/pull/195) — reviewer findings applied, awaiting CI

**Source:** Per the Active Workout audit (this conversation). Fix wave PR-1 of 7.
Addresses 4 audit findings (C1, C2, C4, H7) plus the Q1 UX decision for the
loading overlay's Cancel button. RPC idempotency was verified separately —
`save_workout` + `record_set_xp` defend XP integrity via the BUG-RPG-001
reversal pattern + `xp_events(user_id, set_id)` UNIQUE INDEX, so this PR is
purely a Dart-side correctness fix (no DB migration required).

**Goal:** prevent data-loss / unrecoverable-state failure modes in the active
workout state machine, and unstick the loading overlay's Cancel button so it
always has a meaningful action to take.

### Acceptance criteria

1. **C1 — cancel-after-save race** (`active_workout_notifier.dart:1278-1289`).
   Once `_repo.saveWorkout(...)` returns success, `_cancelRequested` becomes a
   no-op. The finish flows through normally: celebration plays, navigation
   happens, state goes to `AsyncData(null)`. Cancel is honored ONLY pre-commit.
2. **C2 — discard order** (`active_workout_notifier.dart:719-721`). Server call
   first; clear Hive only on success. Terminal error path leaves Hive intact so
   the user can retry / recover.
3. **C4 — `cancelLoading` dead-end** (`active_workout_notifier.dart:124-134`).
   When `_lastValidState == null` (start phase), emit `state = AsyncData(null)`
   so the screen falls through to `/home` navigation. No permanent spinner.
4. **H7 — offline weekly-plan dependency** (`active_workout_notifier.dart:1229-1238`).
   `PendingMarkRoutineComplete` enqueued during offline finish carries
   `dependsOn: [workout.id]`. Verified as a real corruption hazard via
   investigation of `weekly_plans.routines` (JSONB, no FK, RPC silently inserts
   unknown UUIDs) + `SyncService` drain (FIFO + dependsOn only).
5. **Q1 — Cancel from t=0** (`active_workout_loading_overlay.dart`). Cancel
   button visible immediately when the overlay mounts, in every phase
   (start/finish/discard). Drop the 10s `_cancelTimeout` timer. Drop the
   `hasRestorable` gate — combined with C4, `cancelLoading` always has a
   meaningful action.

### Files to modify

- `lib/features/workouts/providers/notifiers/active_workout_notifier.dart`
  - `cancelLoading()`: emit `AsyncData(null)` when `_lastValidState == null`;
    reset `_cancelRequested = false` after restoration so it doesn't leak.
  - `discardWorkout()`: swap the two awaits — `_repo.discardWorkout(...)` first,
    `_localStorage.clearActiveWorkout()` only on success.
  - `finishWorkout()`: introduce `var saveCommitted = false;` inside the guard
    scope; flip true immediately after `_repo.saveWorkout(...)` returns; gate
    the cancel-check at line 1282 to `if (_cancelRequested && !saveCommitted)`.
  - Offline `PendingMarkRoutineComplete` enqueue: add
    `dependsOn: [workout.id]`.
- `lib/features/workouts/ui/widgets/active_workout_loading_overlay.dart`
  - Remove `_showCancel` state, `_timer`, `_cancelTimeout`, `initState`,
    `dispose`. Convert to `ConsumerWidget`.
  - Remove `hasRestorable` parameter (and the call site in
    `active_workout_screen.dart:109`).
  - Cancel button always rendered.
- `lib/features/workouts/ui/active_workout_screen.dart`
  - Drop the `hasRestorable: asyncState.hasValue` arg at line 109.

### Tests to add (TDD-first per CLAUDE.md)

In `test/unit/features/workouts/providers/notifiers/active_workout_notifier_test.dart`:
- `discardWorkout` — when `_repo.discardWorkout` throws terminal: Hive remains
  populated, `state` is `AsyncError`.
- `discardWorkout` — when server call succeeds: Hive cleared, state is
  `AsyncData(null)`.
- `cancelLoading` with `_lastValidState == null` — emits `AsyncData(null)`.
- `cancelLoading` with valid `_lastValidState` — emits `AsyncData(restored)`.
- `finishWorkout` — cancel BEFORE `saveWorkout` returns: state restored to
  pre-finish, no celebration built, no navigation, no XP committed (no save
  ever fired).
- `finishWorkout` — cancel AFTER `saveWorkout` returns success: celebration
  built, FinishWorkoutResult returned non-null, state ends `AsyncData(null)`,
  `_isFinishing` cleared.
- `finishWorkout` offline path — `PendingMarkRoutineComplete` enqueued with
  `dependsOn: [workout.id]` (assert against the captured `enqueue` call).

In `test/widget/features/workouts/ui/widgets/active_workout_loading_overlay_test.dart`:
- Cancel button is rendered immediately on mount (no pump-and-wait for 10s).
- Tap on Cancel calls `cancelLoading` on the notifier.

E2E impact assessment (per CLAUDE.md QA gate, navigation/provider logic
changed):
- `test/e2e/specs/workouts.spec.ts` and any spec using the discard / finish
  flow — verify no selector breakage. Add at minimum one regression test:
  starting a workout with a stalled network, tapping Cancel, ending up on
  `/home` (BUG-C4). Run full suite locally before PR open.

### Pipeline checklist

- [ ] `tech-lead` reads PLAN.md Quick Reference + this WIP + the audit summary
      in conversation, then implements with TDD.
- [ ] After each fix: `dart format .` + `dart analyze --fatal-infos` clean.
- [ ] All new tests pass; existing notifier tests still pass.
- [ ] `qa-engineer` reviews coverage, runs full E2E suite locally
      (`FLUTTER_APP_URL= npx playwright test --reporter=list` from
      `test/e2e/`). Adds new E2E for the Q1 + C4 cancel-to-home flow.
- [ ] Orchestrator runs `make ci` — 0 failures, full output read.
- [ ] PR opened with copy of acceptance criteria and "Closes audit findings
      C1, C2, C4, H7; implements Q1."
- [ ] `reviewer` flags addressed in same cycle (no deferral, per memory rule).
- [ ] Squash merge to `main`; no DB migration to apply (verified above).
- [ ] WIP section removed; PLAN.md unchanged (this is a fix wave, not a phase).
