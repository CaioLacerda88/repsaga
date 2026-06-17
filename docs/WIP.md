# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 38e — Cardio activation (atomic boundary flip + coherent UI) ⚠ LARGEST

Branch `feature/phase38e-cardio-activation`. Per `docs/PROJECT.md` §2 → "Phase 38 —
remaining stages" + the plan `~/.claude/plans/noble-stirring-scroll.md` → "PR 38e".
**This is the boundary-crossing PR** — cardio goes from silent (computed but excluded)
to a visible 7th progression track. Per the boundary-ripple rule (CLAUDE.md §1 +
memories `feedback_measure_blast_radius_shared_code`, cluster `async-caller-broke-snackbar`)
EVERYTHING that derives from the 6-part assumption must move TOGETHER — run ALL
affected consumers (char-level, class, celebrations, stats), not a subset.

**Net effect:** 38a–38d already compute + store cardio XP and capture age; this flips
the leverage so cardio surfaces on the Saga sheet, contributes to character level,
and gets a class descriptor. New user-facing surfaces → **mockup + user approval
BEFORE build, + visual-verification gate before merge.**

### Locked spec (from the plan — confirm in scoping)
- **Flip:** add `cardio` to `activeBodyParts`; update **both** `_activeKeys`
  (`rank_curve.dart` + `character_xp_calculator.dart`); update `character_state` SQL
  view + the in-RPC char-level recompute to 7 parts (**denominator stays 4**). Max
  character level 148 → 172.
- **Classes:** add `Wayfarer` to `CharacterClass` + slug + l10n + `dominantClass[cardio]
  =wayfarer`; compound label `[StrengthClass]·[CardioDescriptor]`. **Ascendant stays
  6-strength-only** (explicit cardio exclusion in the spread test).
- **Identity:** `AppColors.bodyPartCardio` already teal `#22D3EE` (38b); wire
  `BodyPartHues[cardio]` (currently `hair`) → `bodyPartCardio`.
- **Saga UI:** replace hardcoded `DormantCardioRow` with a real `CardioProgressRow`
  (grouped apart: `surface2` divider + tint); 7-row rail; vitality table/chart gain
  the cardio row/line; two-speed Vitality halo legibility (cardio decays 3-wk vs 6-wk —
  stats copy).
- **Celebrations:** `CardioEntryRow` for the post-session summary panel (replaces the
  "0 kg × 0" `LiftRow` for cardio); cardio teal flood for B2 cuts; class-change cuts
  stay `hotViolet`.
- **Migration:** the `character_state` view + in-RPC char-level recompute (next free
  after 00079 = **00080**). Applied to hosted after merge.
- *(Split valve: if the diff is unmanageable, celebration/stats POLISH may split to a
  fast-follow 38e-bis, but the minimum coherent flip — Saga row + hue + char-level +
  classes + summary row — stays ATOMIC in this PR.)*

### Boundary inventory — TO FILL via Explore before implementation
_(Every `activeBodyParts` consumer (~40 sites: 21 lib + 16 test per the plan); both
`_activeKeys` defaults; `character_state` view + in-RPC recompute; `CharacterClass` +
`class_resolver` + `dominantClass`; `DormantCardioRow` → `CardioProgressRow` call site;
vitality table/chart row/line wiring; post-session `LiftRow` → `CardioEntryRow`; B2/B3
cut widgets; the max-level 148→172 consumers (title cap, level-up); E2E selectors that
assume 6 rows.)_

### Pipeline checklist
- [ ] Boundary Explore → fill the inventory (the load-bearing step — nothing builds until filled).
- [ ] product-owner thesis gut-check (cardio = separate-but-equal 7th track; Wayfarer; Ascendant stays strength-only) — plan-locked, quick confirm.
- [ ] ui-ux-critic design direction → mockup (`docs/phase-38-mockups.html` 38e: Saga `CardioProgressRow` grouped-apart, vitality table/chart cardio row/line, post-session `CardioEntryRow`, teal cut flood) → **USER APPROVAL**.
- [ ] tech-lead TDD: the atomic flip (all consumers together) + new widgets. Consider split valve only if diff is unmanageable.
- [ ] Tests: char-level w/ cardio (denominator 4, level→172), Ascendant-excludes-cardio spread test, Wayfarer compound class, CardioProgressRow/CardioEntryRow widget states, vitality row/line, parity for char-level recompute (Dart↔SQL).
- [ ] `make ci` green; full integration suite green (cardio now in char-level — re-verify the rpg_* parity tests).
- [ ] reviewer → fixes → QA gate (boundary = flow change → E2E for Saga 7-row + cardio rank-up + class; run affected specs).
- [ ] **Visual-verification gate:** 320/360/412 dp, foundation + fresh + **cardio-active** users, vs the mockup.
- [ ] Verify before PR → PR → ship → `npx supabase db push` 00080 to hosted.
