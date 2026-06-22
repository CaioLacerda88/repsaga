# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

_No in-flight work._ **Phase 38.9 hardening — Tiers 0-3 done** (Tier 0 scaffolded #397, needs
user secrets to go live). Tier 1 (#367/#369/#372), Tier 2 T2.1-4 (#374), Tier 3 T3.1-4
(#384/#385/#393), Tier 0 (#397). Deps: #386/#394 merged; dependabot now ignores the deliberately-
held versions (supabase 2.15, riverpod_generator 4.0.4 + chained quartet, package_info_plus 10) so
the grouped PR stops failing every run. **Remaining:** T2.5/T2.6 (perf-regression + visual/a11y CI
— deferred, harder) in §2. Next launch step is USER-owned (secrets + tag) per docs/release-checklist.md.
