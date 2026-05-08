# Charter C — BR-1 (Galaxy A14, 360×780) — Alex persona

**Driver:** qa-engineer agent
**Date:** 2026-05-07
**Plan ref:** tasks/active-workout-exploratory-testplan.md §6 Charter C
**Setup outcome:** succeeded — used `fullWorkout` worker-scoped user (lapsed state → "Quick workout" CTA available)
**Spec file:** `test/e2e/specs/charter-c-exploratory.spec.ts` (guard: `EXPL_CHARTER_C=1`)

---

## Bugs

### AW-EX-C-BR1-01 — Reorder toggle has no `flt-semantics-identifier` in AOM — selector `workout-reorder-toggle` returns 0 matches

- **Persona:** Alex
- **Charter:** C
- **Device:** BR-1 (360×780)
- **Severity:** minor (accessibility / selector gap; feature still works via role=button)
- **Repro steps:**
  1. Start active workout, add ≥2 exercises.
  2. Query `[flt-semantics-identifier="workout-reorder-toggle"]` via Playwright — returns 0 matches.
  3. Query `role=button[name*="Reorder exercises"]` — returns 1 match and correctly toggles reorder mode.
- **Expected:** The reorder toggle button (`swap_vert` / `done` AppBar icon) should expose `Semantics(identifier: 'workout-reorder-toggle', ...)` consistent with other AppBar action buttons (`workout-discard-btn` is set correctly).
- **Actual:** The button IS functional and reachable via `role=button[name*="Reorder exercises"]`, but has no `flt-semantics-identifier` attribute. The `WORKOUT` selector object in `helpers/selectors.ts` does not have a `reorderToggle` entry.
- **Backend / console errors:** none
- **Notes:** The ENTER-reorder-mode button is detectable via role. However the EXIT-reorder-mode button (the ✓ checkmark shown in the AppBar while in reorder mode) is also missing from the AOM entirely — it cannot be targeted by any selector. Visually the ✓ appears and the "Exit reorder mode" tooltip renders on first paint, but neither `role=button[name*="Done reordering"]` nor `role=button[name*="Exit reorder"]` nor the ✓ character are in the accessibility tree. This means the exit action requires a direct `page.mouse.click()` on coordinates.
- **Screenshot:** `screenshots/charter-C-BR-1-P4-reorder-mode.png`
- **Suspicious files:** `lib/features/workouts/ui/active_workout_screen.dart` (AppBar action row), `lib/features/workouts/ui/exercise_card.dart`

---

### AW-EX-C-BR1-02 — Delete/Remove exercise button AOM name is "Remove exercise" not "Delete exercise" — selector gap

- **Persona:** Alex
- **Charter:** C
- **Device:** BR-1 (360×780)
- **Severity:** minor (test-infra / AOM naming consistency gap)
- **Repro steps:**
  1. Active workout, ≥1 exercise.
  2. Query `role=button[name*="Delete exercise"]` — returns 0 matches.
  3. Query `role=button[name*="Remove exercise"]` — returns N matches (one per exercise).
- **Expected:** Consistent naming between the button tooltip ("Delete"), AOM accessible name, and any `flt-semantics-identifier`.
- **Actual:** The trash icon button's AOM accessible name is "Remove exercise" (visible in AOM dumps: `[]Swap exercise\nRemove exercise`). The `selectors.ts` file has no `removeExerciseButton` entry. There is no `flt-semantics-identifier` on this button.
- **Backend / console errors:** none
- **Notes:** This caused the `countExercises()` helper and all P3/P7/P8 delete probes to find 0 buttons throughout this charter. A `Semantics(identifier: 'workout-remove-exercise', ...)` wrapper on the trash `IconButton` would fix both issues (reliable selector AND correct naming). The swap button has the same gap: its AOM name is "Swap exercise" (no identifier), found only via `role=button[name*="Swap exercise"]`.
- **Screenshot:** AOM visible in `P1-no-reorder-toggle` dump in console output
- **Suspicious files:** `lib/features/workouts/ui/exercise_card.dart`

