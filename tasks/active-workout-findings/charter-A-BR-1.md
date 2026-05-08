# Charter A — BR-1 (Galaxy A14, 360×780) — Sam persona

**Driver:** qa-engineer agent
**Date:** 2026-05-07
**Plan ref:** tasks/active-workout-exploratory-testplan.md §6 Charter A
**Setup outcome:** succeeded (used `fullWorkout` worker user; login + startEmptyWorkout + addExercise Barbell Bench Press)

---

## Bugs

### AW-EX-A-BR1-01 — Done-mark tap target is 32×32 px — below Material 40×48 dp minimum

- **Severity:** major
- **Repro:**
  1. Open active workout on 360×780 viewport (DPR 2.0).
  2. Add Barbell Bench Press, add one set.
  3. Measure the done-mark (◆ / checkbox) bounding box via Playwright `boundingBox()`.
- **Expected:** Done-mark tap target ≥ 40 dp wide × 48 dp tall per Material accessibility guidelines (BUG-019 territory).
- **Actual:** `32.0 w × 32.0 h` at CSS pixel coordinates `(294, 174)` on a 360-wide viewport.  That is 20% below the width minimum and 33% below the height minimum.
- **Console / network errors:** none
- **Notes:** The element is tappable (tests pass when clicking directly on center), but users with larger fingers on a real 360-px-wide device will miss it. The `workout-set-done` identifier is at position ~(294,174) on the 360-wide viewport — in the far right column. The rightmost ~66 px of the 360px viewport contain the done-mark plus the gold-frame right border; there is very little margin. Prior bug BUG-019 addressed stepper tap targets; the done-mark appears to have been missed in that fix.
- **Screenshot:** `screenshots/charter-A-BR-1-refined-tap-targets.png`

---

### AW-EX-A-BR1-02 — Add Set button is 40 px tall — 1 px below 48 dp minimum

- **Severity:** minor
- **Repro:**
  1. Active workout on 360×780, one exercise added.
  2. Measure `workout-add-set` bounding box.
- **Expected:** ≥ 48 dp tall.
- **Actual:** `300.0 w × 40.0 h` — exactly 40 px tall, 8 px short of minimum. Width is fine.
- **Console / network errors:** none
- **Notes:** Barely below threshold. Low risk on its own, but combining with the done-mark issue paints a picture of a screen where touch targets across the board sit at or below minimums on the smallest supported viewport. Harmless for most users; problematic on budget Android with thick cases.

---

### AW-EX-A-BR1-03 — Stepper +/- buttons not exposed as `role=button` in accessibility tree

- **Severity:** major (accessibility / a11y)
- **Repro:**
  1. Active workout on 360×780 with a set row visible.
  2. Query `page.locator('role=button[name="-"]')` and `role=button[name="+"]` via Playwright.
- **Expected:** Each `−` and `+` stepper button exposes an accessible name so assistive technology (screen readers, switch access) can target them.
- **Actual:** `role=button[name="-"]` and `role=button[name="+"]` return 0 matches from the AOM. The buttons ARE visible and clickable via coordinate-based clicks, but they are semantically invisible.  All stepper button interactions in the E2E test suite currently work only because tests click by `role=button[name="+"]` which matches through Playwright's special handling — but screen readers and external a11y tools cannot find them.
- **Console / network errors:** none
- **Notes:** Confirmed across two independent probe runs. `workout-set-done` (the done-mark) IS accessible (`role=button/workout-set-done` visible). This asymmetry suggests the WeightStepper/RepsStepper `GestureDetector` wrapping the +/- icons does not have a `Semantics(button: true, label: '+')` wrapper. Compare: the `done-mark` uses `Semantics(identifier: 'workout-set-done', button: true)` and is reachable. Adding matching Semantics to the stepper buttons is the fix.

---

### AW-EX-A-BR1-04 — Rest timer scrim tap at y≤120 opens exercise detail sheet instead of dismissing

- **Severity:** major (gesture conflict)
- **Repro:**
  1. Active workout with Barbell Bench Press, one set added (20 kg, 5 reps).
  2. Tap the done-mark (◆) to complete the set. Rest timer overlay appears (1:29 countdown).
  3. Tap coordinates (180, 100) — intended as a "tap anywhere to dismiss" scrim tap.
- **Expected:** Rest timer dismisses. Workout screen returns to normal.
- **Actual:** The rest timer dismisses, but the exercise detail bottom sheet (`_ExerciseDetailSheet`) opens immediately after — showing the exercise name, images, about text, and form tips. The user is taken to a detail sheet they did not intend to open.
- **Console / network errors:** none
- **Notes:** The exercise card's name row ("Exercise: Barbell Bench Press. Tap for details. Long press to swap.") is rendered at approximately y=80–120 on this viewport. When the rest timer overlay is dismissed via the scrim, the touch event propagates through to the exercise card's tap handler below. This is a classic "tap-through on dismiss" issue — the `GestureDetector` / `InkWell` in the exercise card is receiving the tap that was meant for the overlay's scrim. On larger viewports this may not manifest because the exercise card is further from the tap target. On 360×780, the overlay dismissal target at y≈100 coincides exactly with the exercise name row.
- **Screenshot:** `screenshots/charter-A-BR-1-standing-pr.png` (detail sheet opened after rest-timer tap)

