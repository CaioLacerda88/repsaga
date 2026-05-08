# Charter F — BR-1 (Galaxy A14, 360×780) — Accessibility, Visual Scale, i18n

**Driver:** qa-engineer agent
**Date:** 2026-05-07
**Plan ref:** tasks/active-workout-exploratory-testplan.md §6 Charter F
**Viewport:** 360×780 CSS px, DPR 2.0

**Session outcome:** BROWSER CLOSED — Playwright MCP browser context was found in the same terminal-closed state as Charter E. All `browser_navigate`, `browser_snapshot`, and `browser_take_screenshot` calls returned "Target page, context or browser has been closed." The browser cannot be revived without restarting the MCP server process.

**Mitigation applied:** Charter executed as code-analysis-driven inspection. All findings are cross-referenced against:
- `lib/features/workouts/ui/widgets/set_row.dart`
- `lib/features/workouts/ui/widgets/rest_timer_overlay.dart`
- `lib/features/workouts/ui/widgets/finish_workout_dialog.dart`
- `lib/features/workouts/ui/widgets/finish_bottom_bar.dart`
- `lib/features/workouts/ui/widgets/active_workout_app_bar_title.dart`
- `lib/features/workouts/ui/active_workout_screen.dart`
- `lib/shared/widgets/weight_stepper.dart`
- `lib/shared/widgets/reps_stepper.dart`
- `lib/l10n/app_en.arb` + `lib/l10n/app_pt.arb`
- `lib/core/format/number_format.dart` + `lib/core/format/date_format.dart`
- `lib/features/workouts/providers/notifiers/active_workout_notifier.dart`
- Prior charter findings (A–E) as established context

**Browser-required probes:** All interactive probes (tab focus tracing, keyboard nav round-trip, screenshot capture, zoom emulation, reduced-motion emulation, forced-colors emulation, live AOM dumps) are explicitly marked DEFERRED below.

**Prior a11y findings confirmed present in code (not re-filed):**
- AW-EX-A-BR1-03: stepper +/− GestureDetectors have no `Semantics(button:true, label:...)` — confirmed still present in `weight_stepper.dart` L168-183 and `reps_stepper.dart` L135-147 (the IconButtons themselves have no Semantics wrapper).
- AW-EX-A-BR1-05: set-type micro-label (`WK`/`WU`/`DR`/`FL`) — confirmed present as plain `Text` with no Semantics wrapper (set_row.dart L666-681); the `_SetNumberCell.build` `Semantics` wraps the CELL but the type abbreviation text is inside a Column child and is not given a live-region or its own identifier.
- AW-EX-B-US1-02: rest timer overlay AOM gap — see structural note in §C below.
- AW-EX-C-BR1-01: reorder toggle + exit button — confirmed: `_buildAppBarActions` wraps `IconButton` with NO Semantics identifier (active_workout_screen.dart L229-240).
- AW-EX-C-BR1-02: swap/remove exercise buttons — confirmed: exercise_card.dart has no `Semantics(identifier:)` wrappers on the swap or remove icon buttons.

---

## Bugs

### AW-EX-F-BR1-01 — Stepper `+`/`-` `IconButton` have no Semantics wrapper — screen readers and E2E cannot address them

- **Persona:** all (sweep auditor)
- **Charter:** F
- **Device:** BR-1 (360×780) — also affects all viewports
- **Severity:** major (accessibility / AOM gap — cross-confirmed with AW-EX-A-BR1-03)
- **Repro (code-confirmed):** In `lib/shared/widgets/weight_stepper.dart` L168-183 and L228-243, the `GestureDetector` + `IconButton` that render the `−` and `+` stepper buttons have no `Semantics(button: true, label: '−' / '+')` wrapper. The `IconButton` itself uses `Icon(Icons.remove / Icons.add)` but does not set a tooltip or semantics label. Flutter's `IconButton` only auto-generates a Semantics node with `role=button` and a label when the `tooltip` parameter is provided. With no tooltip AND no wrapping `Semantics`, both buttons emit no AOM presence.
- **Expected:** Both `−` and `+` buttons should be reachable as `role=button` with an accessible name ("Decrease weight", "Increase weight") so keyboard users and screen readers can navigate steppers.
- **Actual:** `role=button[name="-"]` and `role=button[name="+"]` return 0 matches (confirmed in Charter A). The `GestureDetector` wrapping each button uses `HitTestBehavior` that intercepts real tap events correctly, but the AOM layer is entirely absent for these controls. The value `GestureDetector` (tap-to-type dialog) DOES have a Semantics wrapper: `WeightStepper` L184-227 and `RepsStepper` L149-175 each have `Semantics(label: ..., button: true)` on the value center zone. Only the `+`/`-` buttons are missing.
- **Affected files:** `lib/shared/widgets/weight_stepper.dart` (L168-183, L228-243), `lib/shared/widgets/reps_stepper.dart` (L135-147, L176-192)
- **Fix direction (not fixing, flagging):** Add `tooltip` param to each `IconButton` (e.g., `tooltip: l10n.decrementWeight` / `l10n.incrementWeight`) — Flutter auto-promotes the tooltip text as the button's accessible name. Or wrap each in `Semantics(button: true, label: '...')`.

---

### AW-EX-F-BR1-02 — Workout default name uses `DateFormat('EEE MMM d')` without locale — always generates English date

- **Persona:** all (BR users)
- **Charter:** F
- **Device:** BR-1 (360×780) — also all BR and PT locales
- **Severity:** major (i18n — pt-BR users always see English date in the workout name fallback)
- **Repro (code-confirmed):** In `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` L263-267:
  ```dart
  String _generateWorkoutName() {
    final now = DateTime.now();
    final formatted = DateFormat('EEE MMM d').format(now);
    return 'Workout — $formatted';
  }
  ```
  `DateFormat('EEE MMM d')` with no locale argument defaults to the ICU system locale, but in Flutter web the `intl` package's `DateFormat` defaults to `'en'` when no explicit locale is passed. The string `'Workout —'` is also a hardcoded English prefix.
