# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Routine builder — visual + functional polish (ui-ux-critic review)

**Branch:** `feature/routine-builder-polish`
**Source:** User ask — "looks a bit off" + "nothing to guide the user (unit/format) for the cardio time input."
Full ui-ux-critic review of `CreateRoutineScreen`. User chose **full polish pass**.
**Pipeline:** mockup sign-off → tech-lead TDD → reviewer → QA → visual gate → ship. No migration / no model change.

### Findings to implement (from the review)
**Blockers (functional bugs):**
- [ ] **1a** Duration dialog format guidance is dead — `hintText:"mm:ss"` never shows because the field opens
      pre-filled. Add always-visible `helperText` "mm:ss or minutes — e.g. 28:00" (new ARB `enterDurationHelper`, en+pt).
- [ ] **1b** Both dialogs silently pop `null` on unparseable input (treated as Cancel → looks like a broken OK).
      Validate before close; show inline `errorText` on invalid. (`cardio_target_dialogs.dart`)

**Important (visual + UX):**
- [ ] **1c** Distance dialog: add `helperText` example "e.g. 5.2" / "ex.: 5,2" (locale separator; new ARB `enterDistanceHelper`).
- [ ] **2a** Cardio card density: bump target slot height 52→64 + value 18→22sp **in the builder only**.
      ⚠️ `CardioField` is SHARED with the active `CardioEntryCard` → add an opt-in size param defaulting to current
      (blast-radius rule); active card unchanged.
- [ ] **2b** Unify the 3 identity tags (cardio eyebrow / bodyweight pill / strength pill) into ONE pill grammar,
      vary only color; unify casing + radius (`kRadiusSm`, `AppTextStyles.label`); promote literal `6`/`fontSize:11`.
- [ ] **2c** Suppress name field `0/80` counter until near cap (mirror notes counter); add `ROUTINE`/`NOTES` section eyebrows.
- [ ] **2e** Bottom-anchored full-width Save CTA (keep AppBar save as secondary).
- [ ] **3a** Filled `CardioField` needs a tappable affordance — add an edit (pencil) glyph; reads as display now.
- [ ] **3d** Empty state when `_exercises.isEmpty` (RPG-voiced "add your first exercise" beat).

**Nits:**
- [ ] **2d** Standardize vertical rhythm; add button gets 16dp top separation from last card (currently 8).
- [ ] **3c** Verify remove `×` rendered hit-box ≥48dp via `tester.getSize`; drop `compact` if under.

### Steps
- [x] New routine-builder mockup section in `docs/phase-38-mockups.html` ("Phase 38h-polish") → **user sign-off** ✅ approved 2026-06-18
- [ ] tech-lead TDD implement → reviewer → QA (incl. dialog validation + E2E selector check) → visual gate → ship
- [ ] PROJECT.md row on merge

### Implementation log (tech-lead) — code complete, gate green (3809 pass / 1 skip / 0 fail)
- [x] 1a/1b/1c — `cardio_target_dialogs.dart`: stateful `_CardioInputDialog`, helperText, validate-before-close + errorText
- [x] ARB: enterDurationHelper, enterDurationError, enterDistanceHelper, enterDistanceError, routineSectionLabel, notesSectionLabel, routineEmptyExercises, saveRoutineCta (en+pt)
- [x] 2a — `CardioField` opt-in `CardioFieldSize { compact, large }` (compact = current/active size)
- [x] 2b — unified `_IdentityPill` (cardio teal-dim / strength BodyPartHues / bodyweight neutral); promoted literal 6/fontSize:11
- [x] 2c — name counter buildCounter + ROUTINE/NOTES section eyebrows
- [x] 2e — bottom-anchored Save CTA (`_BottomSaveBar`) in SafeArea bottom bar (AppBar Save kept)
- [x] 3a — edit pencil glyph on filled CardioField
- [x] 3d — empty state (routineEmptyExercises)
- [x] 2d — add-button 16dp top separation
- [x] 3c — remove × hit-box ≥48dp via tester.getSize (dropped visualDensity.compact)
- [x] Tests: dialog validation matrix, helper visibility, shared-widget guard, pill variants, counter, empty state, bottom save, remove hit-box

Phase 38 ✅ COMPLETE + post-38 follow-ups (#352 CI job, #353 routine cards). Only open §2 follow-up:
post-launch cardio tier-band recalibration (telemetry-gated).
