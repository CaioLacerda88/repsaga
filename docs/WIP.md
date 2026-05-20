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
- [x] **Phase 28a — Foundation** (pre-Barlow, ~6–8h):
  - [x] Task #16 — Extended `scripts/check_typography_call_sites.sh`
        with 4 new gates (`w800`/`w900`, raw `'Inter'` literals,
        `GoogleFonts.*` calls, `google_fonts` import); smoke-tested
        each fires on a temp violation
  - [x] Task #17 — Fixed all 6 forbidden-weight violations
        (WeightStepper default + dartdoc, set_row ×2,
        rest_timer_overlay, pr_celebration_screen ×2)
  - [x] Task #18 — Added 3 tokens (`numericSmall`, `appBarTitle`,
        `celebrationSize(double)`) + migrated 3 numericSmall sites,
        wired `appBarTitle` into theme, migrated 3 celebration
        overlays. Renamed `class_change_overlay`'s
        `GoogleFontsRajdhani` → `_ClassChangeHeadlineStyle` (misnamed;
        never used google_fonts package).
  - [x] Task #19 — Property pins for all 12 tokens (9 existing + 3
        new); appBar wiring test pins token ↔ theme equivalence
  - [x] Task #20 — Fixed dead doc refs (`lib/core/theme/README.md:4` +
        `lib/core/theme/app_theme.dart:9` + outdated google_fonts
        narrative at `lib/core/theme/README.md:64`); added "Use for: /
        Not for:" dartdoc prescription to every `AppTextStyles` getter
  - [x] format + analyze + 4 gates clean; 2954 tests pass; Android
        debug APK builds clean
- [ ] **Phase 28d — `_textTheme` shim research** (pre-28b, ~2h):
  - Inventory which Material widgets read which `textTheme` slots
    (Dialog, SnackBar, InputDecoration, ListTile, SegmentedButton)
  - Output: narrowed shim covering only the inherited slots
  - User locked direction: narrow to compat shim (not full deletion)
- [x] **Phase 28d — `_textTheme` shim research** — recommendation locked:
  KEEP `bodyLarge/Medium/Small`, `labelLarge/Medium`, `titleMedium`. DROP
  the rest. Critical sequencing: migrate call sites BEFORE narrowing shim.
- [ ] **Phase 28b — Barlow swap + textTheme migration** (branch:
  `feature/28b-barlow-texttheme-shim`, ~12–18h, single PR):
  - [ ] Step 1 — Bundle Barlow Regular/SemiBold + Barlow Condensed
        Medium/SemiBold TTFs in `assets/fonts/` + `pubspec.yaml`
  - [ ] Step 2 — Migrate all 220 `theme.textTheme.*` call sites in
        `lib/features/` + `lib/shared/` to `AppTextStyles.*` (FIRST;
        narrowing-after dependency per Phase 28d). File order:
        volume_peak_block (16) → exercise_card (11) →
        workout_detail_screen (9) → pr_celebration_screen (8) → ...
  - [ ] Step 2.6 — Reconcile `sectionHeader` 12dp ↔ `SectionHeader`
        widget 13dp by promoting token to 13dp
  - [ ] Step 3 — Swap `fontFamily: 'Inter'` → `'Barlow'` (body/title/
        bodySmall) and `'Barlow Condensed'` (label/sectionHeader) in
        `AppTextStyles`. Update `arcane_theme_test.dart` family pins.
  - [ ] Step 4 — Narrow `_textTheme` shim to KEEP set per Phase 28d
        (`bodyLarge`/`bodyMedium`/`bodySmall`/`labelLarge`/`labelMedium`/
        `titleMedium`)
  - [ ] Step 5 — Add Gate 6 to `check_typography_call_sites.sh` —
        `theme.textTheme.*` forbidden in `lib/features/` + `lib/shared/`
  - [ ] Step 6 — Update auto-memory
        `project_design_language_typography.md`
  - [ ] Step 7 — Visual verification 320/360/412dp on 6 surfaces
        (Saga, Home, Stats, Exercises, Routines, Workout-log)
