# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 38f — Cardio titles (ladder + cross-build + 172 level-cap title)

Branch `feature/phase38f-cardio-titles`. Per `docs/PROJECT.md` §2 + the plan
`~/.claude/plans/noble-stirring-scroll.md` → "PR 38f". Now that cardio is a real
rank track (38e) it earns titles like the 6 strength parts.

### Locked spec (from the plan)
- **13-rung cardio ladder** (e.g. First Stride @ rank 5 → … → The Stride @ 99),
  kinetic/wind register, teal hue.
- **Cross-build:** update `iron_bound` (+ a `cardio ≤ 10` condition); add **The Forged
  Wind** + **Storm-Tempered**; new **character-level title at 172**. Total titles 90→106.
- **Vitality XP-gate:** `VITALITY_XP_FLOOR = 0.40` for cardio (already applied in the
  38c earning formula — confirm, don't re-add); **strength NOT retrofitted** (separate
  future decision — would need a fresh 13-persona re-tune).
- **Tests:** title evaluation with cardio active; the 3 cross-build predicates.

### Decisions for the USER (permanent user-facing names → surface before build)
- The full **13-rung cardio title-ladder names + flavor** (en+pt) + the **172
  level-cap title** name. These are permanent (awarded into the DB), so get the
  user's sign-off on the names before implementing.

### Boundary inventory — TO FILL via Explore (the title system)
_(Title data: `title_thresholds_table.dart`, `titles_repository.dart`, `title.dart`,
`assets/rpg/titles_*.json`; the SQL award VALUES lists in `record_set_xp` +
`record_session_xp_batch` (00077) + the cross-build evaluators `00043/00045/00049`;
l10n title keys + `title_localization.dart`; titles screen + `titles_view_model`;
how a body-part title ladder is defined for the 6 strength parts (the pattern to
mirror for cardio); the 148→172 character-level title rung.)_

### Pipeline checklist
- [ ] Boundary Explore → fill the inventory.
- [ ] Draft the cardio ladder names (ui-ux-critic/product-owner, plan register) → **USER APPROVAL**.
- [ ] tech-lead TDD: title data (cardio 13-rung ladder + 172 rung) + SQL migration (award VALUES + cross-build) + l10n en+pt + cross-build (iron_bound + Forged Wind + Storm-Tempered).
- [ ] Tests: cardio title evaluation/award, the 3 cross-build predicates, 172 char-level title, title count 90→106.
- [ ] `make ci` + full integration green (title award SQL); reviewer → QA → ship → push migration to hosted.
