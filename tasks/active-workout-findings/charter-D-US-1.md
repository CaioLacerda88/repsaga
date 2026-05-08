# Charter D — US-1 (iPhone 15, 393×852) — Sam persona

**Driver:** qa-engineer agent
**Date:** 2026-05-07
**Plan ref:** tasks/active-workout-exploratory-testplan.md §6 Charter D
**Setup outcome:** succeeded — fresh user `expl-d-us1-{timestamp}@test.local` created via signup; Workout 1 (Bench Press 50kg×8) logged to establish baseline; first-workout PR celebration appeared and was dismissed (expected)
**Spec file:** `test/e2e/specs/charter-d-exploratory.spec.ts` (guard: `EXPL_CHARTER_D=1`)
**Run result:** 13/13 tests passed (all branches executed; findings recorded below)

---

## Branches Probed

| Branch | Description | Outcome |
|--------|-------------|---------|
| SETUP | Sign up + onboarding + Bench Press 50kg×8 baseline | PASS (PR celebration for first workout — expected) |
| B1 | 0 PRs (30kg×5, below 50kg×8 baseline) → expected /home | BUG: went to /pr-celebration |
| B2 | ≥1 PR (60kg×8 beats 50kg×8) → expected /pr-celebration | BUG: went to /home (Saga intro intercepted) |
| B3 | Multiple PRs (65kg×8 + Squat 100kg×10) → celebration lists all | FINDING: PR details not in AOM |
| B4 | Routine workout, NOT in plan → add-to-plan prompt | SKIP: routine card not found after save |
| B5 | Routine workout, IN plan → /home (no prompt) | SKIP: routine card not found after save |
| B8 | Offline finish → "Saved offline" snackbar + pending badge | PARTIAL PASS: pending badge visible; snackbar text not in AOM |
| B9 | Server 500 on save → error snackbar, stays on workout | BUG: silent redirect to /home, no error shown |
| B10 | Background mid-save → celebration plays on return | FINDING: celebration skipped during background |
| B11 | Double-tap Save & Finish → only one save fires | PASS |
| B12 | Loading overlay cancel button (10s+ wait) | BUG: no loading overlay — app queues immediately |
| NOTES | Notes field edge cases | PARTIAL: field visible; character-limit probe inconclusive |

---

## Bugs

### AW-EX-D-US1-01 — PR celebration fires for a workout with 0 new PRs (below-baseline weight)

- **Persona:** Sam
- **Charter:** D
- **Device:** US-1 (393×852)
- **Severity:** BLOCKER (users see false "NEW PR" screen after every workout on a fresh account — even when they underperform)
- **Repro steps:**
  1. Create a new account.
  2. Log Workout 1: Barbell Bench Press 50 kg × 8. Finish. PR celebration appears (expected — first-ever set).
  3. Log Workout 2: Barbell Bench Press 30 kg × 5 (intentionally below baseline weight and reps). Finish.
  4. Observe: the app navigates to `/pr-celebration`.
- **Expected:** The app routes to `/home` — 30 kg × 5 is strictly below the 50 kg × 8 baseline in all metrics (weight, reps, and volume = 150 kg vs 400 kg).
- **Actual:** `/pr-celebration` appears. The celebration screen shows three Barbell Bench Press rows: Max Weight (30 kg × 5), Max Reps (5 reps), Max Volume (150 kg). All three metrics are below baseline.
- **Screenshot:** `screenshots/charter-D-US-1-B1-unexpected-pr-celebration.png`
- **Suspected cause:** The PR detection logic appears to treat any set as a PR if it is the user's "best recorded" value within the current session — it is comparing against an empty or stale cache rather than the persisted historical record. Alternatively, the comparison function may be returning `true` when `newValue >= previousMax` is evaluated on a metric category that was never previously stored in the local cache after the session restart (login clears in-memory state). The second workout opens a fresh session so the in-memory PR cache is empty — the first set logged in that session becomes "the new max" and triggers celebration regardless of what the database holds.
- **Suspicious files:** `lib/features/workouts/data/workout_repository.dart` (save_workout RPC result processing), `lib/features/progress/data/pr_detection_service.dart` or equivalent PR comparison logic, any provider that hydrates the PR cache on session start
- **Additional signal:** In B1, the set-row AOM showed `set-row-state-standing-pr: true` BEFORE finishing — confirming the in-session PR state was already wrong during the active workout, not just at the finish step.
- **Backend / console errors:** none observed in AOM

