# Flaky & Failing E2E Tests

This is a **debt register**, not a permanent home. The goal is to converge to zero entries here. Every test listed below is a latent bug — either a real production race, a missing wait, a timing assumption, or a seed-isolation gap — and we treat it as such.

**State as of 2026-04-28 (post PR #116):** All 5 flake families (entries #1–#13, #15, #16, #17, #20, #21) discharged via PR #116. Only test-methodology carryovers remain — these are not bugs in production code or test code; they're artifacts of `--repeat-each=N` itself (Supabase local rate limits + shared-user state accumulation). They pass reliably in normal CI single-run mode and in independent runs.

**State as of 2026-05-06 (Phase 21):** S4 + S4b (`rank-up-celebration.spec.ts` overflow card) were briefly tagged `@flaky` after CI hit 4 vCPU saturation at workers=4. Root cause was e2e assertions on Flutter `Timer.delayed` animation timing (1.1 s overlay holds, 4 s overflow auto-dismiss) that race against real wall-clock under any CPU contention. Discharged in the same PR by trimming the e2e assertions to the integration property the test exists to verify (cap-at-3 produces a visible overflow card with the correct `+N ranks` label; tap routes to /profile) and leaving the auto-dismiss timing to its widget test (`celebration_overflow_card_test.dart` — `tester.pump(Duration)` against a fake clock). Tag removed; verified 16 consecutive passes across workers=3 / workers=4 with `--repeat-each=5`.

## How this doc is used

- `qa-engineer` excludes anything tagged `@flaky` from Stage 2 of the staged-run strategy and routes it through Stage 3 with `--retries=2` instead.
- When a new flake appears, add a row here, tag the test `@flaky`, and open or update an investigation entry.
- When a test passes 5 consecutive runs (cross-PR, cross-platform), remove the `@flaky` tag AND delete its entry here.
- A flaky test that fails 3× in a row in Stage 3 has drifted toward "broken." Promote to a real bug report against `lib/**` (tech-lead) or `test/e2e/**` (qa-engineer self).

## Carryover entries (test-methodology, not bugs)

These tests pass reliably in CI single-run and in independent reproductions; they only fail under `--repeat-each=N` due to constraints of the test harness itself, not production code or selectors.

| # | Spec | Test | Carryover root cause | Resolution path |
|---|------|------|----------------------|-----------------|
| 14 | `specs/workouts.spec.ts` | navigate-after-finish | Under `--repeat-each=10` hits Supabase local `sign_in_sign_ups` rate limit (30/5 min); auth returns "Wrong email or password" from repeat 3 onward. Phase 18c fixed the actual nav-timing bug — passes 5/5 in independent runs. | Raise `sign_in_sign_ups` in `supabase/config.toml` for local dev, OR restructure to use per-repeat throwaway users. Not a CI blocker. |
| 18 | `specs/home.spec.ts` | history-nav | Under `--repeat-each=10`: `fullHome` user accumulates workouts across repeats → heavier XP calc → home `ActionHero` loads slower than 15s assertion. Passes 5/5 in independent runs. | Add `waitForURL('**/home**')` + `waitForSelector` on status-line after `dismissCelebrationIfPresent`, OR raise the home-state assertion timeout beyond 15s. |
| 19 | `specs/home.spec.ts` | quick-workout | Same root cause as #18 — `home-quick-workout` not visible after `dismissCelebrationIfPresent` at repeat 4 (workers=2) / repeat 7 (workers=1). Passes 5/5 independently. | Same fix as #18. |
| 22 | `specs/workouts.spec.ts` | `Workout loading overlay cancel (PR1 — Q1)` → `should show Cancel button immediately on loading overlay and restore workout on tap (PR1 — Q1)` | **RESOLVED in PR #198 (PR-2 of audit fix wave).** Two attempts to "fix the cleanup": (1) replace discard chain with `page.goto('/')` — failed because Hive still has the active workout so app auto-resumes; (2) **shipped fix:** drop the cleanup entirely. Q1 product contract is asserted at lines 1428-1441 (Cancel visible from t=0 → restores workout → overlay dismissed). Cleanup is optional: Playwright per-test browser context isolation wipes Hive between tests, and `smokeWorkoutCancelStart` is dedicated to this single test. Server-side workout row stays `is_active: true` (harmless — `loadActiveWorkout` reads from Hive, not the server). `@flaky` tag will be removed in PR-2's post-merge cleanup PR. |

## Investigation playbook

For any flake or hard failure, the systematic approach:

1. **Reproduce.** `--repeat-each=5 --retries=0 --grep "<test name>"`. Confirm consistent vs intermittent.
2. **Capture.** stderr (`2>&1`), screenshot, page console logs (`page.on('console')`). Pin down exact failure point.
3. **Categorize.**
   - **Test-infra:** missing `waitFor*`, racy fixture setup, helper chain assumes ordering — fix in `test/e2e/`.
   - **Prod-code:** real lazy-init bug, race in Riverpod refresh, swallowed exception, navigation racing dialog — bug report → tech-lead.
4. **Fix.** Deterministic wait > timeout-based polling. If you can replace `waitForTimeout(N)` with `waitForResponse(...)` or `waitForSelector(...)`, do it.
5. **Verify.** `--repeat-each=20 --retries=0` against the fix. 20/20 stable before claiming "fixed."
6. **Discharge.** Remove `@flaky` tag, delete entry from this doc, commit with rationale.

When a phase touches code in any flake-prone area, the agent driving that phase is responsible for verifying its tests against this register and either fixing the relevant entries or confirming "no longer reproduces, removed from doc."
