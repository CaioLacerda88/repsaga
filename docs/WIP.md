# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 38g — Cardio E2E + QA + calibration sign-off (FINAL cardio stage)

Branch `feature/phase38g-cardio-e2e-calibration`. Per `docs/PROJECT.md` §2 + the plan
`~/.claude/plans/noble-stirring-scroll.md` → "PR 38g". Closes Phase 38.

### Scope
- **Consolidated `cardio.spec.ts`** — the full cardio journey E2E in one feature spec:
  log a cardio session → cardio XP earned → cardio rank ticks → Saga cardio row visible
  → post-session cardio debrief. Per E2E Conventions (`rpgCardioActiveUser`, per-test
  reseed + serial, selectors in `helpers/selectors.ts`). Incremental cardio E2E already
  exists (38e `saga.spec.ts` cardio rows + `post_session.spec.ts` debrief; 38f
  `titles.spec.ts` /106) — 38g consolidates the earn→rank-up→Saga arc + fills gaps.
- **Final regression:** full `make ci` + full E2E suite green (the cardio phase landed
  in pieces — this is the consolidated final green).
- **Calibration sign-off:** lock the cardio formula constants "v1 DRAFT" → v1-final.
  No real user data pre-launch → sign-off = confirm the 14-persona panel (14/14) + the
  tier bands match the ACSM baseline (`docs/cardio-balance-baseline.md`); remove the
  "v1 DRAFT" markers from `tasks/cardio-xp-simulation.py` + `docs/cardio-balance-baseline.md`.

### Decision for the USER
- **Lock the cardio balance as v1-final?** The sim/baseline are marked "v1 DRAFT". Pre-launch
  there's no real data to recalibrate against; locking = committing these as the launch
  values (post-launch real-data recalibration would be a future phase). User owns the balance.

### Checklist
- [ ] **USER**: calibration sign-off (lock v1-DRAFT → v1-final, or keep DRAFT).
- [ ] qa-engineer: consolidated `cardio.spec.ts` (earn → rank-up → Saga row → debrief) per E2E conventions; run it + affected specs against a fresh web build.
- [ ] Un-mark "v1 DRAFT" in `cardio-xp-simulation.py` + `cardio-balance-baseline.md` (after sign-off); confirm sim 14/14.
- [ ] Final `make ci` + full E2E green.
- [ ] reviewer (E2E spec quality) → ship. No migration.
- [ ] Phase 38 fully closed: condense §4, clear backlog Phase-38 section.