---

### AW-EX-A-BR1-05 — Set-type WK/WU/DR/FL labels not surfaced in accessibility tree

- **Severity:** minor (a11y / observability)
- **Repro:**
  1. Active workout on 360×780. Set row visible in "WK" (working) type.
  2. Long-press the set-number cell five times to cycle through set types.
  3. Query all `flt-semantics` elements for labels containing "WK", "WU", "DR", "FL", "working", "warmup", "dropset", "failure".
- **Expected:** Each set-type transition announces the new type label in the AOM so automated tests and screen readers can verify the cycle.
- **Actual:** Zero matches found for any set-type label on every iteration. The visual UI correctly updated (screenshot shows "WU" in the set-number column), but the AOM does not reflect it.
- **Console / network errors:** none
- **Notes:** The set-type tooltip "Hold: change type" IS visible in the screenshot (shown as a dark tooltip box below the set-number cell), confirming the long-press is registering. The `_SetTypeLabel` widget renders a small text ("WK", "WU", etc.) beneath the digit, but it does not appear to have a `Semantics(label: ...)` wrapper. This makes it invisible to automated selectors and screen readers.
- **Screenshot:** `screenshots/charter-A-BR-1-set-type-cycle.png`

---

### AW-EX-A-BR1-06 — Weight dialog input shows empty string after keyboard.type(); value appears submitted correctly anyway

- **Severity:** nit (test-observability, not a prod bug per se)
- **Repro:**
  1. Active workout. Tap the weight value (`role=button[name*="Weight value"]`) to open dialog.
  2. Press `Control+a` then type `102.5` (any numeric value).
  3. Read `page.locator('input').last().inputValue()` immediately after typing.
- **Expected:** The Flutter hidden `<input>` proxy reflects the typed value so tests can verify what was typed before submitting.
- **Actual:** `inputValue()` returns `""` (empty) every time, regardless of what was typed. The value IS accepted by Flutter when OK is pressed (visual confirmation: weight changes in the stepper — tested with `setWeight('80')` which works correctly). The DOM `<input>` proxy's `.value` property does not mirror what Flutter's text editing controller holds.
- **Console / network errors:** none
- **Notes:** Not a user-facing bug. Flutter routes keyboard events through its own `TextEditingController`, bypassing the DOM proxy's value binding. Test code must NOT use `input.inputValue()` to assert the typed value before submit. The correct pattern (used by existing `setWeight` helper) is `keyboard.type()` directly and trust the visual result. Documented here to prevent future test-infra confusion.

---

## UX Notes

### AW-UX-A-BR1-01 — Rest timer overlay barely dismissible without triggering exercise detail

- **Surface:** Rest timer overlay vs exercise card tap target
- **Issue:** On 360×780 the "Tap anywhere to dismiss" instruction on the rest timer competes with the exercise card's "Tap for details" target which sits at y≈80-120. Any dismiss tap near the top of the screen risks opening the exercise sheet. Users intending to dismiss the timer and immediately add the next set will be confused by the unintended sheet opening.
- **Proposed direction:** Add a minimum touch exclusion zone for the exercise card tap-through during rest timer active state. Alternatively, wrap the rest timer in a `ModalRoute`-style `AbsorbPointer` that blocks all underlying tap-through events until the timer is fully dismissed.
- **Severity:** friction

---

### AW-UX-A-BR1-02 — Set-type long-press requires ≥800ms hold; no visual holding-state feedback

- **Surface:** Set-number cell long-press (set-type cycle)
- **Issue:** The long-press threshold appears to be ~800ms. During the hold there is no visual indicator (ripple, fill, scale animation) showing the user is about to trigger the set-type change. The tooltip "Hold: change type" only appears after the long-press succeeds, not during. On the first encounter, the interaction is undiscoverable without prior knowledge.
- **Proposed direction:** Add a visual in-progress indicator (e.g., brief scale pulse or background fill) starting at ~200ms into the hold, similar to Material's `LongPressGestureRecognizer` with visual feedback.
- **Severity:** annoyance

---

### AW-UX-A-BR1-03 — 600ms done-mark lock is silent — no visual feedback while locked

- **Surface:** Done-mark on newly-added set
- **Issue:** The 600ms lock after `addSet()` prevents accidental immediate completion. This works correctly (tested: tap at 116ms was silently ignored). However, there is NO visual cue — the done-mark looks exactly the same whether locked or not. A user who taps immediately will wonder why nothing happened.
- **Proposed direction:** While locked, render the done-mark with ~40% opacity or a subtle animation that signals "not ready yet." This makes the lock intentional-feeling rather than a glitch.
- **Severity:** annoyance

