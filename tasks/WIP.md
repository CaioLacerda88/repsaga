# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `PLAN.md` step or backlog entry, check items off
as work lands, and remove the section after the merge condenses to PLAN.md.

---

## Active Workout Audit — PR-2: Tap target + undo-snackbar reachability

**Branch:** `fix/active-workout-pr2-tap-target-and-undo-snackbar`
**Source:** Per `BUGS.md` PR-2 OPEN cluster + `PLAN.md` Phase 22 cluster ledger.

**Goal:** lift the most time-critical tap (set-completion checkbox) to the
Material 48dp floor + make the swipe-to-delete undo SnackBar reachable when
the rest-timer overlay is up. Plus close the discard-race E2E gap surfaced
post-PR-1.

### Acceptance criteria

1. **H1 — Done-checkbox tap target ≥ 48dp** (`set_row.dart` `_DoneCell` ~lines 1281-1296).
   Inner `SizedBox(width: 40, height: 48)` is widened to ≥ 48dp horizontally
   (or full 52dp Container width). Same for `_PredictedPrUncheckedMark` (32dp
   visual + ≥ 48dp tappable wrapper). `deferToChild` keeps stepper taps safe.
   Pinned by widget test using `tester.getSize()` per the
   `feedback_tap_target_measurement.md` memory rule.
2. **C3 / Q5 — Undo SnackBar visible AND reachable above the rest-timer overlay**
   (`set_row.dart:264-278`, `rest_timer_overlay.dart:71-77`,
   `active_workout_screen.dart` Stack ordering).
   Snackbar duration 4s → 10s (Material max). Z-order: snackbar must render
   ABOVE `RestTimerOverlay`'s scrim. Tap on the Undo action must reach the
   handler — the rest-timer overlay's full-screen GestureDetector must NOT
   capture taps in the snackbar's region.
3. **Discard-race E2E** (post-PR-1 gap; `test/e2e/specs/workouts.spec.ts`).
   Same `page.route()` stall pattern as PR-1's Q1 cancel-overlay test, but on
   `DELETE /workouts`. Tap Cancel during the stall → workout restored. Then
   release the stall → discard succeeds → home navigation.

### Files to modify

- `lib/features/workouts/ui/widgets/set_row.dart`
  - `_DoneCell`: widen the inner GestureDetector tap area to ≥ 48dp (use full
    52dp Container width is the cleanest fix — `deferToChild` prevents
    stealing taps from steppers); confirm `_PredictedPrUncheckedMark` parent
    is also ≥ 48dp on both axes.
  - Snackbar duration in the swipe-to-delete `onDismissed` handler: 4 → 10s.
- `lib/features/workouts/ui/widgets/rest_timer_overlay.dart`
  - Re-evaluate the full-screen `GestureDetector` (line 71-77) so it does NOT
    intercept taps targeted at sibling overlays in the same Stack. Likely fix:
    use `HitTestBehavior.translucent` with explicit excluded regions, OR move
    the dismiss listener to a more constrained widget that doesn't cover the
    snackbar slot. Investigate during implementation; constrain to the
    minimal change.
- `lib/features/workouts/ui/active_workout_screen.dart`
  - Re-stack the Scaffold/snackbar/overlay tree so `ScaffoldMessenger` lives
    ABOVE `RestTimerOverlay`. Likely a wrapper `ScaffoldMessenger` around the
    Stack rather than relying on the inner Scaffold's default. Verify no
    selector regressions on existing snackbar-bearing flows
    (offline-banner, workout-saved-offline, etc.).

### Tests to add (widget + E2E per the user's coverage directive)

In `test/widget/features/workouts/ui/widgets/set_row_test.dart` (or a
sibling tap-target test file):
- `_DoneCell` tap target measured via `tester.getSize()` is ≥ 48×48 dp on a
  360dp viewport (regression-pin H1).
- `_PredictedPrUncheckedMark` parent tap area is ≥ 48×48 dp.
- Tapping at the corner of the new wider area (outside the previous 40dp
  zone but inside the new ≥ 48dp zone) still toggles `isCompleted`.

In `test/e2e/specs/workouts.spec.ts`:
- **Snackbar visibility above rest timer** — describe block "Set deletion
  during rest timer (PR2 — C3)". Test: complete a set (rest timer fires),
  swipe-delete a sibling set, assert undo SnackBar is visible AND
  `data-flutter-flag` shows it's not occluded.
- **Snackbar undo reachability** — same describe. Test: tap Undo while rest
  timer overlay is up, assert set is restored.
- **Snackbar duration ≥ 10s** — same describe. Test: trigger snackbar, wait
  ~9s, assert still visible (Material 10s default leaves a small grace).
- **Discard-race cancel** — describe block "Workout discard cancel (PR2 —
  Fix B coverage gap)". Test: open active workout, tap discard, stall
  `DELETE /workouts` via `page.route()`, tap Cancel on the loading overlay,
  assert workout still active (set still logged); release stall, retry
  discard, assert home navigation.

E2E selectors to add in `test/e2e/helpers/selectors.ts`:
- `swipeToDeleteSnackBar` (role=alert or by text content)
- `swipeToDeleteUndoButton`
Add a new fixture user if needed to keep tests isolated.

### Pipeline checklist

- [ ] `tech-lead` reads PLAN.md Phase 22 + this WIP + the BUGS.md PR-2 entries,
      then implements with TDD.
- [ ] After each fix: `dart format .` + `dart analyze --fatal-infos` clean.
- [ ] All new widget tests pass; existing notifier/widget tests still pass.
- [ ] `qa-engineer` reviews coverage, runs full E2E suite locally, adds any
      missing E2E. Selector additions go in `helpers/selectors.ts`.
- [ ] Orchestrator runs `make ci` equivalent — 0 failures, full output read.
- [ ] PR opened with copy of acceptance criteria and "Closes BUGS.md
      H1, C3, plus PR-2 discard-race E2E gap."
- [ ] `reviewer` flags addressed in same cycle (no deferral, per memory rule).
- [ ] Squash merge to `main`; no DB migration; close WIP section in a
      follow-up docs PR; update BUGS.md to mark items RESOLVED with PR ref.
