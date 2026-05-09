# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `PLAN.md` step or backlog entry, check items off
as work lands, and remove the section after the merge condenses to PLAN.md.

---

## fix/workouts-a11y-i18n-combined — Family 3 + 6 (11 bugs)

Per `tasks/active-workout-implementation-plan.md` §554 (Combine recommendation),
§161 (Family 3) and §378 (Family 6). Combining because both touch the same
widgets (steppers, AppBar title, rest timer, set-row, exercise card).

**Bugs covered (11):**
- Family 3 a11y: AW-EX-A-BR1-03, AW-EX-A-BR1-05, AW-EX-B-US1-02,
  AW-EX-C-BR1-01, AW-EX-C-BR1-02, AW-EX-F-BR1-01, AW-EX-F-BR1-06
- Family 6 i18n: AW-EX-F-BR1-02, AW-EX-F-BR1-03, AW-EX-F-BR1-04, AW-EX-F-BR1-10

**Triage decisions (made up-front):**
- liveRegion: `true` on countdown — simplest correct contract; cadence-shaping
  is premature optimization. Revisit if a screen-reader user reports excess
  chatter.
- ARB coverage: en + pt — both updated in this PR. Standard for the repo.
- Workout name locale: read at GENERATION TIME via `localeProvider`, persist
  thereafter. Matches plan's stated intent (the existing comment block at
  `active_workout_notifier.dart:259-262` codifies "stored data, not
  display-only" — the fix doesn't violate that, it just stops hardcoding `en`).
- Set-type abbreviation (Path A vs Path B): **Path A.** Active workout adopts
  the canonical localized abbreviations already used by `workout_detail_screen`.
  Raw English `WK/WU/DR/FL` on a pt-BR session is the bug; the localized
  `setTypeAbbr*` ARB keys already exist and `workout_detail_screen.dart:285-288`
  consumes them. Updating `set_row.dart:667` to do the same removes a
  product-decision split, not creates one.

### Checklist

**Implementation (tech-lead, TDD per CLAUDE.md):**
- [x] Step 1 — Steppers (smallest diff)
  - [x] Add `Semantics(button: true, label: l10n.decrementWeight)` (et al)
        wrapping the +/− GestureDetector chain — chose explicit Semantics
        over `IconButton.tooltip:` because the existing
        `GestureDetector(onLongPressStart: _startRepeating)` lives between
        Tooltip's gesture arena and the IconButton; tooltip injection would
        risk capturing the long-press. Localize the existing
        `Semantics(label: ...)` at `:187` / `:151` via
        `l10n.weightValueSemantics(formatted, unit)` /
        `l10n.repsValueSemantics(value)`. (Family 6 overlap.)
  - [x] **Risk verified:** widget tests pin (a) `find.bySemanticsLabel` for
        the localized labels in en + pt, (b) `tester.longPress` still fires
        `onChanged` at least once, (c) the structural pin that the
        GestureDetector(onLongPressStart) survives the wrap. All green.
- [x] Step 2 — Set-type micro-label
  - [x] Parent `setNumberSemantics` already takes a type placeholder
        (`set.setType.localizedName(l10n)`) — no ARB change needed for the
        accessibility label. Only the VISIBLE micro-label was hard-coded.
  - [x] Switch `set_row.dart:667` `set.setType.tinyAbbr` → new helper
        `_localizedSetTypeAbbr(setType, l10n)` reading the existing
        `setTypeAbbr*` ARB keys (Path A). Updated `set_row_test.dart` pins
        from raw `WK/WU/DR/FL` to the en localized values `W/WU/D/F`.
        Added `@Deprecated` on `SetType.tinyAbbr` so future UI calls that
        bypass localization fail review.
- [x] Step 3 — Rest timer overlay
  - [x] Wrap countdown Semantics with `liveRegion: true` + `container: true`.
  - [x] Outer scrim wrapped in `Semantics(container: true,
        explicitChildNodes: true, button: true, label: l10n.restTimerDismiss)`
        — pair-rule mandatory because without it the dismiss label merged
        with every descendant (countdown, exercise name, controls) into one
        AOM blob, and the inner liveRegion would fire on the entire merged
        label every tick.
  - [x] Wrap exercise-name Text with `Semantics(container: true,
        label: timerState.exerciseName)` + inner `ExcludeSemantics` so the
        Text's own emission doesn't double-announce.
- [x] Step 4 — Reorder + swap + remove
  - [x] `active_workout_screen.dart:_buildAppBarActions` — reorder toggle
        wrapped with the pair-rule + identifier `'workout-reorder-toggle'`
        + localized label.
  - [x] `exercise_card.dart` — swap/remove IconButtons wrapped with the
        pair-rule + identifiers `'workout-swap-exercise'` and
        `'workout-remove-exercise'`.
  - [x] `test/e2e/helpers/selectors.ts` — added `WORKOUT.reorderToggle`,
        `WORKOUT.swapExercise`, `WORKOUT.removeExercise` (selector-additive;
        existing `charter-c-exploratory.spec.ts` tolerance-selectors already
        anticipate these so no migration needed there).