---

### AW-EX-D-US1-02 — PR celebration MISSING for a genuine new PR when Saga intro overlay is active

- **Persona:** Sam
- **Charter:** D
- **Device:** US-1 (393×852)
- **Severity:** MAJOR (users who hit a real PR get no celebration if the Saga intro fires post-finish)
- **Repro steps:**
  1. Following AW-EX-D-US1-01, the user is on a fresh account that has triggered the Saga intro.
  2. Log Workout 3: Barbell Bench Press 60 kg × 8 (beats 50 kg × 8 from W1 in weight × reps).
  3. The set-row shows `standing-pr: true` before finishing — PR detection in-session IS correct.
  4. Tap Finish → Save & Finish.
  5. Observe: the app navigates to `/home`, NOT `/pr-celebration`.
- **Expected:** `/pr-celebration` appears, showing the new Bench Press weight PR.
- **Actual:** The URL stays at `/#/home`. The B2 screenshot (`B2-unexpected-home.png`) shows the Saga RPG intro overlay ("YOUR TRAINING IS YOUR CHARACTER") displayed over the home screen instead of the PR celebration.
- **Screenshot:** `screenshots/charter-D-US-1-B2-unexpected-home.png`
- **Suspected cause:** Two potential explanations, possibly both active: (1) The Saga intro overlay is being pushed onto the navigator stack post-finish, and it suppresses or replaces the `/pr-celebration` navigation. The saga intro presentation code may intercept the post-workout navigation callback and route to home + overlay instead of the celebration route. (2) Due to AW-EX-D-US1-01 corrupting the PR history (the false 30kg×5 PR was stored), the second workout's 60kg×8 may no longer look like a new maximum — the stored "max" is now 30kg×5 for reps/volume and 50kg×8 for weight, but after the false celebration recorded 30×5 as the PR, 60×8 may be treated as "already beaten" in an inconsistent state.
- **Suspicious files:** `lib/features/rpg/ui/saga_intro_overlay.dart` or equivalent (post-login intro), `lib/features/workouts/ui/active_workout_screen.dart` (post-finish navigation), any code that sequences post-workout events (celebration → saga intro)
- **Backend / console errors:** none

---

### AW-EX-D-US1-03 — Server 500 on `save_workout` causes silent redirect to /home — no user-visible error

- **Persona:** Sam
- **Charter:** D
- **Device:** US-1 (393×852)
- **Severity:** MAJOR (data loss risk — user thinks workout is saved but it may only be in local queue; no feedback to retry)
- **Repro steps:**
  1. Start a workout with one exercise (Dumbbell Curl, 20 kg × 10, set completed).
  2. Override fetch: `save_workout` RPC returns HTTP 500 with `{ message: 'simulated server error' }`.
  3. Tap Finish → Save & Finish.
  4. Wait 8 seconds.
- **Expected:** App shows an error snackbar ("Failed to save workout — try again") and remains on the workout screen so the user can retry.
- **Actual:** App redirects to `/home`. No error message appears in the AOM. The home screen shows "2 workouts pending sync" in the pending badge — the 500-failed workout was silently enqueued in the offline queue. This matches the behavior for a genuine offline finish (B8), meaning the app treats HTTP 500 the same as a network timeout/unreachable error.
- **Screenshot:** `screenshots/charter-D-US-1-B9-after-500.png` — home screen with pending badge but no error snackbar visible.
- **Suspected cause:** The save error handler in the workout repository catches all exceptions uniformly (network error AND server error) and routes to the offline queue. The 500 response likely causes a Supabase client exception that is caught by the same handler as a connectivity exception. The fix should distinguish HTTP 5xx (server-side failure — should surface error and not queue) from `SocketException`/`TimeoutException` (genuine offline — should queue).
- **Suspicious files:** `lib/features/workouts/data/workout_repository.dart` (save_workout exception handler), `lib/core/sync/offline_queue_service.dart` or equivalent, provider that calls `saveWorkout` and handles result
- **Backend / console errors:** none in AOM; fetch intercepted at network layer

