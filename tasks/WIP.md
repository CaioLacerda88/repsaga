# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `PLAN.md` step or backlog entry, check items off
as work lands, and remove the section after the merge condenses to PLAN.md.

---

## Active Workout Audit — PR-6: PR-row loading flicker + analytics source DRY

**Branch:** `fix/active-workout-pr6-row-flicker-and-source-dry`
**Source:** Per `BUGS.md` PR-6 OPEN cluster + `PLAN.md` Phase 22 cluster ledger.

**Goal:** stop the PR-row flicker that briefly mis-renders rows as
"standing PR" while `exercisePRsProvider` is loading, and DRY the
`source` analytics-string computed in three places in the notifier.
Pure UX polish + maintainability; no functional behavior change.

### Acceptance criteria

1. **M6 — `activeWorkoutRowDisplaysProvider` returns empty PR list during loading → false predicted-PR signals**
   (`lib/features/workouts/providers/workout_providers.dart:109-110`).
   Today: `exercisePRsProvider(...).value ?? const []` — when loading,
   every completed working set looks like a "standing PR" (gold stripe
   + bracket). Once data lands, rows reclassify. Visual flicker.
   Documented as "first-ever workout" behavior but also fires for
   returning users with slow PR data.
   Fix: when `exercisePRsProvider.isLoading`, return `PrRowState.none`
   for completed sets — don't classify until data lands. The actual
   PR celebration at finish uses pr_cache (not the row provider) so
   finish-time correctness is unaffected.
2. **Source-string DRY (smell)**
   (`active_workout_notifier.dart` lines 259, 732, 1258 — three
   occurrences of `current.routineId != null ? 'routine_card' : 'empty'`).
   Extract to a private `_workoutSource()` helper so a future addition
   (e.g. `'barcode_scan'`) needs one update, not three. Bug-prone today
   — one missed update produces inconsistent analytics.

### Files to modify

- `lib/features/workouts/providers/workout_providers.dart` — M6: gate `activeWorkoutRowDisplaysProvider` on `exercisePRsProvider.isLoading`.
- `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` — extract `_workoutSource()` helper; replace the 3 inline ternaries.

### Tests to add (widget + E2E per the user's coverage directive)

**Widget/unit tests:**
- M6 — `workout_providers_test.dart` (or wherever `activeWorkoutRowDisplaysProvider` is tested): pump the provider with `exercisePRsProvider` overridden to `AsyncLoading`; assert all completed sets resolve to `PrRowState.none`. Then transition to `AsyncData([])`; assert classifier runs normally. Then `AsyncData([record])`; assert standing-PR rows get the right state.
- DRY — `active_workout_notifier_test.dart`: existing analytics tests should keep passing; verify the three `'empty'` / `'routine_card'` analytics events still fire correctly across startWorkout, finishWorkout, discardWorkout. No new test needed if existing coverage is sufficient.

**E2E tests in `test/e2e/specs/workouts.spec.ts`:**
- M6 — `PR row state during loading (PR6 — M6)` describe block:
  - "should NOT flicker completed sets to standing-PR while pr_cache is loading" — tricky to drive in E2E because pr_cache loads fast. May need to use page.route() to stall the PR endpoint, then complete a set, then assert the row identifier is NOT `set-row-state-standing-pr` during the stall window. If hard to stage deterministically, document why and skip — unit test owns the contract.

E2E selectors should be reusable from prior PRs.

### Pipeline checklist

- [ ] `tech-lead` reads PLAN.md Phase 22 + this WIP + the BUGS.md PR-6 entries (M6, source-string DRY), then implements with TDD.
- [ ] After each fix: `dart format .` + `dart analyze --fatal-infos` clean.
- [ ] All new tests pass; existing tests still pass.
- [ ] `qa-engineer` reviews coverage, runs full E2E suite locally, adds any missing E2E. Selector additions go in `helpers/selectors.ts`.
- [ ] Orchestrator runs CI verification — 0 failures (mod pre-existing flakes), full output read.
- [ ] PR opened with copy of acceptance criteria and "Closes BUGS.md M6 + source-string DRY smell."
- [ ] `reviewer` flags addressed in same cycle (no deferral, per memory rule).
- [ ] Squash merge to `main`; no DB migration; close WIP section in a follow-up docs PR; update BUGS.md to mark items RESOLVED with PR ref.