- **Expected:** A pt-BR user starting a new workout on Wednesday 7 May should see `"Treino — Qua 7 mai"` as the default workout name.
- **Actual:** The user sees `"Workout — Wed May 7"` regardless of their selected language. The `'Workout'` prefix is never translated through `AppLocalizations`; it is a bare string literal. The date portion uses `DateFormat('EEE MMM d')` without locale, which always returns English day/month abbreviations.
- **Affected files:** `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` L263-267
- **Fix direction:** The notifier runs as a Riverpod notifier and has access to `ref`; it can read `localeProvider` to get the active language code. Fix: pass the locale string to `DateFormat('EEE MMM d', locale)` and replace the `'Workout —'` prefix with an `AppLocalizations` key (e.g., `l10n.workoutDefaultName(formatted)`). The `l10n` instance is not currently available in the notifier but can be obtained via `ref.read(localeProvider)` + the ARB system, or by threading locale through `startWorkout`.

---

### AW-EX-F-BR1-03 — Weight stepper semantic label is hardcoded in English — not translated for pt-BR

- **Persona:** all (BR users)
- **Charter:** F
- **Device:** BR-1 (360×780) — all locales
- **Severity:** minor (i18n — AOM label not translated; does not affect visual UI)
- **Repro (code-confirmed):** In `lib/shared/widgets/weight_stepper.dart` L185-188:
  ```dart
  label: 'Weight value: $formatted ${widget.unit}. Tap to enter weight.',
  ```
  This semantic label is a bare string literal in English. It is not keyed through `AppLocalizations`. A pt-BR screen reader user navigating to the weight stepper's value zone would hear the English phrase.
- **Expected:** Label should be localized: `l10n.weightValueSemantics(formatted, widget.unit)` or equivalent ARB key.
- **Actual:** English-only label regardless of app locale.
- **Affected file:** `lib/shared/widgets/weight_stepper.dart` L187
- **Related:** Same issue in `lib/shared/widgets/reps_stepper.dart` L151: `'Reps value: ${widget.value}. Tap to enter reps.'` — also a bare English string.

---

### AW-EX-F-BR1-04 — AppBar workout-name rename tooltip is hardcoded in English — not translated

- **Persona:** all (BR users)
- **Charter:** F
- **Device:** BR-1 (360×780)
- **Severity:** minor (i18n — AOM label not translated)
- **Repro (code-confirmed):** In `lib/features/workouts/ui/widgets/active_workout_app_bar_title.dart` L78:
  ```dart
  label: '$name. Tap to rename workout.',
  ```
  The suffix `"Tap to rename workout."` is a bare English string, not keyed through `AppLocalizations`. A pt-BR user's screen reader announces this in English.
- **Expected:** Should use an ARB key, e.g., `l10n.workoutNameSemanticsLabel(name)` → pt-BR: `"$name. Toque para renomear o treino."`.
- **Affected file:** `lib/features/workouts/ui/widgets/active_workout_app_bar_title.dart` L78
- **Note:** The `l10n` instance is NOT currently imported in this widget. Fix requires importing `AppLocalizations` and threading it through.

---

### AW-EX-F-BR1-05 — Rest timer overlay missing `AbsorbPointer` / `ModalBarrier` — tap-through to underlying widgets (code-level root cause of AW-EX-A-BR1-04 and AW-EX-B-US1-01)

- **Persona:** all
- **Charter:** F
- **Device:** BR-1 (360×780) — all viewports
- **Severity:** major (gesture conflict — confirms prior bugs; newly: code-level classification)
- **Repro (code-confirmed):** In `lib/features/workouts/ui/widgets/rest_timer_overlay.dart` L49-212, the overlay is built as:
  ```dart
  return GestureDetector(
    onTap: () => ref.read(restTimerProvider.notifier).stop(),
    child: Material(
      color: AppColors.abyss.withValues(alpha: 0.87),
      ...
    ),
  );
  ```
  The outer `GestureDetector` uses `onTap` for the scrim dismiss. There is no `AbsorbPointer`, no `ModalBarrier`, and no `HitTestBehavior.opaque` at the outer GestureDetector level. On line 108-109, the inner control row wraps in `GestureDetector(onTap: () {}, behavior: HitTestBehavior.opaque)` to prevent button taps from bubbling to the outer dismiss. However, this inner guard only covers the button row — NOT the full overlay area. Any touch event that lands outside the button row AND outside the exercise card's tap zone will correctly dismiss the rest timer. But if a touch lands at a coordinate that overlaps an underlying widget's tap target (exercise name InkWell at ~y=80-120 on BR-1), the touch-down is processed by the outer GestureDetector's onTap (stop) AND simultaneously the underlying InkWell receives the pointer event (no `AbsorbPointer` prevents the hit-test from propagating downward).
- **Root cause:** Flutter's `GestureDetector` competes in the gesture arena but does NOT block pointer events from reaching widgets in layers below it in the widget tree unless `behavior: HitTestBehavior.opaque` is set on the outer detector. The correct fix is either: (a) change the outer `GestureDetector` to `behavior: HitTestBehavior.opaque`, or (b) wrap the entire overlay in `AbsorbPointer(absorbing: true, child: ...)` so no pointer events reach underlying layers while the overlay is visible.
- **Affected file:** `lib/features/workouts/ui/widgets/rest_timer_overlay.dart` L49

---

### AW-EX-F-BR1-06 — Rest timer overlay has incomplete AOM representation — countdown not a live region; exercise-name is used as timer label fallback