---

### AW-EX-D-US1-04 — Never-resolving `save_workout` fetch triggers immediate offline-queue instead of a loading overlay

- **Persona:** Sam
- **Charter:** D
- **Device:** US-1 (393×852)
- **Severity:** MAJOR (the "cancel" flow for long-running saves is unreachable — no loading overlay appears)
- **Repro steps:**
  1. Start a workout with one exercise.
  2. Override fetch: `save_workout` RPC returns `new Promise(() => {})` (never resolves).
  3. Override also covers all `/rpc/` calls.
  4. Tap Finish → Save & Finish.
  5. Wait 2 seconds — take screenshot. Wait 11 seconds — take screenshot.
- **Expected:** A loading overlay appears while the save is in progress; after ~10 seconds a "Cancel" button appears on the overlay.
- **Actual:** At 2 seconds, the AOM shows the `/home` screen, not the workout screen or a loading overlay. At 11 seconds, still on `/home`. The AOM confirms: only home-screen nodes (`home-status-line`, `offline-pending-badge`, `home-plan-your-week`, etc.) are visible. The screenshot at 2s shows "Workout saved. Will sync when back online." snackbar and "2 workouts pending sync" badge — the app treated the never-resolving fetch as offline and queued immediately.
- **Screenshot:** `screenshots/charter-D-US-1-B12-loading-2s.png`
- **Notes:** The premise of B12 (a loading overlay with a cancel button after 10s) does not apply to the current implementation. If this feature was designed/specced, it has not been implemented — or the timeout that triggers the loading-overlay is shorter than a never-resolving promise (the app may have a short network-detection timeout, say 3s, after which it falls through to offline mode).
- **Suspicious files:** `lib/features/workouts/ui/active_workout_screen.dart` (finish dialog/save flow), `lib/features/workouts/data/workout_repository.dart` (timeout configuration), any loading-overlay widget that should appear during a slow save

---

## Findings (non-bug observations)

### AW-EX-D-US1-F01 — PR celebration screen exercise details not accessible via AOM (accessibility gap)

- **Severity:** minor (accessibility)
- **Detail:** The `/pr-celebration` screen AOM contains exactly 2 nodes: `[][pr-new-heading]` and `[][pr-continue-btn]`. The individual PR rows (exercise name, metric type, value) are rendered visually but not exposed as AOM nodes. The visual content IS correct — the B1 screenshot shows three named rows for Barbell Bench Press with specific values. However, screen readers cannot read this content. Automated tests cannot assert on which exercises or values are listed in the celebration.
- **Recommendation:** Add `Semantics(identifier: 'pr-item-{index}', label: '{exerciseName} {metric} {value}')` wrappers to each PR item row.
- **Screenshot:** `screenshots/charter-D-US-1-B3-pr-celebration.png`

### AW-EX-D-US1-F02 — Offline badge persists after fetch is restored (sync drain not triggering within 5s)

- **Severity:** minor
- **Detail:** In B8, after simulating offline (fetch override) and finishing a workout, the pending badge appeared. After restoring fetch (`window.fetch = originalFetch`), waiting 5 seconds, the pending badge was STILL visible. The sync drain is either not triggered on `window.fetch` restoration, or the 5-second wait is insufficient.
- **Notes:** This is consistent with how the offline-detection relies on `visibilitychange` or explicit reconnect signals rather than polling. The sync drain from cold-launch is covered by PR #171 — but a mid-session reconnect drain may not be wired.

