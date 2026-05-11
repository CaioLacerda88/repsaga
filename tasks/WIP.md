# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `PLAN.md` step or backlog entry, check items off
as work lands, and remove the section after the merge condenses to PLAN.md.

---

## Active Workout Audit — PR-3: Hidden destructive gestures cleanup + Q3 swap confirm + S1

**Branch:** `fix/active-workout-pr3-destructive-gestures-cleanup`
**Source:** Per `BUGS.md` PR-3 OPEN cluster + `PLAN.md` Phase 22 cluster ledger.

**Goal:** every destructive shortcut on the active-workout surface either
removed or behind an explicit confirm/undo. Plus close S1 (DiscardCoordinator
re-entrance window) which surfaced during PR-2's implementation.

### Acceptance criteria

1. **H2 / Q6 — Remove long-press swap on exercise name** (`exercise_card.dart:424-427`).
   Drop the `onLongPress` from the header InkWell entirely. The visible
   `swap_horiz` button is the sole entry point for swap. Per Q6 decision
   (industry has converged AWAY from gesture shortcuts in gym apps).
2. **H3 — Remove long-press Fill Remaining on Add Set** (`exercise_card.dart:313-315`).
   Drop the `onLongPress` from `_AddSetButton`. The visible `_FillRemainingButton`
   below it is the sole entry point. No two-affordance redundancy for the same
   action.
3. **Q3 — Conditional confirm when swap-with-completed-sets**
   (`exercise_card.dart` `_swapExercise`).
   - Zero completed sets on the exercise → silent swap (no friction)
   - One or more completed sets → confirm sheet/dialog with copy:
     "Swap to **\<New Exercise>**? Your N logged sets will count toward
     **\<New Exercise>** PRs (not \<Old Exercise>)."
   - Concrete exercise names per UI critic guidance, not "the new exercise."
   - Explicit Cancel + Swap actions.
4. **H5 — Add-exercise undo snackbar** (`exercise_picker_sheet.dart:215`,
   `active_workout_notifier.dart` new `restoreExercise(...)` mirror of
   `removeExercise`).
   Tap on exercise in picker = immediate add (unchanged). On add, show 4-second
   undo snackbar ("**\<Exercise>** added — Undo") that calls
   `notifier.restoreExercise(workoutExercise.id)` to remove the added exercise.
   The new method takes the workoutExercise id (UUID) since `removeExercise`
   uses the same handle. Restore should clear the entry from `state.exercises`
   AND release the ID slot for re-add. Note: undo snackbar is for ADD-only,
   not swap (swap has its own confirm per Q3).
5. **S1 — DiscardWorkoutCoordinator re-entrance window**
   (`discard_workout_coordinator.dart:38-67`).
   When `cancelLoading` fires mid-discard, the coordinator's `_isShowingDialog`
   stays `true` until the still-in-flight `discardWorkout()` completes — silently
   no-ops subsequent discard attempts. Fix: listen for state restoration
   post-await — if `state.value != null` after `await discardWorkout()`, that
   means cancel restored state; clear `_isShowingDialog` early so the user can
   retry. Alternatively convert to a notifier-coupled flag. Tech-lead picks
   the cleaner of the two; both options documented in `BUGS.md` S1.

### Files to modify

- `lib/features/workouts/ui/widgets/exercise_card.dart`
  - Drop `onLongPress` from header InkWell (H2/Q6)
  - Drop `onLongPress` from `_AddSetButton` (H3)
  - Add conditional confirm in `_swapExercise` when `widget.activeExercise.sets.any((s) => s.isCompleted)` (Q3)
- New widget: `lib/features/workouts/ui/widgets/swap_exercise_confirm_dialog.dart` (Q3 confirm dialog with concrete exercise names)
- `lib/features/workouts/ui/widgets/exercise_picker_sheet.dart` — when used as add-exercise (NOT swap), show undo snackbar after add (H5)
- `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` — add `restoreExercise(...)` mirror of `removeExercise` (H5)
- `lib/features/workouts/ui/coordinators/discard_workout_coordinator.dart` — fix S1 re-entrance window
- `lib/l10n/app_en.arb` + `app_pt.arb` — new keys for Q3 confirm copy + H5 undo snackbar

### Tests to add (widget + E2E per the user's coverage directive)

**Widget tests:**
- `exercise_card_test.dart` (or new file) — long-press on header DOES NOT open swap picker (H2/Q6)
- `exercise_card_test.dart` — long-press on Add Set DOES NOT trigger fill remaining (H3)
- `exercise_card_test.dart` — `_swapExercise` with zero completed sets does NOT show confirm dialog (Q3)
- `exercise_card_test.dart` — `_swapExercise` with ≥1 completed set DOES show confirm dialog with concrete exercise names (Q3)
- `exercise_card_test.dart` — confirm Cancel keeps exercise as-is; confirm Swap proceeds (Q3)
- `active_workout_notifier_test.dart` — `restoreExercise` removes the entry by id (H5)
- `discard_workout_coordinator_test.dart` (new file) — `_isShowingDialog` cleared after cancel restores state (S1)

**E2E tests in `test/e2e/specs/workouts.spec.ts`:**
- `Exercise card destructive gestures cleanup (PR3)` describe block:
  - "should NOT swap exercise on long-press of header" (H2/Q6)
  - "should NOT trigger fill remaining on long-press of Add Set" (H3)
- `Swap exercise with logged sets (PR3 — Q3)` describe block:
  - "should swap silently when no sets are completed" (Q3)
  - "should show confirm dialog when ≥1 set is completed, with concrete exercise names" (Q3)
  - "should keep original exercise when Cancel is tapped on confirm" (Q3)
  - "should swap when Confirm is tapped on confirm" (Q3)
- `Add exercise undo (PR3 — H5)` describe block:
  - "should show undo snackbar after adding an exercise from picker" (H5)
  - "should remove the just-added exercise when Undo is tapped" (H5)
- `Discard re-entrance (PR3 — S1)` describe block:
  - "should allow re-opening discard dialog after Cancel during stalled DELETE" (S1)
    - Pattern: stall DELETE via page.route, tap discard X, tap confirm, tap Cancel on overlay (state restored), tap discard X AGAIN BEFORE the stall resolves, assert confirm dialog appears (S1 fixed → re-entrance unblocked)

E2E selectors to add in `test/e2e/helpers/selectors.ts`:
- `swapExerciseConfirmDialog` (role=alertdialog or by text)
- `swapExerciseConfirmCancelButton` / `swapExerciseConfirmSwapButton`
- `addExerciseUndoSnackBar`
- `addExerciseUndoButton`
Add new fixture users if needed for isolation.

### Pipeline checklist

- [ ] `tech-lead` reads PLAN.md Phase 22 + this WIP + the BUGS.md PR-3 entries (H2/Q6, H3, Q3, H5, S1), then implements with TDD.
- [ ] After each fix: `dart format .` + `dart analyze --fatal-infos` clean.
- [ ] All new tests pass; existing tests still pass.
- [ ] `qa-engineer` reviews coverage, runs full E2E suite locally, adds any missing E2E. Selector additions go in `helpers/selectors.ts`.
- [ ] Orchestrator runs CI verification — 0 failures, full output read.
- [ ] PR opened with copy of acceptance criteria and "Closes BUGS.md H2/Q6, H3, Q3, H5, S1."
- [ ] `reviewer` flags addressed in same cycle (no deferral, per memory rule).
- [ ] Squash merge to `main`; no DB migration; close WIP section in a follow-up docs PR; update BUGS.md to mark items RESOLVED with PR ref.