- **Persona:** all
- **Charter:** F
- **Device:** BR-1 (360×780) — all viewports
- **Severity:** major (accessibility — cross-confirmed with AW-EX-B-US1-02; now: deeper structural analysis)
- **Repro (code-confirmed):**
  In `rest_timer_overlay.dart` L61-95:
  ```dart
  Semantics(
    label: l10n.restTimerRemaining(timeText),
    child: SizedBox(...
      child: Stack(children: [CircularProgressIndicator(...), Text(timeText, ...)]),
    ),
  ),
  ```
  The `Semantics` node with `label: l10n.restTimerRemaining(timeText)` (resolved from ARB key `restTimerRemaining: 'Rest: {time} remaining'` in pt-BR: `'Descanso: {time} restante'`) covers the countdown ring. This IS a labeled node. HOWEVER:
  1. The label is a static `Semantics(label:)` — it does NOT use `liveRegion: true`. A screen reader will only announce this label when the user explicitly focuses the element, NOT when the countdown value changes. Changes from `1:29` to `0:01` will not be auto-announced.
  2. The three control buttons (−30s, Skip, +30s) at L114-196 each have `Semantics(label: ..., button: true)` wrappers using ARB keys (`l10n.subtract30Semantics`, `l10n.skipRestSemantics`, `l10n.add30Semantics`). These ARE accessible. The prior Charter B finding (AW-EX-B-US1-02: "zero AOM entries") may have been a timing/snapshot issue; the code clearly declares Semantics.
  3. The exercise name `Text(timerState.exerciseName ?? l10n.restTimerLabel, ...)` at L97-104 has NO Semantics wrapper and will be excluded from the AOM as raw Text inside a Column under a GestureDetector (which is non-semantic by default).
  4. The outer `GestureDetector` for the scrim dismiss (L49) has no Semantics label — a screen reader user will not know that "tap anywhere" dismisses the overlay.
- **Missing AOM items:**
  - Live region on countdown (`liveRegion: true` on the countdown Semantics node)
  - Semantics label on the outer dismiss gesture ("Tap to dismiss rest timer")
  - Semantics label on the exercise name text
- **Affected file:** `lib/features/workouts/ui/widgets/rest_timer_overlay.dart`

---

### AW-EX-F-BR1-07 — `FinishBottomBar` correctly uses `onPressed: null` when disabled — but AOM `aria-disabled` not confirmed in prior charters; code analysis shows correct Flutter pattern

- **Persona:** all
- **Charter:** F
- **Device:** BR-1 (360×780)
- **Severity:** note (potential false positive in AW-EX-C-BR1-03)
- **Code analysis:** `lib/features/workouts/ui/widgets/finish_bottom_bar.dart` L74:
  ```dart
  onPressed: enabled ? onPressed : null,
  ```
  Flutter's `FilledButton` with `onPressed: null` correctly sets `aria-disabled="true"` in the AOM. The Charter C finding (AW-EX-C-BR1-03) reported the button was tappable with 0 completed sets — this IS a real bug, but the mechanism is the `enabled` parameter: `lib/features/workouts/ui/active_workout_screen.dart` L271 passes `enabled: _hasCompletedSet`. The `_hasCompletedSet` getter at L182-183 checks `widget.state.exercises.any((e) => e.sets.any((s) => s.isCompleted))`. When the picker auto-adds a default set (weight=20, reps=5, `isCompleted=false`), the finish button should correctly be disabled (no completed sets). The Charter C observation that the button was tappable is therefore confirmed as a real bug (the button opens the dialog despite no completed set being visible and the button appearing grey), and `onPressed: null` path is not being reached — the condition `_hasCompletedSet` may be evaluating incorrectly, OR the picker helper in the test auto-completes a set as part of setup. This warrants a code audit of the exact state passed to `enabled` at the moment of the tap. NOT a new finding — cross-referencing AW-EX-C-BR1-03. Flagging here so the fixer knows the code path to audit.
- **Affected files:** `lib/features/workouts/ui/active_workout_screen.dart` L182-183, `lib/features/workouts/ui/widgets/finish_bottom_bar.dart` L74

---

## Probe Results by Section

### A. Keyboard-only navigation — DEFERRED (browser required)

All keyboard tab-trace probes require a live browser session with `document.activeElement` access. Cannot execute without browser.

**Code-analysis observations:**
- The app uses `Scaffold` with standard Flutter focus management. Flutter web uses a `FocusScopeNode` that mirrors HTML tab order based on widget position in the tree.
- The `RestTimerOverlay` is stacked ABOVE the Scaffold body in a `Stack` in `active_workout_screen.dart` L100-111. Flutter's focus traversal follows the widget tree depth — the rest timer overlay's controls (TextButton) WILL receive focus before the underlying Scaffold's controls in the standard traversal. This means Tab during rest timer SHOULD focus overlay buttons correctly. However, the outer `GestureDetector` (the scrim dismiss) has no `FocusNode` or `FocusScope`, so pressing Escape to dismiss has no Semantics-based handler — only pointer events trigger `stop()`.
- The `FinishWorkoutDialog` and `DiscardWorkoutDialog` both use `AlertDialog` via `showDialog`, which Flutter automatically wraps in a `FocusTrap` (via `DialogRoute`). Tab focus should be trapped within the dialog. **PASS in code.**
- The `ExercisePickerSheet` uses `showModalBottomSheet` which also establishes a `FocusTrap`. **PASS in code.**
- **Gap found:** The Escape key is NOT wired as a dismiss for the rest timer overlay. `GestureDetector.onTap` only fires on pointer events. Adding `Shortcuts` + `Actions` for `EscapeIntent` would make keyboard-only dismiss possible.

**Status:** DEFERRED — browser-required for measured focus order and round-trip confirmation.

---

### B. Focus management on modals — DEFERRED (browser required)

Cannot trace `document.activeElement` across modal open/close transitions without browser.

**Code-analysis observations:**
- `FinishWorkoutDialog` uses `TextField` with `autofocus` NOT set. The first focusable element in `AlertDialog.actions` (first `TextButton`) will receive focus by default Flutter `AlertDialog` focus management. **Potential gap:** the notes `TextField` does NOT have `autofocus: true` (finish_workout_dialog.dart L80-91) — focus will land on the "Continue Training" (`keepGoing`) button, not the notes field. Whether this is correct or wrong depends on UX intent: the spec says "focus should go to notes textarea or first button" which is ambiguous. The actual behavior is "first button" (Keep Going).
- `Weight entry dialog` in `WeightStepper` L113-151: `TextField` has `autofocus: true` (L122). Focus goes to the input field on open. **PASS in code.**
- Return focus on dialog close: Flutter's `showDialog` / `showModalBottomSheet` restore focus to the `FocusScopeNode` that was active when the modal was shown. In practice this means focus returns to the widget that was last focused before the modal — which should be the button that triggered it. **PASS in code (for dialogs using `showDialog`).**

