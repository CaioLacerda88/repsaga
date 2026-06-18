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

### Decisions locked (user, 2026-06-17)
- **Title names APPROVED as-is** (ladder + Saga-Unending@172 + cross-build triangle — table below).
- **VITALITY_XP_GATE: WIRE IN 38f.** The plan/old-WIP wrongly assumed cardio's
  `VITALITY_XP_FLOOR=0.40` gate was applied in 38c — it is NOT (only in the Python sim;
  `record_cardio_session` (00079) earns `base×tdm×mod×3.5` with NO vitality mult). 38f
  adds the cardio vitality XP-multiplier `mult = FLOOR + (1−FLOOR)×vpct` (vpct =
  clamp(cardio vitality_ewma/peak,0,1)) to `record_cardio_session` (SQL) + mirror in
  `cardio_xp_calculator.dart`; regen the 4-site parity (the sim applies it caller-side at
  `cardio-xp-simulation.py:412`, so add a vitality-gated fixture section + update the
  earning parity test). **Strength NOT retrofitted.**

### Boundary inventory (filled via Explore) — ⚠ migration-number corrections
- **Current XP RPC def = `00080`** (NOT 00077); cross-build evaluator current = **`00049`**.
  New migration **00081** does `CREATE OR REPLACE` from 00080/00049 bodies.
- **Title data pattern (mirror for cardio):** `title_thresholds_table.dart` flat const
  list, `TitleThresholdKind{bodyPart,characterLevel,crossBuild}`, sorted by slug per kind.
  Each strength part = **13 rungs @ thresholds 5,10,15,20,25,30,40,50,60,70,80,90,99**;
  slug `<part>_r<thr>_<name>`. Char-level ladder 7 rungs ending `saga_eternal@148`
  (`assets/rpg/titles_character_level.json`). Cross-build 5 entries; predicate in Dart
  (`cross_build_title_evaluator.dart`) — MUST stay bit-identical to the SQL mirror.
- **Add for cardio:** 13 `cardio_r*` bodyPart entries (in `titles_v1.json` + the table —
  loader injects `kind:body_part`), 1 char-level `saga_unending@172`, 2 cross-build.
  ⚠ `BodyPart.cardio` is now a real enum value (38e) — confirm.
- **l10n:** keys `title_<slug>_name` / `_flavor` in `app_en.arb`+`app_pt.arb`; EXHAUSTIVE
  switch `title_localization.dart` needs a CASE per new slug (else raw slug shows).
- **SQL award:** body-part VALUES + char-level VALUES lists in BOTH `record_set_xp` +
  `record_session_xp_batch` (`00080`); cross-build delegated to
  `evaluate_cross_build_titles_for_user` (`00049`) — extend all. Add `('saga_unending',172)`
  to char-level VALUES; add 13 cardio `(slug,'cardio',thr)` to body-part VALUES.
- **Titles screen auto-wires** (iterates `activeBodyParts`) — BUT `VitalityStateStyles.bodyPartColor`
  needs a **teal cardio entry** or cardio rungs render grey; new cross-build slugs need
  `crossBuildStatsFor` + `gapHintFor` cases.
- **Count guard:** `titles_repository_test.dart` asserts **90 → 106** (+13 cardio +1 char +2 cross);
  add `perBodyPart[cardio]==13`. Title-table↔JSON drift test + e2e `titles.spec.ts`.
- ⚠ **iron_bound tightening must NOT revoke** already-earned titles (`earned_titles` append-only;
  future awards only — the backfill must not DELETE).

### LOCKED title spec (user-approved 2026-06-17)
**Cardio ladder** (`cardio_r<thr>_<name>`, kind=bodyPart, BodyPart.cardio):
`5 first_stride` (First Stride) · `10 breath_found` (Breath-Found) · `15 wind_touched`
(Wind-Touched) · `20 pace_keeper` (Pace-Keeper) · `25 long_strider` (Long-Strider) ·
`30 wind_drawn` (Wind-Drawn) · `40 tempo_sworn` (Tempo-Sworn) · `50 wind_crowned`
(Wind-Crowned) · `60 breath_forged` (Breath-Forged) · `70 wind_runner` (Wind-Runner) ·
`80 stride_of_storms` (Stride of Storms) · `90 wind_untouched` (Wind-Untouched) ·
`99 the_stride` (The Stride).
**Char-level @172:** `saga_unending` (Saga-Unending) — "One seventy-two. Nothing left to
forge — only the legend, going on without end." / pt "Saga-Sem-Fim".
**Cross-build (predicates — keep Dart↔SQL bit-identical; cardioRank defaults to 1):**
- `iron_bound` AMEND: `chest≥60 AND back≥60 AND legs≥60 AND cardioRank≤10` (flavor unchanged).
- `the_forged_wind` NEW: all 6 strength ≥60 AND cardioRank≥60 ("The Forged Wind" /
  "O Vento Forjado" — "Every track at sixty, the lungs among them. Iron that runs.").
- `storm_tempered` NEW: cardioRank≥60 AND all 6 strength ≥30 ("Storm-Tempered" /
  "Temperado-na-Tempestade" — "The lungs of a gale, hands that still know iron.
  Tempered, not narrowed.").
> Full en+pt name+flavor for all 16 = the ui-ux-critic proposal (this session). The
> tech-lead fills the ARB from that table; the slugs/thresholds/predicates above are authoritative.

### Pipeline checklist
- [x] Boundary Explore → fill the inventory.
- [x] Draft the cardio ladder names → **USER APPROVAL** (locked 2026-06-17).

#### Workstream A — cardio titles (content + award)
- [x] A1 title data: table + 3 JSON assets.
- [x] A1b `CrossBuildTriggerId` enum: +theForgedWind +stormTempered.
- [x] A2 l10n en+pt: 16 slugs × name+flavor + @-desc on en; gen-l10n.
- [x] A3 `title_localization.dart`: CASE per new slug.
- [x] A4 `cross_build_title_evaluator.dart`: iron_bound + 2 new + gapHint/stats.
- [x] A5 cardio bodyPartColor teal — already landed in 38e (verified).
- [x] A6 SQL 00081 PART B/C (writers) + PART A (evaluator).
- [x] A7 counts: titles_repository_test 106; drift test; evaluator test; rpg_acceptance (3 fixed); pill widget + e2e titles.spec.

#### Workstream B — cardio vitality XP-gate
- [x] B1 SQL record_cardio_session (00081 PART D): vmult applied to v_xp.
- [x] B2 Dart `cardio_xp_calculator.dart`: vitalityXpMult/vitalityPct + vitalityMult param.
- [x] B3 fixture cardio_vitality_gate (6 rows) + Dart parity test + integration gate test; sim 14/14.

#### Verify — ALL GREEN
- [x] gen + gen-l10n; format; analyze 0; unit/widget 3758 pass / 1 skip;
      integration 72 pass; cardio sim 14/14; fixture byte-deterministic.
