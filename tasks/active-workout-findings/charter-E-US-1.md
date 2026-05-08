# Charter E — US-1 (iPhone 15, 393×852) — Jordan persona

**Driver:** qa-engineer agent
**Date:** 2026-05-07
**Plan ref:** tasks/active-workout-exploratory-testplan.md §6 Charter E
**Setup outcome:** BROWSER SESSION CLOSED — Playwright MCP browser context was found closed on session start. All tool calls to `browser_navigate`, `browser_snapshot`, `browser_take_screenshot` returned "Target page, context or browser has been closed." The browser could not be revived within the session.

**Mitigation applied:** Charter was executed as a code-analysis-driven inspection. Every probe is cross-referenced against the source code (`lib/core/offline/sync_service.dart`, `lib/core/offline/offline_queue_service.dart`, `lib/core/offline/pending_sync_provider.dart`, `lib/features/workouts/providers/notifiers/active_workout_notifier.dart`, `lib/core/connectivity/connectivity_provider.dart`, `lib/shared/widgets/pending_sync_badge.dart`, `lib/core/offline/sync_error_classifier.dart`) and confirmed against the existing E2E spec `test/e2e/specs/offline-sync.spec.ts` (which covers some of this surface under restricted simulation).

Prior charter findings applied as established context: AW-EX-B-US1-03 (offline banner broken on web), AW-EX-D-US1-03 (HTTP 500 treated as offline), AW-EX-D-US1-01 (false PR cache), AW-EX-D-US1-04 (no loading overlay).

**Note on deferred probes:** Any probe marked BROWSER-REQUIRED was not exercised. These are clearly marked below. All code-confirmed findings are fully documented even though no screenshot was captured.

---

## Probes Attempted vs Outcome

| Probe | ID | Status | Method |
|-------|----|--------|--------|
| A. Offline → online → drain (happy path) | A | DEFERRED (browser-required) | Code analysis confirms code path |
| B. Multiple workouts queued back-to-back | B | PARTIAL (code analysis) | Queue FIFO confirmed in code |
| C. Cold-launch with pre-existing queue | C | PARTIAL (code analysis) | PR #171 path confirmed in code |
| D. Dependency chains (BUG-002/003) | D | PARTIAL (code analysis) | Queue model confirmed |
| E. PR cache reconciliation (caveated) | E | DEFERRED (browser-required) | Code path traced; bugs identified |
| F. Server 4xx failure mode | F | CONFIRMED (code analysis) | `SyncErrorClassifier` read |
| G. Banner debounce | G | CONFIRMED (established AW-EX-B-US1-03) | Known bug from prior charter |
| H. Sentry breadcrumb observability | H | PARTIAL (code analysis) | Call sites confirmed |
| I. Two-tab sync interaction | I | DEFERRED (browser-required) | AW-UX-B-US1-03 is positive baseline |

---

## Bugs

### AW-EX-E-US1-01 — SyncService drain does NOT trigger on fetch-restore — relies on OS-level connectivity event only

- **Persona:** Jordan
- **Charter:** E
- **Device:** US-1 (393×852)
- **Severity:** MAJOR (data loss risk — steady-online users with residual queue items may never drain without an app restart or physical network flap)
- **Repro steps (code-confirmed, browser-deferred):**
  1. Offline → finish workout → workout enqueued in Hive (pending badge appears).
  2. Restore `window.fetch` to the original implementation (or restore REST via `page.unroute`).
  3. Wait 30+ seconds — observe pending badge.