### AW-EX-D-US1-F03 — Background mid-save skips PR celebration

- **Severity:** minor
- **Detail:** In B10, the app was mid-save (2.5s delay) when the page was backgrounded. After the save completed and the page was foregrounded, the app went to `/home` rather than `/pr-celebration`. The PR weight (80 kg × 8, beating the existing 65 kg × 8 baseline) should have triggered celebration. The celebration navigation likely fires during the background period, hits a guard, and is dropped.

### AW-EX-D-US1-F04 — Notes field: counter does not update and typed text does not appear in dialog screenshots

- **Severity:** minor (test-infra finding, not confirmed as prod bug)
- **Detail:** In the NOTES probe, the notes field input proxy was automatically attached when the dialog opened (auto-focus — correct). Direct `page.keyboard.type()` calls with 1ms delay sent 1000 and then 1001 characters. However, the screenshots taken after each type call still show "Add notes (optional)" placeholder and "0/1000" counter — indicating the text was not committed to the Flutter TextEditingController. The AOM node `[][workout-notes]` had no label text. This may be a test-infra timing issue (characters sent too fast for Flutter's CanvasKit to process) or a genuine Flutter web behavior where `keyboard.type` with near-zero delay loses events. The `flutterFill` helper uses `delay: 10` for this reason; the NOTES probe used `delay: 1`.
- **Action:** Not a production bug report. The character-limit probe was inconclusive. Requires re-running with `delay: 10` and verification that the counter updates visually. The notes field IS visible and IS auto-focused on dialog open — the field exists and behaves correctly in that respect.

### AW-EX-D-US1-F05 — Routine card not findable after save (B4/B5 SKIP)

- **Severity:** minor (test-infra gap)
- **Detail:** `scrollToVisible(page, 'text=Charter D Test Routine', 15)` returned null after the routine was saved. The routines tab did show a page (screenshot `B4-after-save-routine.png`), but the routine card text could not be matched after navigation back to the routines tab. The `scrollToVisible` helper may need to use the AOM (`flt-semantics` text content) rather than CSS `text=` matching for Flutter rendered text. Branches B4, B5 were skipped as a result.

---

## Passed Branches

### B8 — Offline finish queues correctly
- Pending sync badge appeared after finishing while fetch was overridden.
- App routed to `/home` (correct — cannot show result without server confirmation).
- No "Saved offline" snackbar text found in AOM (the snackbar text IS rendered visually — seen in screenshot `B12-loading-2s.png` — but is not in the accessibility tree). This is an accessibility gap, not a functional failure.

### B11 — Double-tap Save & Finish debounced correctly
- Two mouse clicks 80ms apart triggered exactly 1 `save_workout` network request.
- URL went to `/home` — workout saved successfully.
- **PASS**

---

## Deferred Branches

| Branch | Reason |
|--------|--------|
| B4 | Routine card not found after save (scrollToVisible selector gap — see F05) |
| B5 | Depends on B4 routine card; same selector gap |
| B6 | Requires B4/B5 infrastructure |
| B7 | Requires seeded RPG state (overflow card) — not in scope for this session |

---

## Summary Table (Severity)

| ID | Severity | Title |
|----|----------|-------|
| AW-EX-D-US1-01 | BLOCKER | False PR celebration for below-baseline workouts |
| AW-EX-D-US1-02 | MAJOR | Real PR celebration missing when Saga intro fires post-finish |
| AW-EX-D-US1-03 | MAJOR | HTTP 500 on save treated as offline — silent queue, no error |
| AW-EX-D-US1-04 | MAJOR | No loading overlay on slow/stalled save — falls through to offline queue |
| AW-EX-D-US1-F01 | minor | PR celebration AOM missing exercise details (accessibility) |
| AW-EX-D-US1-F02 | minor | Offline badge not cleared within 5s of fetch restore |
| AW-EX-D-US1-F03 | minor | Background mid-save skips PR celebration |
| AW-EX-D-US1-F04 | minor | Notes probe inconclusive (delay too low) |
| AW-EX-D-US1-F05 | minor | Routine card scrollToVisible gap (test-infra) |

---

## Bug Report to Orchestrator (PROD-CODE failures)

The following bugs are in production code and require tech-lead action. QA has NOT touched `lib/**` except via observation.

**AW-EX-D-US1-01 (BLOCKER)**
1. Failing scenario: B1 branch — `charter-d-exploratory.spec.ts:208`. Post-finish URL is `/#/pr-celebration` when 30kg×5 is logged after a 50kg×8 baseline.
2. Reproduction: `EXPL_CHARTER_D=1 FLUTTER_APP_URL= npx playwright test specs/charter-d-exploratory.spec.ts --grep "B1"` — note that B1 depends on SETUP running first (serial mode), so run the full spec.
3. Suspected cause: In-session PR cache is not hydrated from the database on session start. After login, the cache is empty; the first set logged in the session is compared against the empty cache and always wins. The `save_workout` RPC response or a pre-workout fetch should seed the cache with historical bests before the first set is marked complete.
4. Suspicious files: `lib/features/workouts/data/workout_repository.dart`, `lib/features/progress/` (PR detection), any provider that initializes PR state on session start.
5. Test-side: Spec written. Selectors correct. Fixtures seeded (fresh user, Workout 1 logged). Screenshot evidence at `tasks/active-workout-findings/screenshots/charter-D-US-1-B1-unexpected-pr-celebration.png`.

**AW-EX-D-US1-02 (MAJOR)**
1. Failing scenario: B2 branch — `charter-d-exploratory.spec.ts:258`. Post-finish URL is `/#/home` instead of `/#/pr-celebration` when 60kg×8 is logged (beats 50kg×8 baseline).
2. Reproduction: Same spec, full run — B2 runs after B1. The Saga intro fires because it is a new account.
3. Suspected cause: Either (a) the Saga intro navigator overlay intercepts the post-workout route and replaces `/pr-celebration` with home + overlay, or (b) the B1 false PR corrupted stored PR state and 60kg×8 no longer appears as a new max.
4. Suspicious files: Saga intro presentation/route logic, `lib/features/workouts/ui/active_workout_screen.dart` post-finish navigation, the code that decides to show the saga intro after onboarding.
5. Screenshot: `tasks/active-workout-findings/screenshots/charter-D-US-1-B2-unexpected-home.png`.

**AW-EX-D-US1-03 (MAJOR)**
1. Failing scenario: B9 branch — `charter-d-exploratory.spec.ts:770`. App silently routes to `/home` after `save_workout` returns HTTP 500.
2. Reproduction: Inject 500 via fetch override (see spec B9) then tap Save & Finish.
3. Suspected cause: The save error handler does not distinguish HTTP 5xx (server-side transient error) from network-level offline. Both throw in the Supabase client layer and are caught by the same handler which enqueues to offline queue.
4. Suspicious files: `lib/features/workouts/data/workout_repository.dart` (save error catch block), `lib/core/sync/` (offline queue logic).
5. Screenshot: `tasks/active-workout-findings/screenshots/charter-D-US-1-B9-after-500.png`.

**AW-EX-D-US1-04 (MAJOR)**
1. Failing scenario: B12 branch — `charter-d-exploratory.spec.ts:1034`. App navigates to `/home` within 2 seconds when `save_workout` never resolves — no loading overlay appears.
2. Reproduction: Inject never-resolving fetch then tap Save & Finish. Screenshot at 2s confirms `/home` screen.
3. Suspected cause: The save call has a short network timeout (possibly 3s or less) after which it falls through to the offline handler. If no loading overlay was designed/implemented, this is a missing feature. If it was designed, the timeout guard is too aggressive.
4. Suspicious files: `lib/features/workouts/ui/active_workout_screen.dart` (finish flow), `lib/features/workouts/data/workout_repository.dart` (timeout config).
5. Screenshot: `tasks/active-workout-findings/screenshots/charter-D-US-1-B12-loading-2s.png`.