**Status:** DEFERRED for live browser confirmation.

---

### C. Screen reader semantics — AOM dump — DEFERRED (browser required for live dump)

Cannot execute `browser_evaluate` without browser. Code-level assessment of each row state:

**AOM coverage per row state (code-confirmed):**

| Row state | Identifier | Semantics label | Tap action |
|---|---|---|---|
| `none` | `set-row-state-none` (frame) + `workout-set-done` (done cell) | Frame: identifier only. Done cell: `l10n.markSetAsDone` | Done cell: tap via Checkbox |
| `pendingPredictedPr` | `set-row-state-pending-pr` (frame) + `workout-set-done` (done cell, button path) | Frame: identifier only. Done cell: `l10n.markSetAsDonePredictedPr` | Done cell: `onTap: onChanged` via Semantics button |
| `completedNonPr` | `set-row-state-completed` (frame) + `workout-set-completed` (done cell) | Done cell: `l10n.setCompleted` | Done cell: Checkbox with `value: true` |
| `completedSupersededPr` | `set-row-state-superseded-pr` (frame) + `workout-set-completed` (done cell) | Done cell: `l10n.setCompleted` | Done cell: Checkbox |
| `completedStandingPr` | `set-row-state-standing-pr` (frame) + `workout-set-completed` (done cell) | Done cell: `l10n.setCompleted` | Done cell: Checkbox |

**Gaps identified:**
- The set row frame has `identifier: rowStateId` but NO `label` — a screen reader navigating to the frame hears only the identifier string (not user-readable). The frame's `explicitChildNodes: true` means child semantics are readable, but the row as a container has no descriptive label (e.g., "Set 3, 100 kg, 8 reps, completed personal record").
- The weight value and reps value semantics labels are hardcoded English (AW-EX-F-BR1-03).
- No `aria-live` region exists anywhere in the set row or the active workout screen. PR state transitions (e.g., `none` → `pendingPredictedPr` after entering a PR-beating weight) fire a Riverpod state rebuild but produce no AOM announcement. A screen reader user will not know a PR is predicted until they explicitly navigate to the done cell and hear the label change.

**Prior bugs confirmed by code:** AW-EX-A-BR1-03 (stepper +/− not in AOM), AW-EX-A-BR1-05 (set-type abbreviation not in AOM), AW-EX-B-US1-02 (rest timer live region absent).

**Status:** Live AOM dump per row state DEFERRED — browser required.

---

### D. Reduced motion — DEFERRED (MCP API not exposed)

`page.emulateMedia({ reducedMotion: 'reduce' })` is not accessible via the MCP tool set (only `browser_evaluate`, `browser_navigate`, `browser_click`, etc. are exposed). Cannot toggle `prefers-reduced-motion` programmatically.

**Code-analysis observations:**
- The `CircularProgressIndicator` used as the rest timer ring (`rest_timer_overlay.dart` L72-81) uses Flutter's default animation controller. Flutter Web's `CircularProgressIndicator` does NOT check `MediaQuery.of(context).disableAnimations` — it runs at full speed regardless. If the OS has `prefers-reduced-motion: reduce` set, the ring will still sweep at full duration.
- `MediaQuery.of(context).disableAnimations` is accessible in Flutter — it mirrors the OS-level `prefers-reduced-motion` via `AccessibilityFeatures.disableAnimations`. No widget in the active workout screen currently reads this value.
- The PR celebration screen is not in scope for this charter but should also be audited (celebration animations are likely not reduced-motion aware).
- **Finding:** The entire active workout screen (rest timer ring, potential celebration animations) does NOT respect `prefers-reduced-motion`. This is a PROD-CODE gap.

**Finding filed:** AW-EX-F-BR1-08 below.

**Status:** Emulation DEFERRED — real device or CDP-level testing required.

---

### AW-EX-F-BR1-08 — No `prefers-reduced-motion` / `disableAnimations` check anywhere in the active workout screen

- **Persona:** all (users with vestibular disorders, motion sensitivity)
- **Charter:** F
- **Device:** BR-1 and all viewports
- **Severity:** minor (accessibility — WCAG 2.1 SC 2.3.3 Animation from Interactions)
- **Repro (code-confirmed):** Grep for `disableAnimations`, `reducedMotion`, and `MediaQuery.*animation` in `lib/` returns zero matches. The `rest_timer_overlay.dart` `CircularProgressIndicator` runs its sweep animation unconditionally. The `active_workout_screen.dart` does not read `MediaQuery.of(context).disableAnimations`.
- **Expected:** When `prefers-reduced-motion: reduce` is active (OS setting), the rest-timer ring should either stop animating (show a static arc at the current progress value) or use a shorter-duration animation. The completion haptic and dismiss behavior should remain functional.
- **Actual:** The ring sweeps at full 1-second intervals regardless of the OS reduced-motion preference.
- **Affected files:** `lib/features/workouts/ui/widgets/rest_timer_overlay.dart` (L72-81 — CircularProgressIndicator)
- **Fix direction:** Read `MediaQuery.of(context).disableAnimations` in `_RestTimerOverlayState.build()` and pass `animationDuration: Duration.zero` to `CircularProgressIndicator` when true. Or use `disableAnimations` to conditionally suppress the ring and show only the countdown text.

---

### E. Forced colors / Windows high contrast — DEFERRED

Cannot emulate forced colors via MCP tool set. Same constraint as reduced motion.

