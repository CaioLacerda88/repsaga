# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `PLAN.md` step or backlog entry, check items off
as work lands, and remove the section after the merge condenses to PLAN.md.

---

## Active branch: `fix/core-drain-reliability` — Family 5B (drain reliability)

Per `tasks/active-workout-implementation-plan.md` §313–§318 and §344–§348.
Bugs:
- **AW-EX-E-US1-01** — drain only triggers on OS-level event; captive
  portal recovery / same-SSID reconnect → no auto-drain.
- **AW-EX-E-US1-04** — fallback PR upsert with `dependsOn: []` — currently
  safe but fragile.
- **AW-EX-E-US1-05** — mid-drain connectivity flap splits drain into two
  passes (already partially handled by `_draining` reentrancy guard;
  validate behavior with the new signals).

**Triage decisions (settled before tech-lead dispatch):**

- **Recovery-signal scope:** only network-class exceptions count as
  "failures". Domain errors (validation, 4xx, business-logic) do not
  trigger recovery state. The `ErrorMapper`/`SyncErrorClassifier` already
  has the classification surface — reuse `SyncErrorClassifier.isTerminal`-style
  logic, or expose a new `isNetworkClass` helper.
- **Cooldown:** 5 seconds between drain triggers from the recovery hook
  ONLY. Connectivity-listener and cold-launch paths do NOT go through the
  cooldown — those have their own reentrancy guards. The cooldown is
  per-source.
- **Failure-window:** "recent" failure = within last 5 minutes. After 5
  minutes the failure is forgotten; success-after-failure no longer fires
  drain. Prevents stale recovery signals from old offline windows.
- **Health-check cadence:** 60s while queue has at least one transient
  item (retryCount < `kMaxSyncRetries`). Stops when queue empty OR all
  remaining items are terminal. Restarts when a new item enqueues.
- **Health-check endpoint:** Supabase `HEAD /rest/v1/` (PostgREST root)
  with auth headers. Tiny request, no body. Tech-lead can choose between
  this and `/auth/v1/health` if there's a reason — both acceptable.
- **`BaseRepository` integration:** extend `mapException` to record
  failure on network-class exceptions and success on the success path.
  `BaseRepository` doesn't currently hold a `Ref` — tech-lead must thread
  one through (constructor parameter on subclasses, set in the provider
  factory) or pick a non-Ref-coupled equivalent (e.g. a top-level singleton
  `ConnectivityRecoveryRecorder` wired up by app bootstrap).
- **No feedback loop:** when the recovery hook fires drain, the drain's
  own requests must NOT feed back into `recordSuccess`/`recordFailure`.
  Either skip recording during `_draining`, or have `SyncService` set a
  short-lived "drain-in-progress" flag the recorder respects. Plan §330
  specifically calls out the retry-storm risk.

**Files to touch:**

- New: `lib/core/connectivity/connectivity_recovery_provider.dart` —
  `Notifier<int>` (or sealed-state) exposing `recordFailure()`,
  `recordSuccess()`. Owns the 5-min failure window + 5s drain-trigger
  cooldown. Emits an "increment-and-broadcast" tick that `SyncService`
  watches via `ref.listen`.
- `lib/core/data/base_repository.dart` — `mapException` extension to call
  `recordFailure(e)` on network-class catches and `recordSuccess()` on
  the success branch (gated by an injected `Ref` or equivalent).
- `lib/core/offline/sync_service.dart` —
  - Listen to `connectivityRecoveryProvider`; on tick, trigger `_drain`
    (subject to existing `_draining` guard).
  - Health-check `Timer` lifecycle: start when queue gains a transient
    item, cancel when empty or all-terminal. On tick: HEAD request →
    success → `recordSuccess` (which fires the recovery path via the
    same notifier).
- `lib/core/offline/sync_error_classifier.dart` (existing) — add
  `isNetworkClass(Object)` helper if not already there.

**Tests (TDD):**

- New: `test/unit/core/connectivity/connectivity_recovery_provider_test.dart`
  - recordSuccess WITHOUT a recent failure → no tick
  - recordSuccess AFTER recordFailure within 5min → tick fires
  - recordSuccess AFTER 5min stale failure → no tick
  - Multiple successes within 5s → only first fires (cooldown)
  - Domain-error failure (non-network) → not recorded
- New: `test/unit/core/offline/sync_service_recovery_test.dart`
  (per plan §368) — recovery signal triggers drain; `_draining` guard
  prevents storm; cooldown prevents storm.
- New: `test/unit/core/offline/sync_service_health_check_test.dart` —
  health-check timer starts on enqueue, stops on empty queue, stops on
  all-terminal. Use `fake_async` for time control.
