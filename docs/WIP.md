# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## 23-P-4 — E2E dismissal-time assertions for the three undo SnackBars

Per PROJECT.md §2 Active Backlog → 23-P-4 (PR #214 follow-up, 2026-05-13).
Branch: `test/23-p-4-e2e-snackbar-dismissal-assertions`

**Why.** The current E2E suite asserts SnackBar *appearance* only, never
*dismissal*. That is exactly how the `persist-eats-duration` cluster bug hid
for weeks (source-grep widget tests pinned `persist: false` at the call site
but nothing asserted the snack actually disappeared at duration). Add timing
assertions so a future regression of `persist: false` or the countdown widget
can't slip past CI again. Until added, the source-grep widget-test pins in
`test/widget/shared/widgets/snackbar_tap_out_dismiss_scope_drain_test.dart`
are the safety net.

**Scope.** Three undo SnackBars, two spec files. Durations confirmed in source:

| SnackBar | Duration | Source pin | Spec file |
|---|---|---|---|
| Add-exercise undo (H5) | 3.5 s | `lib/features/workouts/ui/active_workout_screen.dart:368` | `workouts.spec.ts` |
| Set-delete undo (swipe) | 5 s | `lib/features/workouts/ui/widgets/set_row.dart:214` | `workouts.spec.ts` |
| Routine-removed undo | 3 s | `lib/features/weekly_plan/ui/plan_management_screen.dart:328` | `weekly-plan.spec.ts` |

**Selectors (already in `helpers/selectors.ts`).**
- `WORKOUT.addExerciseUndoSnackBar` — `role=group[name=/.+ added$/]`
- `WORKOUT.addExerciseUndoButton` — `role=button[name="Undo"]`
- `WORKOUT.swipeToDeleteUndoButton` — `role=button[name="Undo"]`
- Routine-removed snack has no dedicated selector yet — needs adding (locale-sensitive `routineRemoved` ARB string is `"Routine removed"` in en; will use a role-group regex or pin the Undo button after triggering the swipe-remove).

**Checklist**

- [x] Read existing tests for context patterns:
  - `workouts.spec.ts:1792-1872` (Add exercise undo describe block)
  - `workouts.spec.ts:1010-1130` (Swipe-delete + rest-timer overlap tests)
  - `weekly-plan.spec.ts` whole file (no existing remove test — verified flow)
- [x] Add `WEEKLY_PLAN.routineRemovedUndoSnackBar` + `routineRemovedUndoButton` selectors to `helpers/selectors.ts`.
- [x] In `workouts.spec.ts` "Add exercise undo (PR3 — H5)" describe: added `test('should auto-dismiss the add-exercise undo SnackBar after 3.5 s (23-P-4)')`.
- [x] Noted: set-delete auto-dismiss test already exists at `workouts.spec.ts:1153` — no new test needed for that case.
- [x] In `weekly-plan.spec.ts`: added new describe `Weekly Plan — routine-removed undo SnackBar dismissal (23-P-4)` with dedicated user `smokeWeeklyPlanRoutineRemoveUndo`. Added `test('should auto-dismiss the routine-removed undo SnackBar after 3 s (23-P-4)')`.
- [x] Added `smokeWeeklyPlanRoutineRemoveUndo` user to `test-users.ts` + seed runner in `global-setup.ts`.
- [x] Run the affected specs locally:
  - `FLUTTER_APP_URL= npx playwright test specs/workouts.spec.ts --reporter=list` — 40 passed, 3 pre-existing login-timeout failures at the tail of the 43-test sequential run (smokeWorkoutPr6RowFlicker, smokeRestChrome, smokeAutoSeed — all pass in smoke parallel run).
  - `FLUTTER_APP_URL= npx playwright test specs/weekly-plan.spec.ts --reporter=list` — 11 passed (exit 0).
- [x] Run smoke suite to confirm no regression: 119 passed (exit 0), 0 failures.
- [ ] Open PR with body noting QA pass is intrinsic (this IS the QA-pass work).

**Out of scope for this branch.**
- Re-pinning the widget-tests under `snackbar_tap_out_dismiss_scope_drain_test.dart` — they already cover countdown bar drain at the unit level.
- Adding dismissal assertions to the existing "should show ... undo SnackBar" tests — keep appearance-only assertions where they are; the new dismissal-time tests are dedicated regression pins.
