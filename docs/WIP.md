# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Pre-launch — Typography unification research (branch: `feature/typography-research-pre-launch`)

**Goal.** User feedback: the current Rajdhani+Inter pairing reads as "two
moments in the app." Rajdhani stays (user loves it); the prose-side font
(currently Inter) needs to evolve into something that bridges the RPG +
gym registers without feeling like a generic safe default.

**Phase: research + mockup proposal (no code changes yet).**

- [x] WIP entry created
- [x] product-owner research — competitor scan (Persona 5, Diablo IV,
  Habitica, Hevy, Nike Training Club). Top 3: Barlow → Exo 2 → Outfit.
- [x] ui-ux-critic research — typographic-principle diagnosis (x-height,
  apertures, weight ramp, geometric-vs-humanist DNA). Top 3: Barlow →
  DM Sans → Chakra Petch. Anti-rec: Exo 2 (despite PO's #2).
- [x] Synthesize into `docs/typography-research-mockup.html` —
  4-column side-by-side rendering Current/Barlow/DM Sans/Chakra Petch
  against 6 production surfaces (Saga, Home, Stats, Exercises,
  Routines, Workout-log).
- [x] User picked direction → **Barlow** (2026-05-20)
- [x] UX audit — pre-swap best-practice review across all 22 screens +
  80 widgets + ~400 typography call sites. Findings: 12 Critical, 28
  Important, 8 Nits, 14 Pre-swap. Overall typographic health 6/10.
- [x] **Architecture audit** — read-only deep-dive on whether the
  typography subsystem itself is structured for low-friction
  maintenance. Score 5/10 (lower than call-site 6/10 — the system
  invited the 80 violations). Key finding: `theme.textTheme.*` and
  `AppTextStyles.*` are two parallel paths to the same TextStyle; the
  shorter "wrong" path wins (225 vs 154 calls).
- [ ] **Phase 28a — Foundation** (pre-Barlow, ~6–8h):
  - 4 new CI gates: `w800`/`w900`, raw `'Inter'`/`'Barlow'` literals,
    `GoogleFonts.*` calls, `google_fonts` import
  - Fix 6 forbidden-weight violations (WeightStepper default, PR
    celebration ×2, set_row ×2, rest_timer)
  - 3 new tokens: `numericSmall`, `appBarTitle`, `celebrationDisplay`
    (parameterized helper)
  - Property pins for all 9 tokens in `arcane_theme_test.dart`
  - Fix 2 dead doc links (`tasks/mockups/...` references in
    `app_theme.dart:9` + `README.md:4`)
  - Add "when to use" dartdoc clause to each `AppTextStyles` getter
- [ ] **Phase 28d — `_textTheme` shim research** (pre-28b, ~2h):
  - Inventory which Material widgets read which `textTheme` slots
    (Dialog, SnackBar, InputDecoration, ListTile, SegmentedButton)
  - Output: narrowed shim covering only the inherited slots
  - User locked direction: narrow to compat shim (not full deletion)
- [ ] **Phase 28b — Barlow swap + textTheme migration** (pre-launch, ~12–18h, single PR):
  - Bundle Barlow Regular/SemiBold + Barlow Condensed Medium/SemiBold
  - Swap `fontFamily: 'Inter'` → `'Barlow'` in token definitions
  - Reconcile `sectionHeader` 12dp ↔ `SectionHeader` widget 13dp
  - **Migrate all 225 `theme.textTheme.*` call sites to `AppTextStyles.*`**
    (user locked: bundle this with the Barlow PR rather than defer)
  - Narrow `_textTheme` to compat shim (per 28d research)
  - Add `theme.textTheme.*` CI gate after migration
  - Update auto-memory `project_design_language_typography.md`
  - Visual verification 320/360/412dp on 6 surfaces
