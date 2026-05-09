# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `PLAN.md` step or backlog entry, check items off
as work lands, and remove the section after the merge condenses to PLAN.md.

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