- [x] Step 5 — AppBar title rename Semantics + workout name
  - [x] `active_workout_app_bar_title.dart:81` — replaced bare English
        `'$name. Tap to rename workout.'` with
        `l10n.workoutNameTapToRenameSemantics(name)`.
  - [x] `active_workout_notifier.dart:_generateWorkoutName()` — reads
        `ref.read(localeProvider).languageCode`, calls
        `lookupAppLocalizations(Locale(...))` for the prefix, and passes the
        language code to `DateFormat('EEE MMM d', languageCode)`. The
        comment block at L259-262 ("stored data, not display-only") is
        preserved — the name is generated once at workout start and frozen.

**ARB key additions (en + pt, both required):**
- [x] `decrementWeight`, `incrementWeight`, `decrementReps`, `incrementReps`
- [x] `weightValueSemantics(formatted, unit)`, `repsValueSemantics(value)`
- [x] `restTimerDismiss`
- [x] `workoutNameTapToRenameSemantics(name)`
- [x] `workoutDefaultName(date)`
- [x] Set-type cell label keeps existing `setNumberSemantics(number, type)`
      (already takes type placeholder) — visible micro-label switched to
      existing `setTypeAbbr*` keys, no new key added.

**Tests added (TDD discipline — failing-first where practical):**
- [x] `weight_stepper_semantics_test.dart` (8 tests) — accessible name
      en+pt for +/−, value-zone localized label en+pt, long-press still
      fires once + structural pin on the parent GestureDetector.
- [x] `reps_stepper_semantics_test.dart` (8 tests) — same contracts.
- [x] `set_row_set_type_semantics_test.dart` (8 tests) — set-type abbr en
      values W/WU/D/F + pt values N/AQ/D/F + negative pins on the old
      hard-coded WK/WU/DR/FL.
- [x] `rest_timer_overlay_test.dart` — extended (3 new tests) with
      liveRegion contract, dismiss button label, exercise-name AOM node.
- [x] `exercise_card_action_identifiers_test.dart` (4 tests) — swap +
      remove identifier reachability + pair-rule structural pin.
- [x] `active_workout_reorder_toggle_test.dart` (2 tests) — reorder-toggle
      identifier reachability + pair-rule structural pin.
- [x] `active_workout_app_bar_title_semantics_test.dart` (2 tests) —
      rename Semantics localized en + pt.
- [x] `active_workout_notifier_workout_name_test.dart` (3 tests) — en
      prefix `'Workout — '`, pt prefix `'Treino — '` (NOT en leak), pt
      date formatter actually used (lowercase weekday/month abbrs).
- [x] Updated existing `active_workout_notifier_test.dart` auto-name test
      to inject a StubLocaleNotifier so the notifier's new locale read
      doesn't blow up on uninitialised Hive in unit tests.

**Pipeline:**
- [x] tech-lead: TDD implementation, all 5 stages, all ARB keys, all tests
- [x] `make ci` — fresh full pipeline, 0 failures. 2451 tests passed,
      `dart analyze --fatal-infos` clean, `dart format` no diffs,
      `check_reward_accent.sh` + `check_hardcoded_colors.sh` clean,
      Android debug APK built successfully.
- [ ] qa-engineer: review widget coverage, update `selectors.ts`, run targeted
      e2e (selector-additive change — full suite not required unless tech-lead
      reports flow change). Confirm pair-rule on every new identifier.
- [ ] PR opened
- [x] reviewer-agent cycle: ALL findings (Critical/Warning/Nit/Suggestion)
      addressed same-cycle per memory feedback
  - Critical: warmup abbr alignment — `set_row.dart` warmup branch swapped
    from `setTypeAbbrWarmup` to `setTypeAbbrWarmupShort` so active workout
    matches `workout_detail_screen.dart:286`. Eliminates en `WU/Wu` and pt
    `AQ/Aq` divergence that survived Path A.
  - Warning: `_generateWorkoutName` clamps unsupported language codes to en
    before `lookupAppLocalizations`. Protects `startWorkout` from silently
    transitioning to AsyncError if a future locale slips through. Test
    pinned via `StubLocaleNotifier(Locale('es'))`.
  - Nit: `rest_timer_overlay.dart` `tapToDismiss` Text wrapped in
    `ExcludeSemantics` so `explicitChildNodes: true` no longer emits a
    redundant AOM leaf alongside the outer dismiss-button label. Negative
    pin added in widget test.
  - Nit: `set_row_set_type_semantics_test.dart` warmup test asserts
    localized `Wu/Aq` (not `WU/AQ`) and adds `WU/AQ` negative pins for
    parity with the other set-type tests.
  - Nit: `set_row.dart:670` Path A rationale comment names
    `setTypeAbbr*Short` as the canonical key family and refers to the
    current detail-screen line (`:286`) instead of the stale `:285-288`.
- [ ] Squash-merge after CI green
- [ ] Cleanup PR: close WIP, mark 11 bugs resolved in
      `active-workout-findings.md`

**Risk monitor (from impact analysis):**
- Tooltip captures long-press gesture (steppers) → fall back to explicit Semantics
- Pair-rule violation on identifiers (PR #152 regression risk) — every new
  identifier needs a widget test pinning reachability
- liveRegion may be too chatty — accept for now per Q3.1 default
- Path A breaks `set_row_test.dart` `tinyAbbr` pins — update them as part of
  the same commit; this is the trade-off for product-alignment with workout_detail
