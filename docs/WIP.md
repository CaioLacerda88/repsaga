# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 38d — Age capture (birth-year)

Branch `feature/phase38d-age-capture`. Per `docs/PROJECT.md` §2 → "Phase 38 —
remaining stages" + the plan `~/.claude/plans/noble-stirring-scroll.md` → "PR 38d"
+ the product-owner + ui-ux-critic scoping (2026-06-15/16). Net-new user-facing
surface → **ui-ux-critic mockup + user approval BEFORE build, + visual-verification
gate before merge.**

**Goal:** collect birth-year so cardio scores on real age-decade norms instead of
the age-35 fallback. 38c added nullable `profiles.date_of_birth`; this adds the UI
that populates it. Cardio scoring already reads the column server-side.

### Locked decisions (user, this session)
1. **Birth-YEAR granularity** — stored `YYYY-01-01` in the existing
   `profiles.date_of_birth date` column (NO migration change; formula keys on
   age-decade, so year is the minimal stable representation = LGPD data-minimization).
2. **Optional** — age-35 fallback is a valid steady state; **never gates cardio XP**.
3. **Backfill prompt = post-session summary** — one-time dismissible (Hive flag,
   `bodyweight_prompt_coordinator` pattern); fires after a cardio session when DOB
   is NULL; settings row always available regardless.
4. **Privacy = LGPD Art. 6 consent** (like avatars), **NOT Art. 11 sensitive** (unlike
   gender/bodyweight) → point-of-collection disclosure + privacy-policy §2 row +
   data-export inclusion; **NO Hive consent toggle** (do not clone `BodyweightConsentToggle`).
5. **Control = branded birth-year wheel** (`ListWheelScrollView`, years
   `currentYear−18 … currentYear−100`, default rests on `currentYear−35` so
   skip==fallback; ≥18 floor STRUCTURAL — wheel can't represent under-18, never
   re-asks the signup age-gate). NO Material calendar (over-collects month/day).
6. **No onboarding step** (highest friction, zero day-zero payoff — cardio invisible
   until 38e).

### Boundary inventory — TO FILL via Explore before implementation
_(Profile model + repo read/write/serialization + all consumers; post-session summary
injection point for the prompt; bodyweight-prompt-coordinator + dismissal-flag pattern;
profile_settings_screen structure + the gender_row/bodyweight_row grammar to clone;
l10n key pattern; data_export_service.)_

### Pipeline checklist
- [ ] Boundary Explore → fill the inventory above.
- [ ] ui-ux-critic mockup: add AgeRow + AgeEditorSheet (birth-year wheel) + post-session
      age prompt to `docs/phase-38-mockups.html`; ui-ux-critic critique → **USER APPROVAL**.
- [ ] tech-lead TDD: `Profile.dateOfBirth DateTime?` (model + repo + serialization);
      `AgeRow` + `AgeEditorSheet` (wheel, structural ≥18 floor, clear-to-NULL) in
      profile settings after Gender; post-session one-time prompt (Hive dismissal flag);
      l10n en+pt; privacy-policy §2 DOB row; `DataExportService` includes date_of_birth.
- [ ] Tests: Profile serialization; AgeRow/AgeEditorSheet widget states + ≥18 floor +
      clear-to-NULL + textScaler on wheel; post-session prompt one-time/dismiss logic;
      age-derivation. E2E (flow change): set-age-in-settings + first-cardio-prompt flow.
- [ ] `make gen` + `dart format` + `dart analyze --fatal-infos` + `make test` green.
- [ ] reviewer → fixes → QA gate (E2E flow change → write/update specs, run them).
- [ ] **Visual-verification gate** (new surface): 320/360/412 dp (+ textScaler 1.3 corner)
      vs the mockup; foundation + fresh users.
- [ ] Verify before PR → PR → ship. (No migration → no hosted push.)

### Edge cases (surface in mockup + tests)
Wheel item-extent vs large textScaler (cap visible items / size off scaled metric);
empty "Not set" state reads non-alarming (no warning icon / incomplete-profile nag);
clearing a previously-set value; gender-NULL coherence; never re-ask the 18+ gate.