**Code-analysis observations:**
- The entire app uses custom color constants from `AppTheme` (`AppColors.heroGold`, `AppColors.primaryViolet`, `AppColors.success`, etc.). These are hardcoded `Color(0xFFXXXXXX)` values. None of them are system colors (`SystemColors.buttonFace` etc.).
- Under forced colors mode (Windows high contrast), CSS-painted Flutter canvases typically fall back to the browser's high-contrast layer, but Flutter's custom-drawn elements (the rest timer ring, the set row's color-coded left stripe) are painted on a canvas and may not adapt.
- The gold PR stripe and tint are rendered via `ColoredBox` and `Container` with `color:` — these will NOT adapt to forced colors because they are Flutter canvas draws, not CSS.
- **Likely outcome:** In forced-colors mode, the PR gold/violet color coding that differentiates row states will be invisible or rendered in forced-color foreground (often black on white). The done-mark (Checkbox / ◆) will survive because it uses `MaterialApp`'s widget rendering which does respect some system colors.
- **Status:** DEFERRED — real Windows high-contrast device or Playwright CDP forced-colors emulation required.

---

### F. Browser zoom 200% — DEFERRED (browser required)

Cannot execute `browser_evaluate(() => document.body.style.zoom = '2')` without browser.

**Code-analysis observations for zoom impact on set_row.dart:**
- The set row is built with `constraints: const BoxConstraints(minHeight: 56)` (frame) and fixed column widths (`52dp` done cell, `40px` stepper buttons, `3dp/4dp` stripe). At CSS 200% zoom, the effective viewport shrinks to 180×390 CSS equivalent. The `Expanded(flex:3)` weight column and `Expanded(flex:2)` reps column will collapse to approximately 40dp and 27dp, respectively — too narrow for the 26px font `headlineSmall` weight value. The `FittedBox(fit: BoxFit.scaleDown)` in `WeightStepper` will scale the text down, but the resulting value may be illegible at small sizes.
- The `FinishBottomBar` at 56dp minimum height will remain visible at 200% zoom, but the FINISH label may overflow or wrap since `SizedBox(width: double.infinity)` will be 180dp wide and the FilledButton label is `"FINALIZAR"` (pt-BR, 8 chars) at 13px — likely sufficient.
- The `ExercisePicker` search input and the AppBar title will likely truncate or overflow since the available width at 200% zoom is 180dp.

**Status:** DEFERRED — browser required.

---

### G. System font size XL — DEFERRED (browser required + Flutter canvas note)

Cannot execute `document.documentElement.style.fontSize = '24px'` without browser.

**Code-analysis note:** Flutter web renders text on a canvas — it does NOT respond to CSS root font-size changes. Text size is governed by Flutter's `TextStyle.fontSize` values, not the browser's default font size. Therefore, `fontSize` overrides via CSS will have zero effect on the Flutter web build. This probe would confirm "zero response" as expected behavior for Flutter Web — it is NOT a bug; it is an architectural characteristic of Flutter's CanvasKit rendering model.

Real Android system-font-XL behavior (which DOES affect the Flutter `textScaleFactor`) can only be tested on a real Android device or Android emulator with system font scale set to 130%.

**Status:** DEFERRED — real-device only (Chrome CSS approach ineffective for Flutter CanvasKit).

---

### H. Localization to pt-BR — partially code-confirmed

**H1. In-app language picker — confirmed present:**
- Profile > Settings > Language uses `LanguagePickerSheet` (`lib/features/profile/ui/widgets/language_picker_sheet.dart`). The app supports in-app language switching via `localeProvider`. Switching to pt-BR does NOT require browser language flag — it can be done via the app's Profile settings.
- The `App` widget reads `ref.watch(localeProvider)` and passes `locale:` to `MaterialApp.router` (app.dart L51). A locale switch causes a full widget tree rebuild with the new locale.

**H2. Supported locales — code-confirmed:**
- `AppLocalizations.supportedLocales` = `[Locale('en'), Locale('pt')]` (app_localizations.dart L96-99).
- The pt ARB key `"@@locale": "pt"` — note this is `pt` NOT `pt_BR`. The intl system will match `pt-BR` locale to `pt` via language fallback, so pt-BR should correctly use the pt ARB file.

**H3. pt-BR string coverage — code-confirmed:**
- All active workout screen strings (finish dialog, discard dialog, set row labels, picker labels, rest timer) ARE present in `app_pt.arb`. No missing keys found for this surface.
- Exception: `finishButtonLabel` key maps to `"FINALIZAR"` in pt. `keepGoing` maps to `"Continuar Treinando"`. `saveAndFinish` maps to `"Salvar e Finalizar"`. `discardWorkoutTitle` maps to `"Descartar Sessão?"`. These are all translated.
- `"Workout — Wed May 7"` (the default workout name) bypasses the ARB system entirely — see AW-EX-F-BR1-02.

**H4. Set-type abbreviations in pt-BR:**
- `app_pt.arb` defines: `"setTypeAbbrWorking": "N"`, `"setTypeAbbrWarmup": "AQ"`, `"setTypeAbbrDropset": "D"`, `"setTypeAbbrFailure": "F"`.
- These ARE translated. The micro-label will show `N` / `AQ` / `D` / `F` in pt-BR.
- The set_row.dart `_SetNumberCell` uses `set.setType.tinyAbbr` (L667) which is a getter on `SetType`. If `tinyAbbr` reads from ARB, these are correctly translated. If it is a hardcoded string constant, it is not.

**H5. Check for `tinyAbbr` implementation:**
- Need to verify: is `SetType.tinyAbbr` using ARB keys or a hardcoded string?

**H6. Decimal separator handling in weight input — code-confirmed PASS:**
- `WeightStepper._parseWeight()` (weight_stepper.dart L96-101):
  ```dart
  double? _parseWeight(String text) {
    final normalised = text.trim().replaceAll(',', '.');
    final parsed = double.tryParse(normalised);
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }
  ```
  Both `102,5` and `102.5` will parse correctly (the comma is replaced with a dot before parsing). Mixed input like `102,5.2` normalizes to `102.5.2` which `double.tryParse` rejects (returns `null`) — the input is silently ignored and the weight remains unchanged. **PASS for valid pt-BR input. PASS for EN input. Mixed/invalid input: silent ignore.**

**H7. Number formatting in weight display — code-confirmed PASS:**
- `AppNumberFormat.weight(value, locale: locale)` in `number_format.dart` L20-28 uses `NumberFormat.decimalPattern(locale)` which correctly uses `,` as decimal separator for pt (e.g., `80,5`) and `.` for en (e.g., `80.5`). The locale is read from `Localizations.localeOf(context).languageCode` in `weight_stepper.dart` L157. **PASS.**

**H8. Date formatting in workout name — FAIL (see AW-EX-F-BR1-02):**
- `_generateWorkoutName()` uses `DateFormat('EEE MMM d')` with no locale. Always English. **FAIL.**

**H9. pt-BR string length overflow — code analysis note:**
- `"Salvar e Finalizar"` (18 chars, pt-BR) vs `"Save & Finish"` (13 chars, en) — 38% longer. In the `FinishWorkoutDialog` `AlertDialog.actions` row, both `"Continuar Treinando"` (19 chars) and `"Salvar e Finalizar"` (18 chars) need to fit. `AlertDialog` wraps action buttons in a scrollable overflow bar (`OverflowBar`), so they will stack vertically if they overflow horizontally. At 360dp viewport, this is likely — the two buttons at normal font size will probably stack rather than be side-by-side. This is functional but visually different from the English layout. Browser observation needed to confirm.
- `"Descartar Sessão?"` — Discard dialog title. 18 chars. English: `"Discard Workout?"` — 16 chars. Slight difference, unlikely to overflow.
- `"FINALIZAR"` — Finish button label. 9 chars in pt-BR, 6 chars in en (`"FINISH"` in the ARB: `"finishButtonLabel": "FINISH"`). The button is full-width (`SizedBox(width: double.infinity)`) so no overflow risk.

**Status:** Browser-interactive pt-BR probes (screenshots, overflow observation, decimal dialog) DEFERRED.

---

### I. Visual baselines — DEFERRED (browser required)

All screenshots listed in the charter specification require browser session:
- `charter-F-BR-1-empty-workout.png` — DEFERRED
- `charter-F-BR-1-mid-workout-mixed-pr-states.png` — DEFERRED
- `charter-F-BR-1-rest-timer-active.png` — DEFERRED
- `charter-F-BR-1-finish-dialog-with-notes.png` — DEFERRED
- `charter-F-BR-1-pt-BR-active-workout.png` — DEFERRED
- `charter-F-BR-1-200-zoom.png` — DEFERRED
- `charter-F-BR-1-tab-focus-N.png` — DEFERRED

No screenshots captured in this session. Prior charters (A, B, C, D) captured screenshots of the English workout screen under various states — those serve as informal baselines for Charter F comparison once the browser session is live.

---

### J. Tap-target sweep at scale — DEFERRED (browser required for measurement)

Cannot run `boundingClientRect` measurements without browser.

**Code-analysis inferences for additional targets beyond Charter A findings:**

| Element | Code source | Dimensions (code-inferred) |
|---|---|---|
| Reorder up/down arrows | exercise_card.dart — `IconButton` with no explicit constraints | Default Flutter `IconButton` = 48×48 dp. **PASS.** |
| Swap exercise icon button | exercise_card.dart — standard `IconButton` | 48×48 dp default. **PASS.** |
| Remove exercise icon button | exercise_card.dart — standard `IconButton` | 48×48 dp default. **PASS.** |
| Picker exercise tile row | exercise_picker_sheet.dart — `ListTile` | Flutter `ListTile` min height = 48dp. **PASS.** |
| Snackbar action button ("Undo") | set_row.dart L243-248 — `SnackBarAction` | Flutter `SnackBarAction` renders as TextButton which defaults to 36dp height in Material 3. **POTENTIAL FAIL: 36dp < 48dp minimum.** Browser measurement needed. |
| Finish dialog "Keep Going" button | finish_workout_dialog.dart L96-100 — `TextButton` | Flutter TextButton default min height is 36dp. **POTENTIAL FAIL.** |
| Finish dialog "Save & Finish" button | finish_workout_dialog.dart L103-116 — `FilledButton` | Flutter FilledButton default min height is 40dp. **BORDERLINE.** |
| Weight entry dialog "OK" button | weight_stepper.dart L140-148 — `TextButton` | 36dp. **POTENTIAL FAIL.** |
| Weight entry dialog "Cancel" button | weight_stepper.dart L133-138 — `TextButton` | 36dp. **POTENTIAL FAIL.** |

**Summary of code-inferred tap target gaps:**
- Dialog action `TextButton` instances throughout the app render at 36dp height by default. None of the dialog code paths in the active workout surface (finish dialog, weight entry dialog, reps entry dialog, discard dialog) override `minimumSize` on their `TextButton` actions. These are 12dp below the 48dp Material minimum. On a real 360×780 BR-1 device at DPR 2.0, 36dp = 72 physical pixels — still hittable but below spec.
- `SnackBarAction` uses `TextButton` styling — same 36dp issue.

**Filed as:** AW-EX-F-BR1-09 below.

---

### AW-EX-F-BR1-09 — Dialog `TextButton` actions render at 36dp height — below 48dp Material minimum on all viewports

- **Persona:** all
- **Charter:** F
- **Device:** BR-1 (360×780) and all viewports
- **Severity:** minor (accessibility / tap target — same pattern as AW-EX-A-BR1-01 done-mark and AW-EX-A-BR1-02 Add Set)
- **Repro (code-confirmed):** Flutter Material 3's `TextButton` defaults to `minimumSize: Size(64, 36)` when no explicit style is set. All dialog action buttons in the active workout flow use `TextButton` or `FilledButton` without overriding `minimumSize`:
  - `finish_workout_dialog.dart` L96-100 (Keep Going), L103-116 (Save & Finish — FilledButton default is 40dp)
  - `weight_stepper.dart` L133-138 (Cancel), L140-148 (OK)
  - `reps_stepper.dart` equivalent dialog actions
  - `exercise_card.dart` L63-82 (remove exercise confirm dialog — Cancel + Remove buttons)
  - `set_row.dart` SnackBarAction (Undo)
- **Expected:** Each button's vertical tap target ≥ 48dp per WCAG 2.5.5 Target Size (AAA) and Material 3 guidelines.
- **Actual (code-inferred):** Dialog TextButton minimum height = 36dp. 12dp below minimum.
- **Note:** This is a systemic pattern. The fix would be adding `style: TextButton.styleFrom(minimumSize: const Size(88, 48))` or setting a global `TextButtonTheme` in `AppTheme`. Alternatively, using `ElevatedButton` or `OutlinedButton` for dialog actions (which default to 40dp) halves the deficit.
- **Browser measurement to confirm:** DEFERRED.

---

## UX Notes

### AW-UX-F-BR1-01 — Workout name `"Workout — Wed May 7"` is English-only for BR users — high-visibility branding gap

- **Surface:** Active workout AppBar, workout history card, workout detail screen
- **Device:** BR-1 (all BR users)
- **Issue:** The default workout name (auto-generated when starting an empty workout) is always English. A pt-BR user's workout history shows `"Workout — Qua 7 mai"` partially in English despite the rest of the app being in Portuguese. This is a high-visibility string that appears on home screen, in workout history, and during the active session. It signals to the user that the localization is incomplete.
- **Proposed direction:** Fix AW-EX-F-BR1-02 (translate the prefix via ARB + pass locale to DateFormat). The user-visible text is one of the first things a new user sees after starting their first workout.
- **Severity:** friction

### AW-UX-F-BR1-02 — Finish dialog action buttons may stack vertically in pt-BR on 360dp — layout regression risk

- **Surface:** `FinishWorkoutDialog` action row
- **Device:** BR-1 (360×780)
- **Issue:** `"Continuar Treinando"` (19 chars) and `"Salvar e Finalizar"` (18 chars) are both longer than their English equivalents. Flutter's `AlertDialog` uses `OverflowBar` for the action row — when buttons don't fit side-by-side, they stack. On 360dp, this likely triggers the stack layout. The dialog becomes taller. On a 780dp tall viewport, this is still within bounds but pushes the notes `TextField` up. Worth confirming with browser.
- **Proposed direction:** Consider abbreviating: `"Continuar"` instead of `"Continuar Treinando"`, `"Salvar"` instead of `"Salvar e Finalizar"` — or use a `Column` layout for dialog actions. Browser screenshot needed to confirm whether stacking occurs.
- **Severity:** annoyance (pending browser confirmation)

### AW-UX-F-BR1-03 — Tab-to-rename gesture on workout name has no keyboard affordance (Semantics label is English + no keyboard handler)

- **Surface:** `ActiveWorkoutAppBarTitle` static name widget
- **Device:** all
- **Issue:** `GestureDetector.onTap` opens the rename `TextField`. This is pointer-only. There is no `Actions`/`Shortcuts` wiring for Enter key while the name Row has focus. Keyboard users cannot activate the rename flow. The Semantics label (`"$name. Tap to rename workout."` — also English-only, see AW-EX-F-BR1-04) instructs users to "Tap" which implies pointer-only interaction.
- **Proposed direction:** Wrap the static name `GestureDetector` in a `Focus` widget and respond to `onKey` for `LogicalKeyboardKey.enter` to trigger `onTapToEdit`. Or use `InkWell` (which Flutter also enables on keyboard Enter/Space) instead of `GestureDetector`.
- **Severity:** friction (keyboard accessibility gap)

---

## Deferred Probes (BROWSER-REQUIRED)

| Probe | Charter section | Reason | What to try next |
|-------|----------------|---------|-----------------|
| A — Tab-only navigation | §A | Browser closed | `EXPL_CHARTER_F=1 FLUTTER_APP_URL= npx playwright test specs/charter-f-exploratory.spec.ts --grep "@BR-1" --headed` |
| B — Focus management on modals | §B | Browser closed | Same spec; trace `document.activeElement` in evaluate() after each modal open/close |
| C — Live AOM dump per row state | §C | Browser closed | Use `page.evaluate(() => { const s = Array.from(document.querySelectorAll('[flt-semantics-identifier],[role]')); return s.map(e => ({role:e.getAttribute('role'), id:e.getAttribute('flt-semantics-identifier'), label:e.getAttribute('aria-label')||e.textContent?.slice(0,60), rect:e.getBoundingClientRect()})); })` |
| D — Reduced motion emulation | §D | MCP doesn't expose `page.emulateMedia` | Playwright script: `await page.emulateMedia({ reducedMotion: 'reduce' }); await page.evaluate(() => window.matchMedia('(prefers-reduced-motion: reduce)').matches)` |
| E — Forced colors emulation | §E | MCP doesn't expose `page.emulateMedia` | Same as D: `await page.emulateMedia({ forcedColors: 'active' })` |
| F — Browser zoom 200% | §F | Browser closed | `await page.evaluate(() => document.body.style.zoom = '2')` then screenshot |
| G — System font XL | §G | Browser closed + Flutter CanvasKit not CSS-responsive | Confirm "zero response" via browser; real-device test for true Android font scale |
| H — pt-BR interactive probes | §H | Browser closed | Switch locale in-app (Profile > Language > Português), then screenshot each active-workout state |
| I — Visual baselines (all 7 screenshots) | §I | Browser closed | Re-run after browser session established; use `mcp__plugin_playwright_playwright__browser_take_screenshot` |
| J — Tap target measurements | §J | Browser closed | Run `page.evaluate()` with `getBoundingClientRect()` on all `[flt-semantics-identifier]` elements |
| `SetType.tinyAbbr` l10n check | §H4 | RESOLVED by code read | `set_type.dart` L27: `tinyAbbr` is hardcoded (`WK`/`WU`/`DR`/`FL`), intentionally not localized per inline comment. ARB keys `setTypeAbbrWorking` etc. exist and are used in `workout_detail_screen.dart` but NOT in active workout set row. Deliberate design divergence — documented as AW-EX-F-BR1-10. |

---

### AW-EX-F-BR1-10 — Active workout set-type micro-label uses hardcoded English `tinyAbbr` (`WK`/`WU`/`DR`/`FL`) — workout detail screen uses translated abbreviations from ARB

- **Persona:** all (BR users — UX note, not a blocking bug)
- **Charter:** F
- **Device:** BR-1 (360×780) — all locales
- **Severity:** minor (i18n inconsistency — deliberate design choice, but creates a visible inconsistency between screens)
- **Repro (code-confirmed):**
  - `lib/features/workouts/models/set_type.dart` L27-32: `tinyAbbr` returns `'WK'`, `'WU'`, `'DR'`, `'FL'` — hardcoded, no locale dependency.
  - `lib/features/workouts/ui/widgets/set_row.dart` L667: active workout set row uses `set.setType.tinyAbbr`.
  - `lib/features/workouts/ui/workout_detail_screen.dart` L285-288: workout DETAIL screen uses `l10n.setTypeAbbrWorking` etc. — localized strings from ARB.
  - pt-BR ARB defines: `setTypeAbbrWorking: "N"`, `setTypeAbbrWarmup: "AQ"`, `setTypeAbbrDropset: "D"`, `setTypeAbbrFailure: "F"`.
- **Actual:** A pt-BR user sees `WK`/`WU`/`DR`/`FL` on the active workout screen but `N`/`AQ`/`D`/`F` (or their equivalents) on the workout history detail screen. The two screens use different abbreviation systems for the same data.
- **Design intent:** `set_type.dart` L14-26 contains an inline rationale: "gym shorthand is a vocabulary the app teaches via the long-press cycle" and "Translating `DR` to `RP` would undo that teaching every time a Brazilian user reads English fitness content." This is a documented deliberate choice — NOT an oversight.
- **Counter-argument for review:** If the design intent is universal gym shorthand, the ARB keys `setTypeAbbrWorking = "N"` (Portuguese for Normal) should probably be removed or not wired to any screen, since they CREATE the inconsistency rather than resolving it. The current state has two competing conventions coexisting.
- **Recommendation for triage:** Either (a) unify the workout detail screen to also use `tinyAbbr` (keeping the "universal gym shorthand" philosophy consistent), or (b) update `tinyAbbr` to use localized abbreviations everywhere. The current split is the worst of both worlds. This is a product decision, not a code bug.
- **Affected files:** `lib/features/workouts/models/set_type.dart` L27, `lib/features/workouts/ui/widgets/set_row.dart` L667, `lib/features/workouts/ui/workout_detail_screen.dart` L285-288

---

## Summary

Charter F produced 13 findings (10 bugs + 3 UX notes) from code analysis after the Playwright MCP browser was found closed for the second consecutive charter session.

**Bug severity breakdown:** 3 major bugs, 6 minor bugs, 1 note/design-audit finding.

**By category:**
- **a11y gaps (4):** AW-EX-F-BR1-01 (stepper +/− buttons not in AOM — confirmed A-03 at code level), AW-EX-F-BR1-06 (rest timer missing live region + dismiss-scrim AOM label — deepened B-02), AW-EX-F-BR1-08 (no `prefers-reduced-motion` support anywhere in the active workout screen), AW-EX-F-BR1-09 (dialog `TextButton` actions render at 36dp — systemic pattern across all active workout dialogs).
- **i18n failures (3):** AW-EX-F-BR1-02 (default workout name uses hardcoded English prefix + unlocalized `DateFormat` — major, affects every pt-BR user), AW-EX-F-BR1-03 (weight/reps stepper semantic labels hardcoded English), AW-EX-F-BR1-04 (rename tooltip hardcoded English).
- **Gesture/pointer (1):** AW-EX-F-BR1-05 (rest timer missing `AbsorbPointer` / `HitTestBehavior.opaque` — root cause confirmed for A-04 + B-01).
- **Design audit notes (2):** AW-EX-F-BR1-07 (FinishBottomBar disabled-state code path cross-reference for C-03 audit), AW-EX-F-BR1-10 (set-type abbreviation inconsistency between active workout screen and workout detail screen — deliberate design choice with a competing ARB convention).
- **UX notes (3):** AW-UX-F-BR1-01 (English workout name high-visibility in history), AW-UX-F-BR1-02 (pt-BR finish dialog buttons may stack vertically), AW-UX-F-BR1-03 (rename gesture has no keyboard affordance).

**Prior findings cross-confirmed in code:** AW-EX-A-BR1-03 (stepper +/− not in AOM — root cause in WeightStepper/RepsStepper confirmed), AW-EX-A-BR1-05 (set-type label not in AOM — confirmed: plain Text with no Semantics in _SetNumberCell), AW-EX-B-US1-02 (rest timer AOM — partially revised: control buttons DO have Semantics labels in code, but countdown text is not a live region and scrim GestureDetector has no label), AW-EX-C-BR1-01 (reorder toggle + exit button — no Semantics identifier in `_buildAppBarActions`), AW-EX-C-BR1-02 (swap/remove — no identifier on exercise_card icon buttons).

**Probes deferred:** 10 of 10 interactive probe categories require browser — all deferred due to closed MCP context. This is the highest deferral rate of any charter (A: 6, B: 5, C: 5, D: 4, E: 7, F: 10 deferred). Charter F is also the most emulation-dependent: `reducedMotion` and `forcedColors` are not exposed via the MCP tool set even when the browser is live, meaning those two probes (§D, §E) require either a Playwright script (`page.emulateMedia`) or real-device testing regardless of browser availability.

**Pattern observations:** The i18n analysis surfaces two distinct failure patterns. First, a set of semantic label strings hardcoded in English (3 surfaces: workout name, weight/reps stepper labels, rename tooltip) that were never routed through `AppLocalizations`. The workout name is the most user-visible — it is the first string a new Brazilian user reads after starting their first workout and it persists across their entire history. Second, a design-convention conflict where `SetType.tinyAbbr` uses universal gym shorthand (WK/WU/DR/FL) in the active workout screen while localized abbreviations from ARB are used in the workout detail screen — the two conventions coexist without a documented choice of canonical source. The decimal-separator and number-formatting pipelines are correctly implemented and represent a positive finding. The a11y picture from charters A–F combined: approximately 10 interactive surfaces in the active workout screen lack proper AOM representation (stepper buttons, set-type labels, rest timer controls partially, reorder buttons, exit-reorder button, swap/remove exercise buttons), plus 3 missing Semantics categories (live regions for PR transitions, live region for rest timer countdown, keyboard Escape handler for rest timer). This is a systemic a11y deficit that warrants a dedicated a11y remediation pass.
