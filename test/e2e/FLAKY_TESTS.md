# Flaky & Failing E2E Tests

This is a **debt register**, not a permanent home. The goal is to converge to zero entries here. Every test listed below is a latent bug — either a real production race, a missing wait, a timing assumption, or a seed-isolation gap — and we treat it as such.

**State as of 2026-04-28 (post PR #116):** All 5 flake families (entries #1–#13, #15, #16, #17, #20, #21) discharged via PR #116. Only test-methodology carryovers remain — these are not bugs in production code or test code; they're artifacts of `--repeat-each=N` itself (Supabase local rate limits + shared-user state accumulation). They pass reliably in normal CI single-run mode and in independent runs.

**State as of 2026-05-06 (Phase 21):** S4 + S4b (`rank-up-celebration.spec.ts` overflow card) were briefly tagged `@flaky` after CI hit 4 vCPU saturation at workers=4. Root cause was e2e assertions on Flutter `Timer.delayed` animation timing (1.1 s overlay holds, 4 s overflow auto-dismiss) that race against real wall-clock under any CPU contention. Discharged in the same PR by trimming the e2e assertions to the integration property the test exists to verify (cap-at-3 produces a visible overflow card with the correct `+N ranks` label; tap routes to /profile) and leaving the auto-dismiss timing to its widget test (`celebration_overflow_card_test.dart` — `tester.pump(Duration)` against a fake clock). Tag removed; verified 16 consecutive passes across workers=3 / workers=4 with `--repeat-each=5`.

**State as of 2026-05-11 (PR-4 QA gate):** S12 (`saga.spec.ts` class-badge update after rank cross) tagged `@flaky`. Full-suite run at workers=4 hits a 60s test timeout when CPU saturation extends the `dismissCelebrationIfPresent(25_000)` budget past the test-level wall-clock limit. Passes 100% in isolation (49.4s solo run). Root cause is the celebration overlay's `Timer.delayed` animation chain (~4–6s total) consuming most of the 60s budget under contention, leaving no slack for the subsequent `navigateToTab` → `waitFor` chain. Not a PR-4 regression — PR-4 did not touch `finishWorkout`, celebration logic, or RPG. Active investigation entry below.

**State as of 2026-05-11 (E2E flake root-cause investigation, branch `fix/e2e-flakes-routines-rename-and-s12-saga`):**

Two flakes resolved deterministically (20/20 and 40/40 consecutive passes locally):

1. **`routines.spec.ts` "should edit a routine name via the action sheet" + "should delete a routine and remove it from the list"** — same family. Failure rate ~10–30 % under `--repeat-each=10–15` in isolation. Root cause: `flutterLongPress` in `helpers/app.ts` was firing `onTap` instead of `onLongPress` intermittently. Failure screenshots showed the routine had been STARTED (active workout, "00:09" timer) — proving Flutter's tap recognizer won the gesture arena, not the long-press recognizer. Likely mechanism: between `mouse.down()` and `mouse.up()` (800 ms inert wait), Chromium intermittently dispatches a synthetic `pointermove` (sub-pixel jitter) or `pointercancel` event that rejects Flutter's `LongPressGestureRecognizer`, allowing `TapGestureRecognizer` to fire on pointerup. **Fix:** rewrote `flutterLongPress` to (a) compute the element centre once via `boundingBox()`, (b) re-anchor the cursor with `mouse.move(cx, cy)` immediately after `mouse.down()` and again before `mouse.up()` to invalidate stale browser pointer state and guarantee the up coordinate matches the down coordinate exactly, (c) hold for 1000 ms (default raised from 800 ms) to comfortably exceed Flutter's 500 ms long-press threshold under contention. Verified 40/40 consecutive passes (15 + 15 + 20 + 30 across edit/delete combinations).

2. **`saga.spec.ts:437` S12 "should update class badge after chest crosses rank 5"** — was tagged `@flaky` (entry #22 below). Failure rate 1/10 in isolation under `--repeat-each=10`. Root cause confirmed exactly as PR-4 QA hypothesized: the test runs the longest single user flow in the suite (ProfileNav → empty workout → addExercise → 2 set inputs → completeSet → finishWorkout → ClassChangeOverlay wait → `dismissCelebrationIfPresent(25_000)` → ProfileNav → character-sheet assertions). Successful runs land at 24–35 s; failure mode is the celebration sequence consuming its full 25 s budget plus the 12 s overlay loop, pushing total wall-clock past the 60 s test cap. Failure page snapshot confirms: page is on the Saga tab with class flipped to "Bulwark" (post-rank-up state) and chest at rank 5 — i.e. the test reached the destination state but Playwright killed it for taking too long. NOT a "Target page closed" worker crash as originally suspected; a plain `Test timeout of 60000ms exceeded`. **Fix:** `test.setTimeout(120_000)` on this single test. Chose the local-timeout-bump path (FLAKY_TESTS option (a)) over modifying shared `finishWorkout` helper (option (b)) because eight other specs depend on `finishWorkout` and changing its semantics ripples across the suite; over fast-tracking celebration animations in test mode (option (c)) because that would weaken what the test exists to validate. The celebration timeline (1.6 s ClassChangeOverlay + 1.1 s rank-up + 1.1 s level-up + 1.1 s title) is correct production behaviour; the test must wait it out, and 60 s is simply the wrong budget for this scenario. Tag removed; entry #22 retired. Verified 20/20 consecutive passes (10 + 10).

## How this doc is used

- `qa-engineer` excludes anything tagged `@flaky` from Stage 2 of the staged-run strategy and routes it through Stage 3 with `--retries=2` instead.
- When a new flake appears, add a row here, tag the test `@flaky`, and open or update an investigation entry.
- When a test passes 5 consecutive runs (cross-PR, cross-platform), remove the `@flaky` tag AND delete its entry here.
- A flaky test that fails 3× in a row in Stage 3 has drifted toward "broken." Promote to a real bug report against `lib/**` (tech-lead) or `test/e2e/**` (qa-engineer self).

## Active flaky tests

_None._ All previously-tagged flakes have been root-caused and discharged — see the dated state notes above for the resolution narrative of each.

## Carryover entries (test-methodology, not bugs)

These tests pass reliably in CI single-run and in independent reproductions; they only fail under `--repeat-each=N` due to constraints of the test harness itself, not production code or selectors.

| # | Spec | Test | Carryover root cause | Resolution path |
|---|------|------|----------------------|-----------------|
| 14 | `specs/workouts.spec.ts` | navigate-after-finish | Under `--repeat-each=10` hits Supabase local `sign_in_sign_ups` rate limit (30/5 min); auth returns "Wrong email or password" from repeat 3 onward. Phase 18c fixed the actual nav-timing bug — passes 5/5 in independent runs. | Raise `sign_in_sign_ups` in `supabase/config.toml` for local dev, OR restructure to use per-repeat throwaway users. Not a CI blocker. |
| 18 | `specs/home.spec.ts` | history-nav | Under `--repeat-each=10`: `fullHome` user accumulates workouts across repeats → heavier XP calc → home `ActionHero` loads slower than 15s assertion. Passes 5/5 in independent runs. | Add `waitForURL('**/home**')` + `waitForSelector` on status-line after `dismissCelebrationIfPresent`, OR raise the home-state assertion timeout beyond 15s. |
| 19 | `specs/home.spec.ts` | quick-workout | Same root cause as #18 — `home-quick-workout` not visible after `dismissCelebrationIfPresent` at repeat 4 (workers=2) / repeat 7 (workers=1). Passes 5/5 independently. | Same fix as #18. |

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
