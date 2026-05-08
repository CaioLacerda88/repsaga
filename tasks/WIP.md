# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `PLAN.md` step or backlog entry, check items off
as work lands, and remove the section after the merge condenses to PLAN.md.

---

## fix/workouts-rest-timer-scrim-modal — Family 2 from active-workout exploratory pass

**Branch:** `fix/workouts-rest-timer-scrim-modal`
**Source:** `tasks/active-workout-implementation-plan.md` Family 2 + master findings AW-EX-A-BR1-04, AW-EX-B-US1-01, AW-EX-F-BR1-05.

**Root cause:** `rest_timer_overlay.dart:49` outer `GestureDetector(onTap: stop)` uses Flutter's default `HitTestBehavior`, which lets pointer events propagate to widgets below the scrim. Single-tap on the scrim near the top of the screen opens the exercise detail sheet (Charter A) or the weight-entry dialog (Charter B). Long-press doesn't repro because pointer-down dismisses before the 900ms threshold (Charter C).

**Fix:** add `behavior: HitTestBehavior.opaque` to the outer `GestureDetector`. Symmetric with the inner button row at L108-109 which already uses opaque behavior. `AbsorbPointer` is overkill per the impact analysis.

### Checklist

- [x] tech-lead: write a widget test that pins the contract (FAILING test first per TDD): RestTimerOverlay rendered over an underlying tappable widget; tap on scrim → overlay dismisses, underlying handler does NOT fire
- [x] tech-lead: add `behavior: HitTestBehavior.opaque` to outer `GestureDetector` at `rest_timer_overlay.dart:49`; test passes
- [x] tech-lead: run `dart format .` + `dart analyze --fatal-infos` clean; full unit/widget suite green
- [x] orchestrator: CI green — format clean, `dart analyze --fatal-infos` 0 issues, reward-accent + hardcoded-colors guards clean, 2363 tests passing, android-debug APK built in 64s
- [ ] qa-engineer: selector impact assessment (no widget tree change → expect zero E2E impact); confirm new widget test pins the contract correctly
- [ ] orchestrator: open PR with root-cause + surgical-fix summary; cite the 3 closed bug IDs
- [ ] reviewer: pass; address every finding before merge
- [ ] squash merge to main, delete branch, remove this WIP section