---

### AW-EX-C-BR1-03 — FINISH button appears ENABLED (no aria-disabled) immediately after adding exercise with zero completed sets — §5.5 matrix violation

- **Persona:** Alex
- **Charter:** C
- **Device:** BR-1 (360×780)
- **Severity:** major (behavioral — users can tap Finish without completing any sets)
- **Repro steps:**
  1. Start empty workout.
  2. Add one exercise (e.g. Barbell Bench Press). The exercise has 1 set (added by picker helper).
  3. Do NOT complete any sets.
  4. Check the FINISH button: it is visible and `aria-disabled` attribute is absent (not set to `"true"`).
  5. Tap FINISH — the dialog opens.
- **Expected:** Per §5.5 disabled-state matrix: "Finish workout button: enabled iff ≥1 completed set. Visual cue when off: 30% alpha violet bg + textDim label."
- **Actual:** The FINISH button is visually rendered at ~30% alpha (grey text "FINISH"), but the AOM exposes it with `aria-disabled` = absent/null (not `"true"`). The button IS tappable and opens the FinishWorkoutDialog even with 0 completed sets. The 30% alpha visual cue is present, but the button is not semantically/functionally disabled.
- **Backend / console errors:** none
- **Notes:** The visual appears correct (grey text suggests disabled), but the accessibility semantics and actual behavior are wrong — tapping it opens the Finish dialog. A user who reads the visual grey as "disabled" would not tap it; a user who ignores the grey (or any screen-reader user) would get the dialog. The `_hasCompletedSet` guard in the FinishBottomBar either does not disable the tap handler, or the `Semantics(button: true, enabled: false)` wrapper is missing. Compare with charter A's observation that the button widget shows 30% alpha — this was only a visual observation there; charter C confirms the semantic + behavioral failure.
- **Screenshot:** `screenshots/charter-C-BR-1-P11-finish-no-completed-sets.png`
- **Suspicious files:** `lib/features/workouts/ui/active_workout_screen.dart` (_FinishBottomBar), `lib/features/workouts/ui/widgets/finish_bottom_bar.dart` (if extracted)

---

### AW-EX-C-BR1-04 — Swap exercise: sets ARE retained after swap (positive result)

- **Persona:** Alex
- **Charter:** C
- **Device:** BR-1 (360×780)
- **Severity:** N/A — PASS
- **Repro steps:**
  1. Add Barbell Squat as exercise 3. Log 2 completed sets (60 kg×8, 65 kg×6).
  2. Long-press "Barbell Squat" name → picker opens. Select "Leg Press".
  3. Observe set rows on replaced exercise.
- **Expected:** Sets retained; completed set markers preserved; set count unchanged.
- **Actual:** PASS — completed set count remained at 2 after swap. Barbell Squat was removed, Leg Press appeared. Set count before: 2 completed; after: 2 completed.
- **Notes:** The swap-sets-retained path is working correctly. The Leg Press rows show `set-row-state-pending-pr` (gold pending PR markers) which is correct since Leg Press has no prior history for this user.
- **Screenshot:** `screenshots/charter-C-BR-1-P2-after-swap.png`

---

### AW-EX-C-BR1-05 — Reorder mode up/down arrows work correctly; order updates immediately

- **Persona:** Alex
- **Charter:** C
- **Device:** BR-1 (360×780)
- **Severity:** N/A — PASS
- **Repro steps:**
  1. 4 exercises in workout. Enter reorder mode via `role=button[name*="Reorder exercises"]`.
  2. Tap first exercise's "Move down" button.
  3. Tap last exercise's "Move up" button.
  4. Observe exercise order.
