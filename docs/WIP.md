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

### ⚠ SCOPE CHANGE (user, 2026-06-17) — NO cardio class; cardio counts toward level
- **NO separate cardio class.** DROP the Wayfarer variant + `dominantClass[cardio]` +
  the `[Strength]·[Cardio]` compound label + `class_wayfarer` l10n + mockup Surface 4.
  Cardio recognition is via **TITLES (38f cardio ladder)**, not a class.
- **Class identity stays pure 6-strength.** Because cardio now lives in `activeBodyParts`
  (for level/Saga/stats), the class system must NOT read `activeBodyParts` anymore — pin
  `class_resolver.dart` + `class_provider.dart` to a **strength-6 subset** (new
  `strengthBodyParts` const, or filter out cardio) so cardio never leaks into class /
  Ascendant. (Simpler than the old "carve cardio out of Ascendant but keep in dominant" —
  cardio is now ENTIRELY out of class.) `b3_class_change_cut` stays violet; cardio
  rank-ups never trigger a class change.
- **Cardio DOES count toward character LEVEL** (user): keep 6→7 in BOTH `_activeKeys`,
  `character_state` view + in-RPC recompute (migration 00080), denominator stays 4, max
  148→172 (computed; title cap 148 → 38f). The never-regress proof stands.

### Decisions locked (user + agents, 2026-06-17)
- **Vitality decay = FULL two-speed in 38e** (user): add cardio to `vitality-nightly` job
  + cardio-specific **τ_down = 21d (3wk)** in BOTH `VitalityCalculator` (Dart) +
  `vitality-nightly` (TS) + parity; ship the "conditioning fades in ~3 weeks" copy.
  (Strength stays τ_down=42d; "never copy τ between stats".)
- **No literal heptagon** (ui-ux): cardio is a **banded** 7th row/line (`surface2` divider
  + teal-tint band + `CARDIO` eyebrow), NOT homogenized onto the strength hexagon. Vitality
  chart = 7th teal line + decay-window copy when selected (split valve: separate strip only
  if 320dp crowds).
- **Two-speed legibility carried by WORDS** (per-row decay subtitle + one-time stats
  explainer), not color/pulse alone.
- **char-level max → 172 (computed)**; the top *title* `saga_eternal` STAYS at 148 +
  the new 172 level-cap title is **38f**. 38e updates the COMPUTED-max in fixtures/tests
  (all-99 7-key → 172) but leaves the title threshold at 148.
- **Stays 6 (do NOT let the flip leak in):** weekly-plan engagement (`weekly_engagement.dart`
  cardio-skip + `engajamento_section`), cross-build title SQL evaluators (`00043/00045/00049`),
  Ascendant spread, class-change cut `hotViolet`.
- **Acceptance criterion (thesis):** a pure-strength user's character level must NEVER
  regress post-38e (denominator-stays-4 proof) — named test required.

### Boundary inventory (filled via Explore — implementation may start)
**Atomic-flip sites (MUST move together):**
1. `lib/features/rpg/models/body_part.dart:50-57` `activeBodyParts` (+`cardio`) — the trigger.
2. `lib/features/rpg/domain/rank_curve.dart:179-186` `_activeKeys` (+`'cardio'`); denominator `~/4` stays.
3. `lib/features/rpg/domain/character_xp_calculator.dart:7` `_activeKeys` (SEPARATE — +`'cardio'`).
4. **SQL migration 00080:** `character_state` view filter `00040:321` (current def, never redefined) + in-RPC recompute filters in **00077** (current; NOT 00065): `record_set_xp` `00077:224,507`, `record_session_xp_batch` `00077:734,1102`, `_rpg_backfill_chunk` (~`00077:1226` block). All `WHERE body_part IN (6)` → 7.
5. **Classes (REVISED — pin to strength-6, NO Wayfarer):** `class_resolver.dart:85-106` + `class_provider.dart:40` currently project onto `activeBodyParts` — change to a **strength-6 subset** (`BodyPart.values` minus cardio, or a new `strengthBodyParts` const) so cardio (now in `activeBodyParts`) does NOT enter class resolution / Ascendant spread. NO `character_class.dart` change, NO `dominantClass[cardio]`, NO compound label (`saga_header.dart`/`class_badge.dart` untouched), NO `class_wayfarer` l10n. Rewrite `class_resolver_test.dart:209` to assert cardio is excluded from class via the strength-6 subset (not via activeBodyParts).
6. `lib/features/rpg/domain/body_part_hues.dart:62` `cardio: hair` → `bodyPartCardio` (ONE line → teal flows to rows + B2 floods + chart line + table for free). `bodyPartCardio` already `#22D3EE` (`app_theme.dart:93`).
7. Saga: `character_sheet_screen.dart:127-135` — remove `DormantCardioRow` block (else double-cardio: provider auto-adds a 7th `BodyPartRankRow` + dormant still renders) → new `CardioProgressRow` (alive: `AmbientPulseDot`, rank numeral, teal bar, tap→`/saga/stats?body_part=cardio`; + untrained-cardio day-zero state). Delete/retire `dormant_cardio_row.dart`. Skeleton to borrow: `body_part_rank_row.dart:41`.
8. **Vitality two-speed (net-new):** `vitality_calculator.dart:23-41` (single τ today) → per-bp τ (cardio 21d); `vitality-nightly/index.ts:104-110` (TAU + cardio-excluded set) → include cardio + cardio τ; parity (the EWMA closed-form integration tests).
9. **CardioEntryRow (post-session):** new sibling of `lift_row.dart` (teal dot, duration hero, distance/pace dim suffix via `CardioFormat`, `FittedBox` 320dp guard, NO PR/heroGold); insert in `mission_debrief_section.dart:182-193` (today loops strength-only `topLifts` from `post_session_controller.dart:213`). Mixed strength+cardio ledger must read coherent.
10. **148→172 computed-max:** fixtures `generate_rpg_fixtures.py:405` (7-key all-99→172) + regen `rpg_xp_fixtures.json:1144`; tests `rank_curve_test.dart:274,284`, `titles_repository_test.dart:392`. (Title threshold 148 untouched — 38f.)

