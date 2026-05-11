# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `PLAN.md` step or backlog entry, check items off
as work lands, and remove the section after the merge condenses to PLAN.md.

---

## Active Workout Audit — PR-7: Brand voice + generic-icon swaps (FINAL PR of audit wave)

**Branch:** `fix/active-workout-pr7-brand-voice-and-icons`
**Source:** Per `BUGS.md` PR-7 OPEN cluster + `PLAN.md` Phase 22 cluster ledger.

**Goal:** distinguish the active-workout surface from generic Material/AI
fitness UI. Replace generic Material icons with brand glyphs, revisit
copy to align with the existing RPG/saga voice, and bump
`_AddSetButton` from a near-invisible OutlinedButton to a filled
accent that reads as the high-frequency primary action it is.

This is the **last PR in the Phase 22 audit fix wave** — closes out
Section 5 generic-AI smells from the original audit findings.

### Acceptance criteria

1. **Generic-icon swaps:**
   - `lib/features/workouts/ui/widgets/resume_workout_banner.dart:47`: `Icons.fitness_center` → `AppIcons.lift` (custom brand glyph already exists)
   - `lib/features/workouts/ui/widgets/exercise_card.dart` PR-empty-state (`_SheetPRSection._emptyRow`, ~line 944): `Icons.emoji_events_rounded` → custom brand glyph (check `AppIcons` for a "trophy" or "achievement" alternative; if none exists, drop the icon and use text-only with a small visual treatment)
   - `lib/features/workouts/ui/active_workout_screen.dart:251` reorder toggle: `Icons.swap_vert` → `Icons.reorder` (3-line drag-handle convention; less ambiguous than `swap_vert` which reads as "swap two" not "reorder")
2. **Brand voice copy revisits** in `lib/l10n/app_en.arb` + `app_pt.arb`:
   - **Audit existing RPG/celebration/saga copy first** as the voice anchor. Read at least: `app_en.arb` keys for `firstAwakening*`, `rankUp*`, `titleUnlock*`, `levelUp*`, `class*`, `saga*`, `vitality*` to understand the established voice (heroic, journey-themed, "saga" framing).
   - `finishWorkoutTitle` ("Finish Workout?") → align with that voice. Examples: "Seal this chapter?", "Mark this entry?", "Lock in?" — pick what fits, don't go cheesy.
   - `discardWorkoutContent` ("You've been working out for X. This cannot be undone.") → carry the brand weight at the highest-stakes destructive moment. Don't flatten; lean into the consequence.
   - `workoutInterrupted` lowercase-after-newline issue — capitalize "Was interrupted" or restructure to single-string with placeholders.
   - Cancel-during-loading copy currently uses generic `cancel` key. UI critic flagged on PR-1 this could read as destructive ("cancel my workout"). Add new scoped ARB key (e.g. `loadingOverlayStop` → "Stop" / "Parar"); keep the generic `cancel` key for other call sites.
   - PT "D" set-type abbreviation is ambiguous (could be Drop / Direto / Diminuição). Pick a clearer abbreviation or replace with a tooltip-only approach.
3. **`_AddSetButton` filled accent treatment**
   (`lib/features/workouts/ui/widgets/exercise_card.dart` `_AddSetButton` ~line 535):
   Current: OutlinedButton with `primary.withValues(alpha: 0.3)` border — reads quieter than the `_FillRemainingButton` TextButton beside it. Add Set is the highest-frequency action in the active workout.
   Fix: filled accent (e.g. `hotViolet @ 12% fill + hotViolet border @ 60% alpha + hotViolet text @ full strength`) so it reads as a positive primary action, not a quiet secondary one.

### Files to modify

- `lib/features/workouts/ui/widgets/resume_workout_banner.dart` — icon swap (1 line)
- `lib/features/workouts/ui/widgets/exercise_card.dart` — PR empty state icon (or removal); `_AddSetButton` fill treatment
- `lib/features/workouts/ui/active_workout_screen.dart` — reorder toggle icon
- `lib/features/workouts/ui/widgets/active_workout_loading_overlay.dart` — switch from `l10n.cancel` to new scoped key
- `lib/l10n/app_en.arb` + `app_pt.arb` — copy revisits + new `loadingOverlayStop` key + PT D-abbreviation reconsideration

### Tests to add (widget + E2E per the user's coverage directive)

**Widget tests:**
- Icon swaps: extend `resume_workout_banner_test.dart`, `exercise_card_test.dart`, `active_workout_app_bar_title_test.dart` (or wherever) — find by NEW icon (e.g. `find.byIcon(Icons.reorder)`, `find.bySvgPath(AppIcons.lift)`) and assert presence; find OLD icon and assert absence (regression-pin).
- `_AddSetButton` filled accent: assert button background color is non-transparent in the new state; pin the visual contract.

**E2E tests in `test/e2e/specs/workouts.spec.ts`:**
- ARB key changes flow through to E2E selectors that look up by accessible name. Verify any existing test using `name="FINISH WORKOUT"` or `name="Discard"` etc still matches the new copy. Update selectors as needed.
- Loading overlay "Cancel" → "Stop" — E2E selector `loadingOverlayCancelButton` (`role=button[name="Cancel"]`) needs renaming to `loadingOverlayStopButton` (`role=button[name="Stop"]`). Touches all PR-1 cancel-overlay tests.
- One smoke E2E: tap the now-filled-accent Add Set button → set added (regression pin that the visual change didn't break the gesture).

### Pipeline checklist

- [x] `tech-lead` reads PLAN.md Phase 22 + this WIP + the BUGS.md PR-7 entries (Section 5 + UI-critic deferred + _AddSetButton). **MUST audit existing RPG copy first** before proposing new copy — see acceptance criterion 2.
- [x] After each fix: `dart format .` + `dart analyze --fatal-infos` clean. Run `flutter gen-l10n` after ARB changes.
- [x] All new tests pass; existing tests still pass. Existing PR-1 cancel-overlay tests need selector updates if Cancel→Stop ships. (Full unit/widget suite: 2595/2595 pass. Targeted E2E `workouts.spec.ts`: 40/40 pass.)
- [ ] `ui-ux-critic` reviews — this PR is mostly visual/copy, brief gate on whether the brand voice direction lands.
- [ ] `qa-engineer` reviews coverage, runs full E2E suite locally, adds any missing E2E. Selector additions go in `helpers/selectors.ts`.
- [ ] Orchestrator runs CI verification — 0 failures (mod pre-existing flakes), full output read.
- [ ] PR opened with copy of acceptance criteria and "Closes BUGS.md PR-7 cluster (Section 5 generic-AI smells + UI-critic deferred Cancel→Stop + _AddSetButton accent). Phase 22 audit wave complete."
- [ ] `reviewer` flags addressed in same cycle (no deferral, per memory rule).
- [ ] Squash merge to `main`; no DB migration; close WIP section in a follow-up docs PR; update BUGS.md to mark items RESOLVED with PR ref. Mark Phase 22 status DONE in PLAN.md progress table.