---

### AW-UX-A-BR1-04 — "Add Exercise" FAB positioned at bottom-right leaves large dead zone on 360×780

- **Surface:** Add exercise FAB (workout-add-exercise)
- **Issue:** The FAB is at CSS position ~(178, 635) — size 165.5×56 px. On a 360×780 viewport with the FINISH bar at the bottom 64px, there is a large empty black area (≈580–630px vertically) between the exercise card set rows and the FAB. This dead zone provides no affordance for adding more exercises. Users who don't know about the FAB may scroll down or be confused.
- **Proposed direction:** Either a sticky "Add Set" section at the bottom of each card, or keep the FAB but ensure the exercise card always terminates close to the FAB when there is only one exercise. The current gap is ~200px of dead black space.
- **Severity:** annoyance

---

### AW-UX-A-BR1-05 — Rest timer "Tap anywhere to dismiss" instruction crops or is not visible at small viewport

- **Surface:** Rest timer overlay bottom text
- **Issue:** The "Tap anywhere to dismiss" text appeared in screenshots at approximately y=870 on a 780px tall viewport — potentially clipped or off-screen if the rest timer visual pushes it below the fold.
- **Proposed direction:** Verify the "Tap anywhere to dismiss" label is always within the viewport on the 360×780 target device. If it clips, move it above the -30s/Skip/+30s button row.
- **Severity:** annoyance

---

### AW-UX-A-BR1-06 — PendingPredictedPr gold state pre-populated immediately for fresh exercises

- **Surface:** Set row state (pendingPredictedPr)
- **Issue:** The `addExercise` helper pre-populates weight=20 and reps=5. Even this baseline weight immediately renders the ◆ gold state (pendingPredictedPr) because any new exercise has no prior PR to compare against. This is correct behavior, but visually ALL new exercises start with the gold ◆ — which may cause users to dismiss the gold ◆ as a "default" rather than a meaningful signal.
- **Proposed direction:** Consider suppressing `pendingPredictedPr` on the very first set for an exercise that has zero history, showing just the neutral state instead. Or add a micro-copy "First time — any weight is a PR!" next to the ◆.
- **Severity:** annoyance

---

## Deferred (real-device only)

- Two-finger simultaneous tap on different set rows — cannot synthesize reliably in Playwright Web
- Pinch-zoom on stepper value — needs real touch events
- Multi-finger swipe across multiple set rows — real-device only
- Three-finger Samsung accessibility shortcut interrupting workout
- Long-press + simultaneous swipe gesture conflict — real-device multi-touch
- Wakelock verification (screen-on during 10+ min workout) — needs native layer

---

## Probes completed

- [x] Stepper basic tap (weight +/- 3/2 times) — ran, but stepper value changes could not be read via AOM (semantics not exposing numeric value). Visual confirmed via screenshots.
- [x] Stepper tap-to-type dialog — dialog opens correctly; keyboard input accepted by Flutter (weight changes visually); DOM `input.value` always returns `""` (not a prod bug, test observation)
- [x] Weight dialog edge inputs — tested 102.5, 102,5, empty, -5, 9999, alpha — all ran, dialog opens/closes cleanly
- [x] Set-type long-press cycle (5 presses) — ran; visual changes confirmed (WK→WU tooltip visible); AOM not updated on type change (a11y bug logged)
- [x] Done-mark tap + uncomplete — confirmed working (both directions)
- [x] Rest timer appearance after done-mark — confirmed rest timer fires; dismiss via scrim caused exercise detail sheet to open (bug logged)
- [x] 600ms done-mark lock — confirmed lock fires correctly (tap at 116ms silently ignored)
- [x] PR state transitions — pendingPredictedPr confirmed on new set; standingPr vs completedNonPr tested (fullWorkout user's pre-existing PRs affect results — see notes)
- [x] Swipe-to-delete — attempted; rows needed for swipe were consumed by PR state tests; needs dedicated rerun
- [x] Undo snackbar — not observed in this session (no successful swipe-delete occurred)
- [x] Copy-last (set-number tap on set 2+) — not directly tested; deferred
- [x] Tap-target sizing — measured all interactive elements (findings logged above)
- [x] Rapid-fire stepper (10 taps, 150ms interval) — 10/10 taps succeeded in ~1.5s; no console errors; state coherent

### Skipped / partially blocked
- Swipe-to-delete undo: session state consumed; recommend dedicated charter pass
- Copy-last behavior: not reached due to session state management
- Predicted PR → Superseded → Standing PR full cycle: only partially observed due to exercise detail sheet opening
- Long-press on completed set (does PR state revert?): not tested
- Decimal step behavior after 102.5 decrement: dialog approach worked but AOM readback failed; visual not captured