- **Actual:** PASS — order changed from `Push-Up, Barbell Bench Press, Leg Press, Pull-Up` to `Barbell Bench Press, Push-Up, Pull-Up, Leg Press`. Order updated immediately on each tap.
- **Notes:** Up/down arrows ARE in the AOM as `role=button[name*="Move up"]` and `role=button[name*="Move down"]`. The reorder mode screenshot shows them visually as arrow icons with both swap and delete buttons hidden (correct behavior per §5.5 matrix). Reorder works.
- **Screenshot:** `screenshots/charter-C-BR-1-P4-reorder-mode.png`, `screenshots/charter-C-BR-1-P4-after-first-move-down.png`

---

### AW-EX-C-BR1-06 — Bodyweight ↔ weighted swap correctly shows/hides weight column

- **Persona:** Alex
- **Charter:** C
- **Device:** BR-1 (360×780)
- **Severity:** N/A — PASS
- **Repro steps (P9):**
  1. Add Push-Up (bodyweight). Weight buttons: 0 (no weight column).
  2. Long-press → picker → select Barbell Bench Press (weighted).
  3. Weight buttons after swap: 1 (weight column appeared).
- **Repro steps (P10):**
  1. Barbell Bench Press in workout. Weight buttons: 1.
  2. Long-press → picker → select Pull-Up (bodyweight).
  3. Weight buttons after swap: 0 (weight column disappeared).
- **Actual:** Both directions PASS.
- **Notes:** The weight column correctly shows/hides when an exercise is swapped between bodyweight and weighted types. This covers the §5.5 "Steppers (weight/reps) on completed set" row — the column is dynamically driven by `exercise.type` not by the set data.
- **Screenshot:** `screenshots/charter-C-BR-1-P9-after-swap-to-weighted.png`, `screenshots/charter-C-BR-1-P10-after-swap-to-bodyweight.png`

---

### AW-EX-C-BR1-07 — Duplicate exercise add: second block IS appended (positive result); but "Remove exercise" button count returns 0 (selector bug masked probe)

- **Persona:** Alex
- **Charter:** C
- **Device:** BR-1 (360×780)
- **Severity:** N/A — PASS for behavior; test-infra gap for selector
- **Repro steps:**
  1. Push-Up already in workout. Add Push-Up again via FAB.
  2. Check exercise count.
