# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

_No in-flight work._ **Phase 38.9 hardening — complete** (every tier built or honestly
deferred-with-rationale). Tier 0-3 + the buildable T2.5 (hot-path index gate, #400) and
T2.6 Track A (a11y guideline gate, #400) merged. Documented-deferred in §2: T2.5 EXPLAIN
plan-gate, T2.6 automated visual-regression (→ make the manual gate non-skippable), and 2
a11y follow-ups the gate surfaced (sub-48dp tap targets → layout; textDim contrast → tokens).
