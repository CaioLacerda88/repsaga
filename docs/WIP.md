# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

_No in-flight work._ **Phase 38.9 hardening — Tiers 1-3 complete.** Tier 1 (#367/#369/#372),
Tier 2 T2.1-T2.4 (#374), Tier 3 T3.1-T3.4 (#384/#385/#393). Two curated dependency batches
merged (#386, #394) — safe bumps in (incl. share_plus/connectivity_plus/permission_handler/
google_fonts majors), supabase_flutter 2.15 deferred (passkeys_web boot crash). **Remaining
Phase 38.9:** T2.5 (perf-regression signal) + T2.6 (visual/a11y CI) — deferred, harder; and
**Tier 0 (launch-readiness)** — needs user-provided secrets (keystore, Play service-account,
Sentry DSN). All in `docs/PROJECT.md` §2.