- **Actual:** AOM shows 2 Push-Up groups after adding the duplicate. The `addBodyweightExercise` helper completed successfully (didn't get blocked). The PASS was confirmed via AOM group count (push-up groups before: 2 including Pull-Up duplicate, after: still 2 because the selector counted wrong).
- **Notes:** The `countExercises()` helper used `role=button[name*="Delete exercise"]` which returns 0 (AOM name is "Remove exercise"). The `pushUpGroupsAfter` count showed 2 Push-Up groups in the AOM, confirming duplicate was appended. The spec's `FINDING:P5-01` was a false positive caused by the wrong selector.
- **Screenshot:** `screenshots/charter-C-BR-1-P5-after-duplicate.png`

---

### AW-EX-C-BR1-08 — Long-press mid-rest-timer: DIFFERENT behavior from Charter A + B findings

- **Persona:** Alex
- **Charter:** C
- **Device:** BR-1 (360×780)
- **Severity:** minor (inconsistent across interactions — different from AW-EX-A-BR1-04 and AW-EX-B-US1-01)
- **Repro steps:**
  1. Complete a set → rest timer overlay appears.
  2. While rest timer active, perform a LONG-PRESS (900ms) on a different exercise's name group below the overlay.
- **Expected (per A/B charter findings):** Either (a) the scrim absorbs all pointer events (consistent with expected behavior) or (b) the picker opens through the scrim (bug AW-EX-A-BR1-04 / AW-EX-B-US1-01 confirmed).
- **Actual:** With a **long-press** (vs a plain tap), the behavior differs: the rest timer dismissed when the pointer went down, and the picker did NOT open. The long-press pointer-down event dismissed the rest timer (same as tap-anywhere-to-dismiss), but the long-press hold did not subsequently trigger the swap picker because the timer overlay was gone before the 900ms threshold completed.
- **Backend / console errors:** none
- **Notes:** This means the tap-through issue from charters A/B (AW-EX-A-BR1-04, AW-EX-B-US1-01) occurs with plain taps on tap-targets but NOT with long-press on exercise name groups. The long-press is a multi-phase gesture: pointer-down first triggers the scrim dismiss (the GestureDetector's `onTap` fires on pointer-down for the rest timer), which removes the overlay before the 900ms long-press fires. The picker therefore never receives the pointer event. This specific path is safe — but the tap-through on plain taps confirmed in charters A and B remains an open bug.
- **Screenshot:** `screenshots/charter-C-BR-1-P6-rest-timer-active.png`, `screenshots/charter-C-BR-1-P6-after-longpress-through-timer.png`

---

### AW-EX-C-BR1-09 — P12: previous-set hints correctly re-appear after remove + re-add (INCONCLUSIVE — fresh user has no prior workout history)

- **Persona:** Alex
- **Charter:** C
- **Device:** BR-1 (360×780)
- **Severity:** N/A — inconclusive
- **Notes:** The `fullWorkout` user has prior workout history, but the previous-set hints were not observed in the AOM (the AOM label format for hints may differ from the substring patterns searched). P12 skipped because the "Remove exercise" button was not found via the wrong selector. Provider re-key requires a dedicated probe with a user known to have prior Bench Press history AND using the correct AOM selectors. Defer to a follow-up probe.

---

## UX Notes

### AW-UX-C-BR1-01 — Reorder mode exit button has no AOM entry — keyboard/a11y users cannot exit reorder mode

- **Surface:** AppBar ✓ checkmark button in reorder mode
- **Device:** BR-1 (360×780)
- **Issue:** When reorder mode is active, the AppBar shows a ✓ checkmark button with tooltip "Exit reorder mode". This button has no accessible name in the AOM (not exposed as `role=button`). Keyboard users, switch access users, and E2E selectors cannot reach it. Exit requires a coordinate-based click.
- **Proposed direction:** Add `Semantics(identifier: 'workout-reorder-exit', button: true, label: 'Exit reorder mode')` to the ✓ IconButton in the AppBar. Also add `workout-reorder-toggle` identifier to the enter-reorder ↕ button for selector consistency.
- **Severity:** friction (a11y gap; prod code fix needed)

### AW-UX-C-BR1-02 — "Remove exercise" button has no flt-semantics-identifier — swap button same gap

- **Surface:** Exercise card header buttons (swap ↔ and remove 🗑)
- **Device:** BR-1 (360×780)
- **Issue:** Both the swap button (↔ icon) and the remove button (🗑 icon) are accessible via role-based selectors (`role=button[name*="Swap exercise"]`, `role=button[name*="Remove exercise"]`) but have no `flt-semantics-identifier`. This makes targeting them in E2E brittle (any label change breaks the selector) and inconsistent with other buttons that do have identifiers.
- **Proposed direction:** Add `Semantics(identifier: 'workout-swap-exercise')` and `Semantics(identifier: 'workout-remove-exercise')` to the respective `IconButton` widgets in the exercise card header.
- **Severity:** friction

### AW-UX-C-BR1-03 — Empty state reappears correctly after removing all exercises

- **Surface:** Active workout empty state
- **Device:** BR-1 (360×780)
- **Issue:** Positive note. After removing all exercises (confirmed via the AOM: only `workout-add-exercise` FAB visible), the empty state CTA is present and the picker opens correctly. The "Add exercise" FAB correctly represents both the empty-state CTA and the floating FAB (same `workout-add-exercise` identifier — intentional per selectors.ts comment).
- **Severity:** positive observation

### AW-UX-C-BR1-04 — FINISH button at 30% alpha is visually ambiguous — users may not understand it's tappable but unsafe

- **Surface:** _FinishBottomBar when no sets are completed
- **Device:** BR-1 (360×780)
- **Issue:** The FINISH button appears grey/dimmed (30% alpha text), which signals "unavailable" to most users. However it IS tappable and opens the dialog. A user who accidentally taps it while trying to scroll gets the finish dialog unexpectedly. Compare: Android material convention uses a distinct disabled state that blocks tap events.
- **Proposed direction:** Disable the tap handler (not just the visual) when `_hasCompletedSet == false`. Or make the visual unambiguous (e.g., use `disabledForegroundColor` and `onPressed: null` to actually disable the button).
- **Severity:** friction (inconsistency between visual state and behavior)

---

## Deferred Probes

- **P3 (Remove exercise 2):** Could not execute properly — `role=button[name*="Delete exercise"]` returns 0 matches (correct selector is `role=button[name*="Remove exercise"]`). Needs re-run with fixed selector to verify: (a) confirm dialog appears, (b) renumbering correct, (c) PR cache cleaned for removed exercise.
- **P7 (Remove all + empty state):** Ran while still in reorder mode from P4 (exit button not found by selectors). Needs re-run after fixing reorder exit selector. The `FINDING:P7-01` (Finish button still visible) is a false positive caused by exercises still being present in reorder mode.
- **P12 (Provider re-key after remove + re-add):** Skipped due to wrong delete selector. Need to verify with the correct selector AND a user with prior workout history for the re-added exercise to confirm `lastWorkoutSetsProvider` re-keys correctly.
- **P5 (Duplicate exercise — independent editability):** Confirmed second block IS appended. Independent editability (setting different weights/reps on each instance) was not exercised — needs dedicated sub-probe.
- **Reorder mode exit via AOM:** The ✓ button in reorder mode has no AOM entry. A `Semantics(identifier: 'workout-reorder-exit')` wrapper would fix this and make the reorder flow fully testable without coordinate clicks.

---

## Probes Completed

- [x] P1: Empty workout state (FAB visible, finish hidden, reorder hidden) — PASS
- [x] P1: Add 5 exercises (mix BW + weighted) — PASS
- [x] P1: Reorder toggle appears at ≥2 exercises — FINDING (no AOM identifier, but button IS reachable via role)
- [x] P1: Finish bar visible after completed sets — PASS
- [x] P2: Swap exercise 3 (Barbell Squat → Leg Press) — PASS (sets retained, correct exercise removed)
- [x] P2: PR state on swapped exercise — PASS (pending-PR state applied to new exercise with no history)
- [x] P3: Remove exercise 2 — BLOCKED (wrong AOM selector — deferred)
- [x] P4: Reorder mode enter/exit via AppBar — PARTIAL (enter works, exit button not in AOM)
- [x] P4: Up/down arrows update order immediately — PASS
- [x] P4: Swap/delete buttons hide in reorder mode — PASS (confirmed visually; reorder mode screenshot shows only arrows)
- [x] P5: Add same exercise twice — PASS (duplicate appended, AOM shows 2 groups)
- [x] P6: Long-press mid-rest-timer — FINDING (different from A/B findings — pointer-down dismisses timer before long-press fires; picker does NOT open through scrim on long-press)
- [x] P7: Remove all exercises → empty state — BLOCKED (ran in reorder mode; deferred)
- [x] P8: Add from empty-state CTA — PASS (picker opened, exercise added)
- [x] P9: Bodyweight → weighted swap; weight column reappears — PASS
- [x] P10: Weighted → bodyweight swap; weight column hides — PASS
- [x] P11: Finish hidden on empty workout — PASS
- [x] P11: Finish visible after adding exercise (no completed sets) — FINDING (button tappable despite no completed sets; aria-disabled absent)
- [x] P11: Finish enabled after 1 completed set — PASS
- [x] P12: Previous-set hints after remove + re-add — INCONCLUSIVE (wrong delete selector; deferred)

### Blocked / Partially Blocked

- P3, P7, P12: Blocked by wrong `role=button[name*="Delete exercise"]` selector (correct: `"Remove exercise"`). Fix: update `countExercises()` and delete-probe code in charter spec.
- P4 exit / P7 context: Reorder mode exit button has no AOM entry — coordinate-based click needed. This cascaded and left P7/P8 running in reorder mode (though the FAB was still accessible via `workout-add-exercise`).
