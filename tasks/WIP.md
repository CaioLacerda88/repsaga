# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `PLAN.md` step or backlog entry, check items off
as work lands, and remove the section after the merge condenses to PLAN.md.

---

## Family 7 — AW-EX-D-US1-02 Re-probe (branch: fix/workouts-saga-intro-pr-celebration-reprobe)

**VERDICT: FIXED. Root cause was a navigation race in `FinishWorkoutCoordinator`,
not in PR detection. The qa-engineer's three suspicions (unawaited cache write,
silent exception swallow, detection comparison) were all refuted by systematic
debugging — production logging proved `prResult.hasNewRecords == true` for
workout B and `navigateAfterFinish` correctly pushed `/pr-celebration`. The
final URL still ended at `/home` because the active-workout screen's own
`postFrameCallback` (which goes home when `displayState == null`) fired AFTER
`navigateAfterFinish`'s postFrame in the same frame and clobbered the
celebration push with `go('/home')`.**

**Root cause (file:line):**
`lib/features/workouts/ui/coordinators/finish_workout_coordinator.dart:235`
released `_isFinishHandled = false` BEFORE calling `navigateAfterFinish`. The
flag is read by `lib/features/workouts/ui/active_workout_screen.dart:75` from
inside a postFrameCallback. The screen's postFrame fires in the SAME frame as
navigateAfterFinish's postFrame, in FIFO order — both see `_isFinishHandled =
false`, screen calls `context.go('/home')` after navigator pushed
`/pr-celebration`. Last write wins → `/home`.

**Fix:** defer `_isFinishHandled = false` via a 2-frame `addPostFrameCallback`
chain so the flag stays `true` through frame N+1's postFrame phase. Frame N+2
releases it; by then the active-workout screen has unmounted (route changed)
and its postFrame is irrelevant. Removed the early release at L238 and the
redundant release in `finally` (the deferred chain is the single lifecycle
owner now).

**Verification:**
- Unit reproducer (`active_workout_notifier_test.dart` AW-EX-D-US1-02 test)
  passes — proves PR detection itself is correct (the bug is NOT here).
- Live E2E regression test (`personal-records.spec.ts:584` — AW-EX-D-US1-02
  regression) passes WITHOUT `test.fail()`.
- Full unit suite: 95/95 active_workout_notifier tests pass; 2413 unit/widget
  tests pass overall.
- Full personal-records E2E suite (13 tests) passes.
- Full workouts E2E suite (22 tests) passes.
- Full RPG-foundation E2E suite (6 tests) passes.

**Why unit tests didn't catch it:** the unit reproducer tests data flow
(cache → detection → result), which is correct. The bug is in UI navigation
choreography (postFrameCallback ordering between two coordinators reading the
same `_isFinishHandled` flag). A widget test exercising the full
ActiveWorkoutScreen + GoRouter + post-finish navigation would have caught it,
but no such test existed. Future hardening: a widget test that asserts the
URL after `finishWorkout()` returns with `prResult.hasNewRecords = true`.

**Checklist:**
- [x] Read charter-D-US-1.md AW-EX-D-US1-02 entry
- [x] Read Family 7 section of active-workout-implementation-plan.md
- [x] Read celebration_orchestrator.dart (play() method, SagaIntroSequencer await)
- [x] Read post_workout_navigator.dart (navigateAfterFinish branch logic)
- [x] Read saga_intro_gate.dart (sequencer completion paths)
- [x] Read pr_cache_bootstrap_provider.dart (PR #177 — Family 1A fix)
- [x] Read app_router.dart (bootstrap provider wired via ref.listen at shell mount)
- [x] Read personal-records.spec.ts (existing PR celebration E2E coverage)
- [x] Initial static analysis: suggested Case A (dissolved) — REFUTED by live probe
- [x] Live Playwright E2E re-probe: CONFIRMED Case B (still broken)
- [x] Added regression-guard E2E test to personal-records.spec.ts
- [x] Wrote unit reproducer (passes — confirmed bug is NOT in detection)
- [x] Instrumented production code with diagnostic prints, ran failing E2E
- [x] Captured browser console: `prResult.hasNewRecords=true` AND
      `navigateAfterFinish → /pr-celebration` BOTH happen, but final URL is /home
- [x] Identified root cause: ActiveWorkoutScreen's postFrame fires AFTER
      navigateAfterFinish's postFrame in same frame, clobbers /pr-celebration with /home
- [x] Applied minimal fix (deferred `_isFinishHandled = false` release)
- [x] Removed `test.fail()` from regression test
- [x] All E2E + unit suites pass
- [x] All diagnostic prints removed

**Round 2 review fixes (6 findings, all in this cycle):**
- [x] Critical 1 — `tasks/active-workout-findings.md`: master table row AW-EX-D-US1-02
      flipped from "⏳ pending re-probe" to "✅ resolved (PR #185, Family 7)";
      Family 7 section rewritten end-to-end (no more Saga intro framing — now
      reflects the postFrameCallback ordering race + actual fix); running tally
      bumped 12 → 13 with PR #185 entry added.
- [x] Critical 2 — `finish_workout_coordinator.dart` block comment around the
      deferred-release: removed the false claim that `finally` re-asserts
      `_isFinishHandled = false`; replaced with truthful description of what
      `finally` actually does (resets only `_isFinishing`; on exception paths
      `_isFinishHandled` stays `true` for the screen lifetime — harmless).
- [x] Warning 1 — same block comment now documents `context.mounted` at
      `active_workout_screen.dart:75` as the secondary safety net for late
      Riverpod-triggered rebuilds firing AFTER the deferred release.
- [x] Warning 2 — `finish_workout_coordinator.dart:236` stale comment fixed:
      was "finally block will release the flag", now correctly states finally
      clears only `_isFinishing` and `_isFinishHandled` stays `true` (harmless).
- [x] Warning 3 — `active_workout_notifier_test.dart` AW-EX-D-US1-02 reproducer:
      added `verify(() => mockPRRepo.getRecordsForExercises(any())).called(1)`
      after the workout-B assertions. (Reviewer's `verifyNever` proposal would
      have failed: workout A's first run is a legitimate cold-cache → DB call.
      The cache-hit contract is "B doesn't call it" → "total calls stay at 1
      across both workouts." Same intent, correct shape.) Pins the cache-hit
      path explicitly; without it the test would silently pass on a workout-B
      cache miss because the DB stub returns empty (workout A's PR re-detected
      against empty baseline).
- [x] Warning 4 — `personal-records.spec.ts:584` regression guard: documented
      why it's NOT tagged `@smoke` (two-workout sequence + `test.slow()` triple
      timeout is too slow for the CI smoke gate; full regression suite covers
      it on every PR).
- [x] Suggestion (overlap with Warning 2) — addressed by Warning 2's fix.
- [x] `dart format .` clean
- [x] `dart analyze --fatal-infos` clean
- [x] Full unit/widget suite green; AW-EX-D-US1-02 unit reproducer still
      passes with the new `verifyNever` assertion.

---
