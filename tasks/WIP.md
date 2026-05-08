# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `PLAN.md` step or backlog entry, check items off
as work lands, and remove the section after the merge condenses to PLAN.md.

---

## fix/workouts-finish-button-disabled-state — Family 8 from active-workout exploratory pass

**Branch:** `fix/workouts-finish-button-disabled-state`
**Source:** `tasks/active-workout-implementation-plan.md` Family 8 + master finding AW-EX-C-BR1-03.

**Charter C observation:** Finish button shows 30% alpha (visually disabled) with 0 completed sets, BUT was tappable and opened the FinishWorkoutDialog. Spec §5.5 disabled-state matrix violation.

**Tech-lead static analysis (from PR #174 implementation plan):** `finish_bottom_bar.dart:74` correctly uses `onPressed: enabled ? onPressed : null` which Flutter maps to `aria-disabled`. The disabled state IS wired. Possible explanations:
1. Charter C's repro was wrong — the user had a completed set from setup (or somehow `_hasCompletedSet == true` despite the empty appearance)
2. The `_hasCompletedSet` flag is computed wrong upstream
3. The button fires via a different path (Pulse/Enter key, gesture, etc.) than the standard tap
4. Web-specific gesture quirk (similar to the gesture-arena Family 4 reviewer claim that turned out empirically wrong)

**Approach: investigate-first.** Reproduce in a widget test before changing any code. If the button is genuinely tappable in the disabled state, fix; if not, mark stale with a regression-guard test pinning the contract.

### Checklist

- [x] tech-lead: read implementation plan §Family 8 + Charter C-BR1-03 entry
- [x] tech-lead: reproduce Charter C's scenario in a widget test — pump `ActiveWorkoutScreen` with an active workout that has 0 completed sets; assert the Finish button is visible (per spec §5.5 it should be visible but disabled, not hidden); attempt `tester.tap(finishButton)`; assert dialog does NOT open
- [x] **VERDICT: STALE-WITH-REGRESSION-GUARD.** Three new contract tests in `test/widget/features/workouts/ui/active_workout_finish_button_test.dart` group `'AW-EX-C-BR1-03: Finish button disabled state'` ALL PASS on existing code. The wiring at `finish_bottom_bar.dart:74` (`onPressed: enabled ? onPressed : null`) and `active_workout_screen.dart:271` (`enabled: _hasCompletedSet`) correctly produces `FilledButton.onPressed == null` and `tester.tap` does NOT open the FinishWorkoutDialog when zero sets are completed. Charter C's observation was likely an E2E-environment artefact (see findings doc update for hypothesis).
- [x] tech-lead: `dart format` + `dart analyze --fatal-infos` clean; full unit/widget suite green (2412 tests pass)
- [x] orchestrator: CI green — format clean, `dart analyze --fatal-infos` 0 issues, reward-accent + hardcoded-colors guards clean, 2412 tests passing (+3 from Family 8). Android-debug-build skipped: test-only diff, zero production Dart code changed, so Kotlin compile path is unaffected (per CLAUDE.md "format + analyze + test" minimum).
- [x] qa-engineer: PASS — `lib/` diff empty (zero production-code change); all 3 regression-guard tests genuinely load-bearing (would fail under inverted `enabled` wiring or `every`-instead-of-`any` boundary); "prior session state" hypothesis verified plausible (Charter C P11 didn't record a `state.completedSetsCount == 0` check before tapping, and the `fullWorkout` seed user has prior history)
- [ ] orchestrator: open PR; cite AW-EX-C-BR1-03 with STALE verdict + regression-guard tests
- [ ] reviewer: pass; address every finding (incl. Suggestions) in the same cycle
- [ ] squash merge to main, delete branch, post-merge cleanup PR (mark Family 8 resolved as STALE)