- Existing `test/unit/core/offline/sync_service_test.dart` — must still
  pass without modification.

**Acceptance criteria:**

- `make ci` clean (format + analyze + test + android-debug-build).
- All existing offline-sync E2E tests still pass.
- New unit tests cover the four signals (failure recording, success
  triggering, cooldown, stale-failure forgetting).
- No new background network traffic when queue is empty.
- Recovery hook does not fire drain from within an active `_drain`
  (no retry storm).

**Pipeline tracking:**

- [x] Branch + WIP entry
- [x] Tech-lead implements 5B with TDD
- [x] CI verification (format, analyze, full test suite, android-debug build)
- [ ] QA gate
- [ ] Verify + PR + reviewer cycle
- [ ] Post-merge cleanup PR

---

## Resume context (post-compact pickup)

**Active-workout exploratory pass progress: 25 / 31 bugs shipped across 9 PR
pairs.**

| Family | PRs | Status |
|---|---|---|
| 2 — Rest scrim modality | #175, #176 | ✅ |
| 1A — PR cache bootstrap (BLOCKER) | #177, #178 | ✅ |
| 1B — Save-error classification | #179, #180 | ✅ |
| 4 — Tap targets 48dp | #181, #182 | ✅ |
| 8 — Finish-button disabled wiring (STALE) | #183, #184 | ✅ |
| 7 — postFrame race + offline contract | #185, #186 | ✅ (3-round arc) |
| 3 + 6 — A11y semantics + i18n leaks (combined) | #187, #188 | ✅ (11 bugs in one cycle) |
| 5A — Web `OfflineBanner` Semantics (root cause: shell layout) | #189, _cleanup_ | ✅ |

**What's left (single remaining family):**

**Family 5B — Drain reliability fallbacks.** 3 bugs. ~6h. Architectural,
no UI change. Plan reference: `tasks/active-workout-implementation-plan.md`
§336 (PR 5B section), §344–§348.

Bugs:
- AW-EX-E-US1-01 (drain only triggers on OS-level event; captive portal
  recovery / same-SSID reconnect → no auto-drain)
- AW-EX-E-US1-04 (fallback PR upsert with `dependsOn: []` — fragile)
- AW-EX-E-US1-05 (mid-drain connectivity flap splits drain into two passes)

Plan-recommended approach:
- `connectivityRecoveryProvider` — any successful repository call after a
  recent recorded failure fires a drain signal, gated by a 5s cooldown to
  prevent retry storms.
- Periodic health check every 60s while queue non-empty; HEAD on Supabase
  health endpoint. Stops if queue is entirely terminal-failure items
  (no transient items remain).
- Risk: feedback loops if the recovery signal fires from a request that
  itself failed.

**Process pattern that has been working:**
- TDD discipline (failing-test-first) caught stale measurement findings in
  Families 4 and 8, surfaced architecture-level bugs in Families 1A and 7,
  and exposed the actual layout-bug root cause in Family 5A (initial
  hypothesis blamed `package:web`; tech-lead's systematic-debugging found
  it was a Flutter Web semantics-tree compaction issue in `_ShellScaffold`)
- Reviewer agent has caught real bugs in every cycle. On 5A: caught the
  `_kOfflineBannerHeight` undershoot (40 vs actual 42dp) and an E2E
  cleanup-safety bug where a mid-test timeout would poison subsequent
  tests with a permanently-offline browser context.
- Post-merge cleanup PRs admin-merge after fast checks (memory feedback —
  saves ~20 min per cycle vs waiting on e2e)
- All findings (Critical / Warning / Nit / Suggestion) addressed in same
  cycle per memory feedback — zero post-merge follow-ups

**Next dispatch when resuming Family 5B:**
- Create branch `fix/core-drain-reliability`
- Write WIP entry referencing implementation plan §344–§348
- Dispatch tech-lead with TDD instructions:
  - New: `lib/core/offline/connectivity_recovery_provider.dart` (or extend
    existing) — record a failure timestamp, expose a "consume" method that
    treats a successful call within N seconds of a failure as a recovery
    signal
  - Wire into `lib/core/data/base_repository.dart` — every repository
    success/failure goes through `mapException`, ideal hook
  - `lib/core/offline/sync_service.dart` — listen to recovery signal as a
    third drain trigger alongside `onlineStatusProvider` and the existing
    OS-event path
  - Periodic health-check timer in `sync_service.dart` — start when queue
    becomes non-empty, stop when empty or all-terminal
  - Tests: integration around the recovery hook, cooldown enforcement,
    health-check lifecycle
- Standard pipeline: tech-lead → CI → QA → PR → reviewer → merge → cleanup PR

---

_No work in flight._
