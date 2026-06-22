# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 38.9 T3.1 — decompose finishWorkout() — `feature/hardening-t3.1-finishworkout-decompose`

Per `docs/PROJECT.md` §2 → Phase 38.9 T3.1. `finishWorkout()`
(`active_workout_notifier.dart:1526-2143`, ~617 lines) is the single largest SRP violation
+ the riskiest method to touch blind. **Phase 39's quest/rest work will modify it**, so
decompose first into independently-readable private steps.

**No-regression mandate (CRITICAL — this is a pure refactor):**
- Behavior must be IDENTICAL — same returns, same order of effects, same error paths, same
  re-entrance/cancel semantics, same offline-fallback, same celebration build, same analytics.
- The EXISTING test suite is the regression net. Every existing test must pass UNCHANGED. If a
  test breaks, the refactor changed behavior → fix the refactor, NOT the test. Do not edit test
  expectations to accommodate the refactor.
- Extract private methods only; no logic/contract change; no new public surface.

### Checklist
- [x] Read `finishWorkout()` end-to-end; map the natural cohesive seams (audit suggested
  `_partitionCommitted` / `_detectAndPersistPRs` / `_diffRpgSnapshot` / `_persistWorkout` — but
  follow the real structure; preserve the documented cancel/guard/offline ordering exactly).
- [x] Extract each seam into a private method with a clear name + doc; `finishWorkout` becomes a
  readable orchestration of the steps. Keep the `AsyncValue.guard` + re-entrance guard + cancel
  checks in `finishWorkout` itself (don't bury control flow in helpers).
  - `_persistWorkout(...)` → returns `(savedOffline, serverErrorQueued, saveCommitted)`; owns the
    save try/catch + terminal-rethrow + offline enqueue + `_originalSetIndices.clear()`.
  - `_detectAndPersistPRs(...)` → returns `(prResult, workoutCount)`; owns the offline-first
    detection + direct/queued upsert + pr_cache merge, self-contained swallowing try/catch.
  - `_trackWorkoutFinishedEvent(...)` → fire-and-forget `workoutFinished` analytics + breadcrumb.
  - Control flow (guard, re-entrance guard, cancel-checks, early-returns, post-commit return
    record) stays in `finishWorkout`. Method shrank 617 → 277 lines. NO test modified.
- [x] `dart format` + `dart analyze --fatal-infos` clean.
- [x] FULL `flutter test` green — +3978 passed / ~1 skipped, IDENTICAL to pre-refactor baseline.
  Integration suite green vs local Supabase (+77, incl. save_workout / offline_sync_replay / rpg).

_Tier 1 (#367/#369/#372) + Tier 2 T2.1–T2.4 (#374) merged. T2.5/T2.6 + Tier 0 + rest of Tier 3 queued._

_No in-flight work._ **Phase 38.9 Tier 1 + Tier 2 (T2.1–T2.4) complete** — #367/#369/#372
(correctness, RLS gate, offline integration) + #374 (coverage floor, osv-scanner, layering
gate, migration doc). Remaining: T2.5/T2.6 (deferred — harder), Tier 0 (launch-readiness),
Tier 3 (tech-debt) — tracked in `docs/PROJECT.md` §2 → Phase 38.9.