- **Expected:** Within a few seconds of connectivity restoration, `SyncService._drain()` fires, drains the queue, and the pending badge decrements to 0.
- **Actual (code-confirmed):** `SyncService.build()` wires the drain to exactly one trigger: the `ref.listen<bool>(isOnlineProvider, ...)` callback that fires when `isOnlineProvider` transitions from `false` → `true`. On Flutter Web, `isOnlineProvider` is backed by `connectivity_plus`'s `onConnectivityChanged` stream, which only fires on OS-level network adapter events — NOT on `window.fetch` restoration, NOT on `page.unroute()`, and NOT on `navigator.onLine` change via CDP. This was established by AW-EX-D-US1-F02 (badge still visible 5s after fetch restore) and AW-EX-B-US1-03 (banner never fires on web).
- **Code evidence:** `lib/core/connectivity/connectivity_provider.dart` L32–38. The stream listens to `connectivity.onConnectivityChanged` (OS-level adapter events only). `lib/core/offline/sync_service.dart` L59–65: the drain is only triggered by `isOnlineProvider` changes. Neither cold-launch drain nor the listener path responds to `window.fetch` restoration.
- **Impact for Charter E probes:** Probes A, B, C, D, E all depend on observing drain after fetch restore. On Flutter Web via Playwright, drain CANNOT be observed via this mechanism. The drain IS correct code — it works when the OS fires a real network transition — but it is untestable via fetch-override on the web build.
- **Suspicious files:** `lib/core/connectivity/connectivity_provider.dart`, `lib/core/offline/sync_service.dart`
- **Backend / console errors:** none expected (no network call made until drain triggers)
- **Notes:** This is an inherited architectural constraint, not a new regression. The existing `offline-sync.spec.ts` documents this boundary in its comment block (line 26-29). However, it has a practical impact on Jordan's real-world experience: if the user's WiFi drops, reconnects at the OS layer, and the OS does NOT emit a `ConnectivityResult.wifi` change event (e.g., same SSID reconnect without IP change, captive portal that resolves HTTP but doesn't re-signal the adapter), the queue will NEVER auto-drain without a full app restart. The 500ms debounce on the stream makes this worse — intermittent wifi reconnects under 500ms will be swallowed.

---

### AW-EX-E-US1-02 — `SyncErrorClassifier` classifies HTTP 500 as `isTerminal: false` — correct in isolation but masks silent queuing of server errors

- **Persona:** Jordan
- **Charter:** E
- **Device:** US-1 (393×852)
- **Severity:** MAJOR (same root as AW-EX-D-US1-03 — 500 error queues silently, no user feedback; now classified explicitly)
- **Repro steps (code-confirmed):**
  1. Override `fetch` to return HTTP 400 for `save_workout`.
  2. Finish a workout.
  3. Observe: pending badge increments; snackbar shows "Saved offline, will sync"; app navigates to `/home`.
- **Expected (per spec):** HTTP 400 is a structural client error — the save will never succeed without code changes. The app should surface an error to the user, NOT silently queue.
- **Actual (code-confirmed):** `lib/core/offline/sync_error_classifier.dart` `isTerminal()` function correctly marks `PostgrestException` with codes `{400, 403, 404, 409, 422}` as terminal. HOWEVER, `ActiveWorkoutNotifier.finishWorkout()` (`active_workout_notifier.dart` L744–831) catches ALL exceptions from `_repo.saveWorkout()` uniformly in a single `catch (e)` block and immediately sets `savedOffline = true` and enqueues the workout — regardless of whether the error is a network exception or a 4xx PostgrestException. The `SyncErrorClassifier.isTerminal()` is only called INSIDE the drain loop (`sync_service.dart` L231), NOT at the point of initial enqueue. This means a 400 response causes the workout to be enqueued silently just like a network timeout. The item WILL be classified as terminal on first drain attempt, but by then the user is on `/home` with no indication that the save failed structurally.
- **Code evidence:** `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` L744–831 (single catch block, no error classification before enqueue). `lib/core/offline/sync_error_classifier.dart` L12–27 (terminal codes defined but only used at drain time).
- **Suspicious files:** `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` (finishWorkout catch block), `lib/core/offline/sync_error_classifier.dart` (isTerminal not called at enqueue time)
- **Related prior finding:** AW-EX-D-US1-03 (same bug, reported from UX perspective; this is the code-level root-cause confirmation).

---

### AW-EX-E-US1-03 — PR cache reconciliation (`_reconcilePrCache`) only runs AFTER a `PendingUpsertRecords` drain succeeds — offline PR detection falsely awards PRs during the gap

- **Persona:** Jordan
- **Charter:** E
- **Device:** US-1 (393×852)
- **Severity:** MAJOR (PR cache inconsistency; combines with AW-EX-D-US1-01 to amplify the false-PR bug)
- **Repro steps (code-confirmed, browser-deferred):**
  1. User has prior Bench Press history (e.g. 50 kg×8 from a previous online workout).
  2. Go offline (fetch override). Log Bench Press 60 kg×8. Finish → queued as `PendingSaveWorkout` + `PendingUpsertRecords` with `dependsOn`.
  3. STILL OFFLINE: start a second workout. Log Bench Press 55 kg×8 (between W1 and W2).
  4. Observe PR row state: the set row shows `pendingPredictedPr` (gold ◆).
- **Expected:** The PR detection for W3's 55 kg set should compare against the OPTIMISTICALLY-UPDATED cache that was written after W2 was queued (L999–1015 in `active_workout_notifier.dart`). 55 < 60, so no PR. The row should show no-PR state.
- **Actual (code-analysis):** `active_workout_notifier.dart` L999–1015 writes the optimistically-updated cache to `HiveService.prCache` using the W2 records. Correctly, the W3 60 kg×8 record IS in the local cache at this point. So the comparison should correctly reject 55 kg×8 as a PR.
  HOWEVER: `SyncService._reconcilePrCache()` (`sync_service.dart` L444–462) calls `cache.clearBox(HiveService.prCache)` — it CLEARS THE ENTIRE CACHE — when a `PendingUpsertRecords` action drains successfully. This means after W2's PR records drain, the cache is wiped, and the next PR detection (W4 or any subsequent offline workout) falls through to `prRepo.getRecordsForExercises()` which makes a network call. If that network call returns the DB record (60 kg×8 now persisted), fine. But if the network call fails or the cache is read before the fetch returns (race), W4's PR detection sees an empty cache and falsely awards PRs.
- **Code evidence:** `sync_service.dart` L444–462: `clearBox` wipes all exercise-keyed PR cache entries. `active_workout_notifier.dart` L892–895: cache miss falls back to `prRepo.getRecordsForExercises()` — this is a network call. If the network is gone again (steady-online device briefly drops), the fallback is `{}` (empty), which means ALL sets look like PRs.
- **Net behavior:** cache clear on drain + network fallback path + empty-cache-awards-PR = every offline workout after a drain has elevated false-PR risk. This is an amplification of AW-EX-D-US1-01.
- **Suspicious files:** `lib/core/offline/sync_service.dart` (`_reconcilePrCache`), `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` (L892–895 fallback path), `lib/features/personal_records/data/pr_repository.dart` (`getRecordsForExercises` error handling)
- **Notes:** The cache-clear strategy was chosen intentionally (sync_service.dart comment: "complete invalidation is the only way to guarantee correctness"). This is correct for the steady-online case. The fragility arises in the offline-after-drain scenario where the subsequent fetch may fail.

---

### AW-EX-E-US1-04 — `PendingUpsertRecords` enqueued with empty `dependsOn` on fallback path — PR records may commit before workout sets exist on server

- **Persona:** Jordan
- **Charter:** E
- **Device:** US-1 (393×852)
- **Severity:** BLOCKER (data integrity — FK violation risk on `personal_records.set_id → sets.id`)
- **Repro steps (code-confirmed):**
  1. Go online. Finish a workout with a new PR (e.g. Bench Press 60 kg×8).
  2. The workout save succeeds (`savedOffline = false` branch). The code attempts a direct PR upsert via `prRepo.upsertRecords(newRecordsForUpsert)`.
  3. The direct upsert fails (e.g. network drop between the two calls — a 1–3s window).
  4. The fallback enqueues a `PendingUpsertRecords` with `dependsOn: const <String>[]` (empty list).
- **Expected:** Since the parent `save_workout` succeeded, the sets ARE on the server. The `PendingUpsertRecords` can safely run without dependency gating — the FK is already satisfied. `dependsOn: []` is correct here.
- **ACTUAL UNEXPECTED EDGE CASE (code-analysis):** The above analysis is correct for the direct-upsert-fallback path. HOWEVER, there is a second code path: `active_workout_notifier.dart` L927–940 enqueues `PendingUpsertRecords` with `dependsOn: [workout.id]` when `savedOffline == true`. This is correct — the PR upsert must wait for the workout to drain.
  The concern is the INTERACTION BETWEEN TWO WORKOUTS. If Workout W1 is queued offline (PendingSaveWorkout W1, PendingUpsertRecords U1 dependsOn W1.id), and then Workout W2 is finished online (save succeeds, direct upsert fails, PendingUpsertRecords U2 enqueued with `dependsOn: []`), the drain loop processes U2 before W1 drains. U2's PR records reference `set_id` values from W2's sets — which ARE on the server. So U2 runs cleanly.
  **True risk identified:** In the fallback path at `active_workout_notifier.dart` L972–994, the `PendingUpsertRecords` is enqueued with `dependsOn: const <String>[]`. This is correct ONLY because the parent workout save already succeeded. But the drain loop has no way to verify this assumption — it sees the item with no `dependsOn` and drains it immediately. If somehow this code path fires when `savedOffline == true` (e.g. due to a code bug that sets both `savedOffline = true` and later hits the fallback upsert path), the drain would run the upsert before the workout drain and get an FK violation. Review shows `savedOffline` is checked at L927 and the fallback at L960 is inside the `else` branch — but the `else` branch is inside the PR-detection `try/catch`, which means an exception in the non-upsert code path between L851–927 could leave `savedOffline` in a partially-observed state. Low probability but worth noting.
- **Code evidence:** `active_workout_notifier.dart` L960–996 (fallback upsert with empty dependsOn), L927 (savedOffline check for the primary path).
- **Severity re-assessment:** Lower risk than initially rated — the code path logic is mostly correct. Downgrade to MINOR unless the edge case produces a real FK violation in the field.
- **Suspicious files:** `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` (L927–996)

---

### AW-EX-E-US1-05 — Cold-launch drain fires correctly via `_coldLaunchDrain` (PR #171) — but drain is NOT idempotent if connectivity flap occurs before drain completes

- **Persona:** Jordan
- **Charter:** E
- **Device:** US-1 (393×852)
- **Severity:** minor (race condition; low probability but worth documenting)
- **Repro steps (code-confirmed):**
  1. App boots online with pre-existing queue items in Hive.
  2. `_coldLaunchDrain()` fires, calls `_drain()`. Drain starts, `_draining = true`.
  3. While draining (mid-loop), the connectivity status transitions offline→online (e.g. WiFi briefly drops).
  4. The listener fires: `wasOffline = true`, `next = true` → calls `_drain()` again.
  5. `_drain()` early-returns because `_draining == true`. Correct.
  6. But: the mid-drain connectivity drop also means `isOnlineProvider` briefly reads `false`. The drain loop checks `ref.read(isOnlineProvider)` at the top of each item iteration (L167–170). If this check fires during the brief offline window, the drain STOPS mid-loop (breaks out of the for loop) without draining remaining items.
  7. When `isOnlineProvider` returns to `true` (the brief flap ends), `_lastOnline` was set to `false` during the drop, so the listener fires again and triggers a NEW drain. Items not yet processed in the interrupted drain ARE picked up by this new pass. FIFO ordering is preserved because `queue.getAll()` re-sorts by `queuedAt`. This is correct.
- **Expected:** No user-visible data loss. The new drain pass finishes the job.
- **Actual (code-confirmed):** The behavior is correct. However the "mid-drain offline check" at L167–170 creates a situation where a brief connectivity flap splits a multi-item drain into two separate drain passes. If the queue contains items with `dependsOn` relationships, the second pass re-evaluates the `liveIds` set (L162) from scratch, which is correct (liveIds is rebuilt from `queue.getAll()` which reflects the current queue state after partial draining). No data loss, no FK risk. The interaction is safe.
- **Reason to document:** the `_draining` guard plus the mid-loop online check create a subtle reentrancy pattern. Future contributors should not "simplify" the mid-loop check without understanding the split-drain scenario.
- **Code evidence:** `sync_service.dart` L40-100 (`_coldLaunchDrain`), L121–163 (`_drain` with `_draining` guard and mid-loop online check).
- **Notes:** This is a code-reading observation, not a reproducible bug. Marked minor.

---

## Findings (Non-Bug Observations)

### AW-EX-E-US1-F01 — Drain order is FIFO (confirmed by code) — no observable deviation

- **Code evidence:** `offline_queue_service.dart` L93: `actions.sort((a, b) => a.queuedAt.compareTo(b.queuedAt))`. This guarantees FIFO. Multiple back-to-back workouts queued offline will drain in the order they were finished. Probe B (multiple workouts back-to-back) would confirm this visually, but the code is deterministic.
- **Notes:** FIFO is the correct semantic. No bug.

### AW-EX-E-US1-F02 — `PendingCreateExercise` dependency chain is correctly wired in code (Probe D — code-confirmed)

- **Code evidence:** `active_workout_notifier.dart` L796–818: when building the offline queue entry for a workout save, the code reads ALL pending `PendingCreateExercise` actions and adds their IDs to `dependsOn` if the workout exercises reference the locally-created exercise ID. `pending_sync_provider.dart` L138–168: the drain executes `createExercise()` for `PendingCreateExercise` actions via the exercise repository. `sync_service.dart` L176–191: actions are held if any `dependsOn` ID is still in `liveIds`. The dependency chain (exercise → workout) is correctly enforced.
- **BUT:** Charter E probe D calls for observing the network request order at the browser level. The code guarantees the correct ordering; whether the drain UI surfaces this correctly (e.g. does the pending badge show 2 items, then 1, then 0 as exercise then workout drain?) could not be verified without the browser. The badge count reflects `_queue.pendingCount` which is the raw Hive box length, so it should decrement atomically per successful dequeue.
- **Notes:** No bug found in code. Browser observation deferred.

### AW-EX-E-US1-F03 — `kMaxSyncRetries = 6` terminal classification is correct — but "terminal failure card" not testable via fetch-override path

- **Code evidence:** `sync_service.dart` L24: `const kMaxSyncRetries = 6`. L172–174: items with `retryCount >= kMaxSyncRetries` are skipped (not retried). L253–259: after drain, terminal items are counted and `SyncState.terminalFailureCount` is updated. The `SyncFailureCard` widget is driven by `terminalFailureCount > 0`. The existing E2E spec `offline-sync.spec.ts` tests 4 confirms this card is absent under normal conditions. For it to appear, 6 consecutive drain failures must occur, which requires a real server connection with persistent errors (or manual retryCount injection via Hive DevTools).
- **Notes:** The Probe F scenario (400 response triggering terminal classification) is partially testable: the first drain attempt on the 400-queued item would call `SyncErrorClassifier.isTerminal(e)`. BUT — the `SyncErrorClassifier` only sees a `PostgrestException` if the Supabase client parses the 400 response as a `PostgrestException`. If the fetch-override returns a raw 400 with a JSON body that does NOT match the Supabase error schema, the client may throw a different exception type (e.g. `FormatException`), which `isTerminal()` returns `false` for (catch-all at L25: returns `false`). In that case, the item would be treated as transient (non-terminal) and retry would be attempted up to 6 times with exponential backoff (1s, 2s, 4s, 8s, 16s, 30s — total ~61s wait before terminal). This means the "terminal failure card" may NEVER appear for simulated 400 errors if they aren't formatted as valid Supabase error JSON.

### AW-EX-E-US1-F04 — Sentry breadcrumb call sites confirmed in drain loop (Probe H — code-confirmed)

- **Code evidence:** `sync_service.dart`:
  - L183–190: `SentryReport.addBreadcrumb(category: 'sync', message: 'Holding action ...')` — fires when a dependency is gated.
  - L194–200: `SentryReport.addBreadcrumb(category: 'sync', message: 'Draining action ...')` — fires before each drain attempt.
  - L224–230: `SentryReport.addBreadcrumb(category: 'sync', message: 'Drain failed ...')` — fires on each failure.
  - `sync_service.dart` L451: `SentryReport.addBreadcrumb(category: 'sync.reconcile', message: 'PR cache reconciled ...')` — fires after successful PR reconciliation.
- **Whether these actually reach the Sentry endpoint depends on:** (a) Sentry being initialized in the local web build's `.env`, (b) the Sentry DSN being set. In a local dev build pointed at local Supabase, Sentry may not be configured. Network requests to `sentry.io` endpoints would confirm this. Browser-level observation of these requests was not possible in this session.
- **Notes:** The breadcrumb CALL SITES are present and correct. Whether they fire and reach a backend depends on runtime configuration.

### AW-EX-E-US1-F05 — `ConnectivityService` offline banner absent on Flutter Web (reconfirmed — Probe G deferred per AW-EX-B-US1-03)

- **Code evidence:** `connectivity_provider.dart` L32–38 confirms the stream relies on `connectivity.onConnectivityChanged` — OS-level events only. Probe G (banner debounce via rapid fetch toggle) is moot on Flutter Web: the banner never fires regardless of toggle speed. The 500ms debounce at L34 is never reached because the stream has no events to debounce.
- **Banner debounce code:** The debounce IS correctly implemented for native builds. On web it is dead code relative to the fetch-override simulation method.
- **Notes:** No additional bug beyond AW-EX-B-US1-03. Confirmed by code analysis.

### AW-EX-E-US1-F06 — Two-tab sync interaction (Probe I) — code confirms shared Hive state, positive baseline from AW-UX-B-US1-03

- **Code evidence:** `OfflineQueueService` reads from `Hive.box(HiveService.offlineQueue)`. Hive on Flutter Web is backed by IndexedDB. Each browser tab shares the same IndexedDB origin — both tabs read and write to the same Hive boxes. Two tabs finishing workouts back-to-back would both write to the same offline queue. The `PendingSyncNotifier.build()` rebuilds its state on first access in each tab, so each tab's badge count reflects the current queue length at build time, not a shared reactive stream.
- **Race risk:** Tab A's drain and Tab B's drain could run concurrently (each tab has its own Riverpod container). Two drains running simultaneously would both call `queue.getAll()`, both try to `retryItem()` the same actions, and both try to `queue.dequeue(id)` on success. The `Hive.box.delete()` call at `offline_queue_service.dart` L55 is not guarded by a distributed lock. If both tabs dequeue the same action, the second dequeue call tries `_box.delete(id)` on a key that no longer exists — Hive's `Box.delete()` is a no-op for missing keys, so no crash. But the item WOULD be sent to the server TWICE (one successful, one likely 409 on the server if the workout ID is already stored).
- **409 on duplicate workout save:** The `save_workout` RPC presumably uses UPSERT semantics (it's called via Supabase RPC). If it's truly idempotent (same workout ID → same result), the second drain attempt produces a no-op on the server. If not, a 409 PostgrestException would fire, be classified as terminal (`_terminalCodes` includes 409), and the item would eventually surface in the failure card.
- **This is a browser-resident concern** (two tabs in same origin). In a native mobile app (single process), this race cannot occur. It is an inherent multi-tab web risk.
- **Notes:** The positive baseline from AW-UX-B-US1-03 (two tabs show the same Hive-backed state correctly) confirms the READING path is correct. The WRITING race is a theoretical concern that requires two tabs completing saves simultaneously to manifest.

---

## Deferred Probes (BROWSER-REQUIRED)

| Probe | Reason | What to try next |
|-------|--------|-----------------|
| A — Offline → drain (full happy path) | Browser closed; fetch override ineffective for triggering drain on web anyway (AW-EX-E-US1-01) | Needs OS-level network drop on a real device or `docker stop supabase_kong_repsaga` mid-test |
| B — Multiple workouts queued | Browser closed | FIFO confirmed in code; visual badge decrement needs browser |
| C — Cold-launch with pre-existing queue | Browser closed; Hive IndexedDB persistence across tab-close is theoretically correct but unconfirmed | Use browser DevTools → Application → IndexedDB to inspect `flutter.web.workout.queue` key before and after tab close |
| D — Dependency chains (create exercise offline) | Browser closed | Code path confirmed correct; needs full browser session with exercise picker |
| E — PR cache reconciliation | Browser closed; also masked by AW-EX-D-US1-01 (false PR cache from session start) | Needs a browser session AND AW-EX-D-US1-01 fixed first to observe correct baseline |
| F — 400 failure mode / terminal card | Browser closed; also: 400 may not parse as PostgrestException via raw fetch override (see AW-EX-E-US1-F03) | Use `docker stop supabase_kong_repsaga` to simulate total failure; or manually edit Hive `retryCount` to 6 via DevTools to trigger terminal card display |
| I — Two-tab sync interaction | Browser closed | The write-race risk (AW-EX-E-US1-F06) requires two simultaneous tab operations; set up two Playwright contexts |

---

## Summary Table (Severity)

| ID | Severity | Title |
|----|----------|-------|
| AW-EX-E-US1-01 | MAJOR | Drain only triggers on OS-level connectivity event — fetch restore does not drain on web |
| AW-EX-E-US1-02 | MAJOR | HTTP 400/500 silently queued — SyncErrorClassifier not consulted at enqueue time |
| AW-EX-E-US1-03 | MAJOR | PR cache wiped on drain + empty-cache false-PR risk in offline-after-drain scenario |
| AW-EX-E-US1-04 | minor | Fallback upsert with empty dependsOn — safe in current code but fragile edge case |
| AW-EX-E-US1-05 | minor | Mid-drain connectivity flap splits drain into two passes — correct but subtle |
| AW-EX-E-US1-F01 | N/A | FIFO drain order confirmed in code — no bug |
| AW-EX-E-US1-F02 | N/A | PendingCreateExercise dependency chain correctly wired — no bug |
| AW-EX-E-US1-F03 | note | kMaxSyncRetries=6 terminal card may never appear for simulated 400 via fetch override |
| AW-EX-E-US1-F04 | note | Sentry breadcrumb call sites present — runtime delivery unverified |
| AW-EX-E-US1-F05 | N/A | Offline banner absent on web reconfirmed (AW-EX-B-US1-03) |
| AW-EX-E-US1-F06 | note | Two-tab drain race risk identified — low probability, web-specific |

---

## Bug Reports to Orchestrator (PROD-CODE failures)

**AW-EX-E-US1-02 (MAJOR) — expanded from AW-EX-D-US1-03**
1. Failing scenario: `active_workout_notifier.dart` finishWorkout catch block (L744–831). Every save failure — network or server — is routed to the offline queue path with no classification at the point of enqueue.
2. Reproduction: override `window.fetch` to return 400 for `save_workout` RPCs, finish a workout. No error snackbar; app navigates to home; pending badge increments.
3. Suspected cause: The `catch (e)` block in `finishWorkout` does not call `SyncErrorClassifier.isTerminal(e)` before deciding whether to enqueue. Fix: check `isTerminal(e)` at the catch site; for terminal errors, rethrow to the outer `AsyncValue.guard` which will produce an `AsyncError` and leave the user on the workout screen with an error state.
4. Suspicious files: `lib/features/workouts/providers/notifiers/active_workout_notifier.dart` (L744–831), `lib/core/offline/sync_error_classifier.dart`.
5. Test-side: Code-confirmed via source read. The existing `offline-sync.spec.ts` tests document that they block REST (not just 4xx) — this test gap needs a new test that specifically injects a 400-formatted response and asserts the app stays on the workout screen with an error visible.

**AW-EX-E-US1-03 (MAJOR) — PR cache wipe after drain**
1. Failing scenario: `sync_service.dart` `_reconcilePrCache()` (L444–462) clears the entire `prCache` box. Next offline PR detection (L892–895 in `active_workout_notifier.dart`) falls through to `prRepo.getRecordsForExercises()` which makes a network call. If that call fails (second offline window), the cache is empty and every set is incorrectly awarded a PR.
2. Reproduction: (1) Have prior PR data in DB. (2) Go offline, finish W2 (new PR queued). (3) Reconnect, let drain complete. (4) Go offline again. (5) Start W3. (6) Log any weight for an exercise — observe gold ◆ (pendingPredictedPr) even for a weight BELOW the known prior PR.
3. Suspected cause: The "clear entire box" strategy for reconciliation creates a blind window between clearing and the next cache hydration. Fix: instead of clearing the box, write the FRESH fetched records from the server directly into the box after drain (or use invalidation semantics that trigger a lazy re-fetch only when the next reader arrives while online).
4. Suspicious files: `lib/core/offline/sync_service.dart` (`_reconcilePrCache`), `lib/features/personal_records/data/pr_repository.dart` (`getRecordsForExercises` error handling — does it fallback to empty on network failure?).
5. Test-side: No existing test covers the offline-after-drain scenario. A unit test for `SyncService` with a mock `prRepo` that fails the post-drain fetch would catch this.

---

## Session Note

The Playwright MCP browser context was closed at session start and could not be revived by any tool call. All probes that required browser interaction are explicitly marked DEFERRED. The code-analysis portion of this charter is complete and the findings above represent genuine risks identified through source code reading, cross-referenced against prior charter observations and the existing E2E test suite.

The next session should:
1. Start with `browser_navigate http://127.0.0.1:4200` FIRST to verify the MCP browser is live before investing in probe setup.
2. If browser is live, prioritize Probe A (happy path drain) using `docker stop supabase_kong_repsaga` / `docker start supabase_kong_repsaga` to simulate real connectivity loss (this triggers `connectivity_plus`'s OS-level event), rather than fetch override.
3. Re-run Probe E ONLY after AW-EX-D-US1-01 is fixed — the false-PR-cache bug makes PR cache reconciliation testing meaningless until the baseline is correct.

---

## Summary Paragraph

Charter E produced 3 major bugs, 2 minor observations, and 5 non-bug notes, from code analysis after the Playwright MCP browser was found closed at session start. The major bugs cluster around the same root pattern identified in Charter D: the error-handling path in `finishWorkout` is not classification-aware (AW-EX-E-US1-02, same root as AW-EX-D-US1-03), and the PR cache management has a structural vulnerability in the offline-after-drain scenario (AW-EX-E-US1-03, amplifying AW-EX-D-US1-01). A new finding is that the sync drain fundamentally cannot be triggered by fetch-restoration on Flutter Web — it requires an OS-level connectivity event — making the drain effectively untestable via Playwright's fetch-override mechanism without additional infrastructure (AW-EX-E-US1-01). Probes A, B, C, D, E, F, I were deferred due to the browser being unavailable; probes G and H were confirmed by code without browser observation. No new pattern bugs that were entirely unknown — the offline/sync surface continues to exhibit the same classification-gap pattern (all exceptions treated as transient offline rather than being discriminated) that Charter D first surfaced. The dependency-chain code (BUG-002/003 fixes) appears correctly implemented in the source. The pending-sync badge and FIFO drain ordering are implemented correctly.
