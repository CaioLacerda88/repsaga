# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `PLAN.md` step or backlog entry, check items off
as work lands, and remove the section after the merge condenses to PLAN.md.

---

## Resume context (post-compact pickup)

**Active-workout exploratory pass: 28 / 31 bugs shipped across 10 PR pairs.
Pass effectively complete.**

| Family | PRs | Status |
|---|---|---|
| 2 — Rest scrim modality | #175, #176 | ✅ |
| 1A — PR cache bootstrap (BLOCKER) | #177, #178 | ✅ |
| 1B — Save-error classification | #179, #180 | ✅ |
| 4 — Tap targets 48dp | #181, #182 | ✅ |
| 8 — Finish-button disabled wiring (STALE) | #183, #184 | ✅ |
| 7 — postFrame race + offline contract | #185, #186 | ✅ (3-round arc) |
| 3 + 6 — A11y semantics + i18n leaks | #187, #188 | ✅ (11 bugs in one cycle) |
| 5A — Web `OfflineBanner` Semantics (root cause: shell layout) | #189, #190 | ✅ |
| 5B — Drain reliability (recovery hook + 60s health check) | #191, _cleanup_ | ✅ |

The remaining 3 bugs in `tasks/active-workout-findings.md` are stale
measurement findings already reclassified during prior families (Family 4
tap-target measurements; cluster-F edge cases) — not regressions to chase.

**Process patterns that worked through the entire pass:**
- TDD discipline (failing-test-first) caught stale measurement findings in
  Families 4 and 8, surfaced architecture-level bugs in Families 1A and 7,
  and exposed the actual layout-bug root cause in Family 5A (initial
  hypothesis blamed `package:web`; tech-lead's systematic-debugging found
  a Flutter Web semantics-tree compaction issue in `_ShellScaffold`).
- Reviewer agent caught real bugs in every cycle. Family 5B caught: missing
  T+5min boundary test, doc/code mismatch on `mapException`, dead-wired
  recovery recorder in `AnalyticsRepository`, over-broad `catch (_)` in
  `_hasTransientItems`, over-broad `AuthException` classification.
- Post-merge cleanup PRs admin-merge after fast checks (memory feedback —
  saves ~20 min per cycle vs waiting on e2e).
- All findings (Critical / Warning / Nit / Suggestion) addressed in same
  cycle per memory feedback — zero post-merge follow-ups.
- `superpowers:systematic-debugging` Phase 1 prevented multiple ad-hoc
  patches that would have shipped the wrong fix.

**Next dispatch when resuming:**
- Active-workout pass is closed. PLAN.md is the canonical source for new
  initiatives (`## Active Backlog` section).

---

_No work in flight._