**Auto-extends on flip (verify, no change):** all providers (`character_sheet_provider:59`, `class_provider:40`, `rpg_progress_provider:43,69`, `stats_provider:119,168,299,310`), `StatsDeepDiveState.empty`, `celebration_event_builder` (rank-up/level-up/class-change/first-awakening loops — auto-fires cardio cuts), `vitality_trend_chart:106` (7th line), `vitality_table` (7th row — add the band), B2 cut floods (teal via hue map), `post_session_controller:194` ranksToNextLevel (will include cardio — must match SQL char-level).

**Tests to rewrite (assert old 6/148/cardio-excluded):** `attribution_test.dart:212-215` (length==6, !contains cardio), `class_resolver_test.dart:209` (Ascendant excludes cardio), `vitality_state_styles_test.dart:103`, `vitality_trend_chart_test.dart:99,132,229`, `vitality_table_test.dart:45`, `character_sheet_screen_test.dart:254,303,338,354-355` (findsNWidgets(6) + DormantCardioRow), `character_card_test.dart:752,759,839`, `rank_curve_test.dart:274,284`, fixtures. E2E: `selectors.ts:1468-1469` (`dormantCardioRow`→cardio row), `saga.spec.ts` class/level, `rank-up-celebration.spec.ts` parity levels, `rpg-foundation.spec.ts` levels.

### Implementation checklist (tech-lead, 2026-06-17) — branch `feature/phase38e-cardio-activation`
**Layer 1 — Vitality two-speed (net-new):**
- [x] `vitality_calculator.dart`: per-bp τ_down (cardio 21d, strength 42d); `alphaDownFor` + `step({tauDownDays})` + `tauDownForBodyPart`.
- [x] `vitality-nightly/index.ts`: `stepEwma({tauDownDays})`; loop 7-part `ACTIVE_BODY_PARTS`; cardio τ=21d; `aggregateAttribution` +cardio key.
- [x] Parity: EWMA closed-form cardio decay (Dart unit — cardio α_down ≈ 0.2835, faster fall than strength).

**Layer 2 — The flip (atomic):**
- [x] `body_part.dart` `activeBodyParts` +cardio; new `strengthBodyParts` const.
- [x] `rank_curve.dart` `_activeKeys` +`'cardio'`; denom `~/4` stays.
- [x] `character_xp_calculator.dart` `_activeKeys` +`'cardio'`.
- [x] Migration `00080`: `character_state` view + the 4 in-RPC level snapshots → new `rpg_active_body_part_level(uuid)` helper (7-part list in ONE place). Backfill chunk has NO level filter — confirmed + unchanged. Applied to LOCAL via `db reset`.
- [x] `class_resolver.dart` + `class_provider.dart` → `strengthBodyParts` subset (cardio OUT of class/Ascendant). NO Wayfarer.

**Layer 3 — Hue:**
- [x] `body_part_hues.dart` cardio `hair`→`bodyPartCardio` (flows to rows/flood/chart/table via the shim).

**Layer 4 — Widgets (LOCKED mockup 38e Surfaces 1/2/3):**
- [x] Mockup: deleted dead Surface 4 (+A/B note), fixed 5c (SENTINEL not Wayfarer), trimmed build-notes compound-class bullet, updated header.
- [x] `CardioProgressRow` (banded; alive + untrained dimmed-teal variant); wired into `character_sheet_screen.dart` AND `character_card.dart` (home); retired `dormant_cardio_row.dart` + its Semantics block.
- [x] `CardioEntryRow` (post-session debrief; teal dot, duration hero, dim suffix, FittedBox 320dp, NO PR/gold); `SessionCardioSummary` model + controller projection + `mission_debrief_section.dart` insert + screen passes distanceUnit/locale.
- [x] l10n: `cardioTrackLabel` (CONDITIONING/CONDICIONAMENTO) en+pt; dead `dormantCardioCopy` removed.
- [x] **SPLIT VALVE — DEFERRED → 38e-bis:** vitality table per-row cardio decay subtitle ("Conditioning fades in ~3 weeks") + one-time stats explainer note + chart legend cardio-chip label. NOTE: the table cardio ROW + the trend-chart 7th teal LINE already auto-extend (stats surfaces iterate activeBodyParts + read the hue map) — only the decay-subtitle COPY + explainer banner are deferred. Minimum coherent flip is fully atomic in this PR.

**Layer 5 — Fixtures + tests:**
- [x] `generate_rpg_fixtures.py` 7-key (+ never-regress 6×20+cardio-1=29 case); regen `rpg_xp_fixtures.json` (all-99→172).
- [x] Rewrote 6/148/cardio-excluded tests (attribution, rank_curve, class_resolver, character_sheet_provider, stats_provider, vitality_state_styles, character_card, character_sheet_screen, rpg_acceptance). Added: never-regress (named thesis test), char-level-with-cardio, class-strength-only + Wayfarer-absent + Ascendant-cardio-noise, CardioProgressRow/CardioEntryRow states (incl untrained + 320dp), vitality cardio τ two-speed, CardioFormat.pace.
- [x] l10n en+pt + `@key`; `gen-l10n`; `arb_completeness` green.
- [x] Non-integration suite: 3727 pass / 0 fail / 1 skip. Cardio sim 14/14. Integration: running.

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
