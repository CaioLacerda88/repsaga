# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

_No in-flight work._ Phase 38.9 Tier-1: T1.1+T1.2 merged via #367, **T1.3 (RLS gate) merged
via #369** (58-assertion pgTAP suite + permanent `rls-tests` CI job; current RLS verified
hole-free). Remaining: T1.4 (offline-sync integration tier) + Tiers 0/2/3 — tracked in
`docs/PROJECT.md` §2 → Phase 38.9.
