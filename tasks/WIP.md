# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `PLAN.md` step or backlog entry, check items off
as work lands, and remove the section after the merge condenses to PLAN.md.

---

## E2E flake root-cause: routines-rename + S12 saga

**Branch:** `fix/e2e-flakes-routines-rename-and-s12-saga`
**Source:** Per Phase 22 PR-5/PR-7 admin-merges that surfaced these as pre-existing flakes (NOT Phase 22 regressions). User-chosen path: option (c) — root-cause both, not just tag-and-bypass.

**Goal:** turn two pre-existing intermittent E2E failures into either (a) deterministic green tests OR (b) consciously-tagged `@flaky` with a documented root-cause + a clear path-to-discharge in `test/e2e/FLAKY_TESTS.md`.

### Background

Two flakes have been blocking clean PR ships:

1. **`test/e2e/specs/routines.spec.ts`** "should rename a routine via the action sheet"
   - Failure: `[flt-semantics-identifier="routine-edit-option"]` not visible after 10s timeout. Both attempts fail.
   - Family: same as `routines.spec.ts:172` "should delete a routine and remove it from the list" (documented in PLAN.md Active Backlog "Known flaky e2e tests"). Both rely on the action sheet's options being visible. Action-sheet rendering / state pollution.
   - First observation: surfaced 2026-05-07 across multiple unrelated PR runs.

2. **`test/e2e/specs/saga.spec.ts:437`** S12 "should update class badge after chest crosses rank 5"
   - Failure: "Target page, context or browser has been closed" — Playwright worker crash, infrastructure-level, not assertion-level.
   - Currently tagged `@flaky` with `FLAKY_TESTS.md` entry (added during PR-4 cycle).
   - QA's diagnosis (PR-4 cycle): "post-rank-up navigation chain saturates 60s timeout under workers=4 CPU contention"; passes 1/1 in isolation.

### Investigation plan (apply systematic-debugging skill)

Per `superpowers:systematic-debugging` phases:

1. **Phase 1 — Root Cause:** reproduce both failures locally with deterministic seeds. For routines-rename: run with `--repeat-each=10` to characterize failure rate. For S12: examine worker memory pressure, browser console at crash time, navigation timing.
2. **Phase 2 — Pattern:** compare to working tests in the same files (e.g., other routines tests using the same action-sheet pattern). What's different about the failing ones?
3. **Phase 3 — Hypothesis:** form ONE specific theory per flake. Test minimally.
4. **Phase 4 — Fix:** root cause not symptom. Verify with `--repeat-each=10` consecutive passes.

### Acceptance criteria

For EACH of the two flakes:
- **Either** ship a deterministic fix that passes 10/10 with `--repeat-each=10`, AND removes the test from `FLAKY_TESTS.md` (S12 entry deletion; or routines-rename never gets added),
- **OR** document the root cause precisely in `FLAKY_TESTS.md` with: (a) specific failure mechanism, (b) what would need to change to fix, (c) why that change is out-of-scope right now. Tag the test `@flaky` if not already.

### Files likely to modify

- `lib/features/routines/...` — if action-sheet timing has a real prod bug
- `test/e2e/specs/routines.spec.ts` — possibly tighten setup / add explicit waits
- `test/e2e/specs/saga.spec.ts` — possibly extend timeout or restructure S12
- `test/e2e/playwright.config.ts` — possibly per-test timeout overrides
- `test/e2e/FLAKY_TESTS.md` — entry updates (deletion if fixed, refinement if documenting)
- `test/e2e/helpers/*` — possibly improve action-sheet wait helpers

### Out of scope

- CI workflow change to filter `@flaky` tests (separate infrastructure question — flagged by orchestrator during PR-5 admin-merge but not addressed here)
- Investigation of any OTHER flakes that surface during this work — file separately

### Pipeline checklist

- [x] `tech-lead` reads this WIP + `FLAKY_TESTS.md` + the failing test bodies + the working sibling tests in the same describe blocks. Applies `superpowers:systematic-debugging` skill explicitly.
- [x] For routines-rename: reproduce locally (`--repeat-each=10/15`, characterized 3/10 → 0/10 → 1/15 ≈ 11 % flake rate, failure mode confirmed via screenshot — `flutterLongPress` firing onTap not onLongPress).
- [x] For S12: reproduce locally (1/10 with `--repeat-each=10` in isolation). Failure mode is `Test timeout of 60000ms exceeded`, NOT "Target page closed" as suspected. Page snapshot at timeout confirms the test reached destination state (Bulwark class, chest rank 5) — Playwright killed it for taking too long.
- [x] Apply systematic-debugging phases. Form ONE hypothesis at a time. Test minimally.
- [x] After fix attempts: verify with `--repeat-each` consecutive passes — routines 40/40, S12 20/20.
- [x] FLAKY_TESTS.md updated: dated state-as-of-2026-05-11 narrative added, entry #22 retired, "Active flaky tests" table now empty.
- [x] PLAN.md Active Backlog "Known flaky e2e tests" updated with resolution notes + Phase 22 deferred-work line marked RESOLVED.
- [ ] Orchestrator runs CI verification — confirms no regressions on full E2E suite.
- [ ] PR opened with summary of root causes found + fixes applied + any remaining `@flaky` tags with rationale.
- [ ] `reviewer` flags addressed in same cycle (no deferral, per memory rule).
- [ ] Squash merge to `main`; close WIP section.

### Fixes landed (this branch)

1. **`test/e2e/helpers/app.ts`** — `flutterLongPress` rewritten to compute element centre via `boundingBox()` once, then re-anchor cursor with `mouse.move(cx, cy)` after `mouse.down()` and again before `mouse.up()`. Default hold raised 800 ms → 1000 ms. Mitigates Chromium pointer-event jitter that was rejecting Flutter's `LongPressGestureRecognizer` mid-hold and letting the tap recognizer fire on pointerup.
2. **`test/e2e/specs/saga.spec.ts`** — S12 `@flaky` tag removed from describe block; `test.setTimeout(120_000)` added inside the test with explanatory comment. Surgical to S12 — the global 60 s default is correct for every other E2E test.
3. **`test/e2e/FLAKY_TESTS.md`** — dated state-as-of-2026-05-11 resolution narrative added; entry #22 retired from "Active flaky tests" (table now empty).
4. **`PLAN.md`** — Active Backlog "Known flaky e2e tests" updated; Phase 22 deferred-work line marked RESOLVED.
