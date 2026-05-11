# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `PLAN.md` step or backlog entry, check items off
as work lands, and remove the section after the merge condenses to PLAN.md.

---

## Active Workout Audit — PR-5: Hint slot stability + visual contrast + disabled-Finish helper

**Branch:** `fix/active-workout-pr5-hint-slot-and-visual-polish`
**Source:** Per `BUGS.md` PR-5 OPEN cluster + `PLAN.md` Phase 22 cluster ledger.

**Goal:** layout stability + WCAG AA contrast + previously-invisible
affordance icons + an explanation for the disabled "FINISH" CTA. All in
the active-workout surface; no logic changes.

### Acceptance criteria

1. **H8 — Hint slot stability across set completion**
   (`lib/features/workouts/ui/widgets/set_row.dart:283-361`).
   Today: when a set transitions pending → completed, the previous-session
   hint disappears → row collapses by ~18dp → adjacent rows shift under the
   thumb mid-tap.
   Fix: fixed-height filler when no hint shown (e.g.
   `SizedBox(height: 18)`), so the row geometry is layout-stable across
   transitions. **CRITICAL CONSTRAINT:** PR #193 attempted this with
   `Visibility(maintainSize: true)` and re-triggered a Flutter Web
   semantics-engine role-swap bug — the standing-PR row's
   `flt-semantics-identifier` stopped emitting because the maintained
   layout mutated the Semantics tree shape across visibility flip. See
   the `_shouldShowHint` dartdoc + the conditional-render branch in
   `set_row.dart` for the full root-cause. The fix MUST avoid mutating
   the Semantics tree shape on hint show/hide. Recommended approach:
   gate the filler behind `!kIsWeb` (Web keeps the conditional render
   to dodge the AOM bug; mobile gets the layout-stable filler). OR
   render an always-present fixed-height container that swaps its
   child between the hint Text and an empty SizedBox — same tree shape
   in both states, no Visibility.
2. **M7 — Elapsed timer WCAG AA contrast**
   (`lib/features/workouts/ui/widgets/elapsed_timer.dart:38`).
   `theme.colorScheme.primary` (`primaryViolet #6A2FA8`) on `abyss #0D0319`
   ≈ 2.6:1 ratio. AA requires 4.5:1 for body text. Swap to
   `AppColors.hotViolet #B36DFF` (~5.9:1, passes AA).
3. **M8 — Invisible affordance icons**
   (`active_workout_app_bar_title.dart:92-97` pencil 14dp α=0.4;
   `exercise_card.dart:455-460` info_outline 14dp α=0.35).
   Functional affordances at the visibility threshold. Bump to 16dp
   α=0.6 (pencil) and 16dp α=0.5 (info).
4. **H6 — Disabled FINISH button has no explanation**
   (`lib/features/workouts/ui/widgets/finish_bottom_bar.dart:74-100`).
   When `enabled == false`, show short helper text below or above the
   button: "Complete at least one set to finish." Use existing
   `AppLocalizations` patterns; add EN + PT ARB keys.
5. **Rest-timer dismiss hint contrast**
   (`lib/features/workouts/ui/widgets/rest_timer_overlay.dart:269-276`).
   "Tap anywhere to dismiss" at α=0.3 on near-black scrim is essentially
   invisible. Raise to α=0.55-0.65.

### Files to modify

- `lib/features/workouts/ui/widgets/set_row.dart` — H8 hint slot fixed-height filler (with kIsWeb gate or Semantics-stable design)
- `lib/features/workouts/ui/widgets/elapsed_timer.dart` — M7 color swap
- `lib/features/workouts/ui/widgets/active_workout_app_bar_title.dart` — M8 pencil icon size/alpha
- `lib/features/workouts/ui/widgets/exercise_card.dart` — M8 info_outline icon size/alpha
- `lib/features/workouts/ui/widgets/finish_bottom_bar.dart` — H6 helper text under disabled state
- `lib/features/workouts/ui/widgets/rest_timer_overlay.dart` — dismiss hint α bump
- `lib/l10n/app_en.arb` + `app_pt.arb` — new H6 key `finishWorkoutDisabledHint` ("Complete at least one set to finish." / PT translation)

### Tests to add (widget + E2E per the user's coverage directive)

**Widget tests:**
- H8 — `set_row_test.dart`: pump a row in pending+hint-shown state and same row in completed+hint-hidden state, assert vertical geometry (via `tester.getSize()`) is identical OR that the row's parent height doesn't change. **CRITICAL:** also pin the standing-PR identifier survives the transition — that's the regression the PR #193 attempt caused. Add a transition test (PR-state goes pendingPredictedPr → completedStandingPr) and assert `flt-semantics-identifier` survives.
- M7 — `elapsed_timer_test.dart`: pump the widget, find the Text, assert `style.color == AppColors.hotViolet` (regression pin for WCAG).
- M8 — `active_workout_app_bar_title_test.dart`: assert pencil icon `size: 16` and `alpha: ~0.6`.
- M8 — `exercise_card_test.dart`: assert info_outline icon `size: 16` and `alpha: ~0.5`.
- H6 — `finish_bottom_bar_test.dart`: when `enabled: false`, helper text widget is present with localized string; when `enabled: true`, helper text is absent (or invisible).
- Rest-timer dismiss hint — `rest_timer_overlay_test.dart`: assert hint Text `alpha` ≥ 0.55.

**E2E tests in `test/e2e/specs/workouts.spec.ts`:**
- `Layout stability on set completion (PR5 — H8)` describe block:
  - "should not reflow adjacent rows when a set is completed and its hint slot collapses" — drives the completion gesture and asserts adjacent row's bounding box y-coordinate is stable
- `Disabled Finish helper text (PR5 — H6)` describe block:
  - "should show 'Complete at least one set to finish' helper when no sets are done" (initial state of a fresh exercise card)
  - "should hide the helper text once any set is completed" (toggle)

E2E selectors to add in `test/e2e/helpers/selectors.ts`:
- `finishDisabledHelperText` (role=text or by content)

### Pipeline checklist

- [ ] `tech-lead` reads PLAN.md Phase 22 + this WIP + the BUGS.md PR-5 entries (H8, M7, M8, H6, dismiss hint), then implements with TDD.
- [ ] H8 implementation MUST avoid the Flutter Web AOM bug — read `set_row.dart`'s `_shouldShowHint` dartdoc carefully BEFORE designing the fix.
- [ ] After each fix: `dart format .` + `dart analyze --fatal-infos` clean.
- [ ] All new tests pass; existing tests still pass.
- [ ] `qa-engineer` reviews coverage, runs full E2E suite locally, adds any missing E2E. Selector additions go in `helpers/selectors.ts`.
- [ ] `ui-ux-critic` reviews — this PR is mostly visual/copy. Brief gate.
- [ ] Orchestrator runs CI verification — 0 failures, full output read.
- [ ] PR opened with copy of acceptance criteria and "Closes BUGS.md H8, M7, M8, H6, rest-timer dismiss hint contrast."
- [ ] `reviewer` flags addressed in same cycle (no deferral, per memory rule).
- [ ] Squash merge to `main`; no DB migration; close WIP section in a follow-up docs PR; update BUGS.md to mark items RESOLVED with PR ref.
