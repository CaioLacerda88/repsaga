# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in
`docs/PROJECT.md` → `## §2 Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `docs/PROJECT.md` phase or backlog entry, check
items off as work lands, and remove the section after the merge condenses
the phase summary in PROJECT.md §4.

---

## Phase 38c — Cardio earning formula + 4-site parity + est-VO₂max

Branch `feature/phase38c-cardio-earning`. Per the plan
(`~/.claude/plans/noble-stirring-scroll.md` → "PR 38c") + the source-of-truth
sim `tasks/cardio-xp-simulation.py` (14/14 personas pass) + `docs/cardio-stat-plan.md`
§2.5/§2.6/§4–§7 + `docs/cardio-balance-baseline.md`.

**Goal:** cardio XP accrues to `body_part_progress`/`xp_events` but stays **SILENT**
— cardio is NOT added to `activeBodyParts`/`character_state` (that's 38d). Earn path
is verifiable in DB, invisible in UI, so it's validated before the 38d flip.

### Locked decisions (this session, 2026-06-15)
1. **est-VO₂max = full chain** (user pick): race-equation best-effort (Cooper 12-min /
   1.5-mi / velocity→ACSM running VO₂ → back-project via the sim's
   `sustainable_fraction` curve) when distance+duration present → **rolling per-user
   max**; **non-exercise (age/sex/BMI) seed** for cold-start & duration-only logs.
2. **Cross-credit (strength→cardio) stays IN 38c** (user pick): derive per-session
   `est_met` from work-density → ACSM MET band; feed the same `record_cardio_session`
   as a fixed-MET `kind='abs'` entry. Strictly one-directional (gate already structural
   in 00077). Bands locked (ACSM 2024): light/moderate ~3.5, vigorous free-weight ~5.0,
   powerlifting/BB vigorous ~6.0, dense circuit ~8.0. The work-density→band derivation
   fn is tech-lead's to propose → sign-off before merge.
3. **Port the sim verbatim as v1** (plan default): all sim constants treated as locked
   for this PR; calibration sign-off (tier bands vs ACSM, VITALITY_XP_FLOOR) stays in 38f.
   ⚠ sim/baseline headers say "v1 DRAFT" — re-confirm constants with user only if a
   parity mismatch forces a re-tune.

### Boundary inventory (filled — implementation may start) — from Explore + formula-digest agents

**Cardio XP write path (SQL) — what `record_cardio_session` must reuse:**
- Strength writers to mirror: `record_session_xp_batch(uuid)` (most recent redef
  `00077:632`), `record_set_xp(uuid)` (`00077:90`), `_rpg_backfill_chunk` (3rd writer,
  not a per-session entry). float8 hot path, SECURITY DEFINER, `SET search_path=public`.
- Grants pattern (re-state verbatim): `REVOKE EXECUTE … FROM PUBLIC, anon; GRANT … TO
  authenticated` (`00077:625-626`).
- `xp_events` INSERT `00077:977-985` (cols incl. `event_type`, `set_id`, `session_id`,
  `payload`, `attribution`, `total_xp`); `ON CONFLICT (user_id,set_id) WHERE set_id IS
  NOT NULL DO NOTHING`. **Cardio has NO set_id** → 38c must pick a distinct conflict key
  (likely `event_type<>'set'`, `set_id NULL`, `session_id=workout_id`).
- `body_part_progress` UPSERT `00077:987-1009`; `rank = rpg_rank_for_xp(total)`.
- 7-wide arrays + index map already present: `'cardio'→7` (`00077:891-900`), reverse map
  `WHEN 7 THEN 'cardio'` (`00077:996-1000`), `v_weekly_cardio` slot pre-wired
  (`00077:676,782,792`) — **dead-but-harmless today; 38c lights up index 7.**
- Reuse VERBATIM: `rpg_tier_diff_mult(numeric,numeric)` (`00065:472-494`),
  `rpg_cumulative_xp_for_rank(int)` piecewise (`00065:301-316`), `rpg_rank_for_xp(numeric)`
  (`00040:399-412`). **Do NOT reuse `rpg_base_xp`** — cardio base = `capped_met_min^0.60`
  (different input domain); reuse only the `0.60` exponent constant.

**save_workout contract + cross-credit hook:**
- Signature after 00078: `save_workout(p_workout jsonb, p_exercises jsonb, p_sets jsonb,
  p_cardio jsonb DEFAULT '[]') RETURNS jsonb` (`00078:140-145`). Only Dart caller:
  `workout_repository.dart:67-114` (`p_cardio` at :111, RPC name :82).
- Cardio persists via DELETE+INSERT into `cardio_sessions` (`00078:214,253-264`,
  re-pins `workout_id` server-side), then `PERFORM record_session_xp_batch(v_workout_id)`
  at `00078:266`. Cross-credit hook = between that PERFORM and bucket logic, OR inside
  the batch (has per-set weight/reps/rest via sets→workout_exercises join).
- ⚠ **Reversal risk:** BUG-RPG-001 reversal (`00078:189-206`) reverts `body_part_progress`
  by summing `xp_events.attribution` for the session via `jsonb_each_text` over ALL keys.
  Cardio `xp_events` with `session_id=workout_id` + a `cardio` attribution key will revert
  cleanly on re-save **iff** the attribution lands the same way. Pin with an idempotent
  re-save integration test.

**`cardio_sessions` columns (00078:62-70):** `id, workout_id(FK), exercise_id(FK),
duration_seconds NOT NULL >0, distance_m NULL >=0, rpe NULL 1-10, created_at`. **No
`met`/`met_minutes`/`est_met` columns yet — 38c adds them** (deferred per 00078 header).
No `user_id` (ownership via workout_id FK).

**4-site parity machinery (Python → fixture → Dart → SQL):**
- Site 1 (Python oracle): `tasks/cardio-xp-simulation.py` — entry pts `compute_session_xp`
  (:342-371), `session_met_and_intensity` (:317-339), `demonstrated_vo2` (:306-311),
  `implied_cardio_tier` (:284-287), shared `tier_diff_mult` (:222-232). Currently
  standalone (NOT imported by the fixture generator) → 38c must wire it in.
- Site 2 (fixture): `test/fixtures/rpg_xp_fixtures.json`, generated by
  `test/fixtures/generate_rpg_fixtures.py` (loads sim via `importlib` against hyphenated
  filename, :46-62). Add cardio sections (`cardio_session_xp` end-to-end + component
  lists). Store **raw unrounded** floats (sim panel rounds to int at :429).
- Site 3 (Dart): `test/unit/features/rpg/xp_calculator_test.dart` pattern (set_xp_v2
  replay :942-947). New `cardio_xp_calculator_test.dart` consumes the cardio section.
- Site 4 (SQL): `test/integration/rpg_record_set_xp_test.dart` pattern (seeds via RPC,
  reads live `body_part_progress.total_xp`). Tolerance: **Dart↔Python = 1e-4**;
  **SQL↔Dart live-row = 0.01** (batch rounds per-bp XP to 4 dp before persisting).
- ⚠ **Section-count guard:** `test/unit/features/rpg/domain/phase29_formula_parity_test.dart`
  (:44-138) pins required fixture sections + exact row counts + meta keys → MUST be
  extended for the new cardio sections or they go unguarded.
- No standalone CI parity script — enforced purely via `flutter test`.

**Dart calculator to mirror:** `lib/features/rpg/domain/xp_calculator.dart` (class
`XpCalculator`, private const ctor, static methods, entry `computeSetXp(...)`→
`SetXpComponents` w/ `toJson()` mirroring `xp_events.payload`). `CardioXpCalculator`
follows this shape; inputs map to sim `compute_session_xp(vo2max, age, female, modality,
duration_min, kind, value, current_rank, week_cap_state)` → `(xp, met_minutes, rel_intensity)`.
`xp_distribution.dart` already accepts the `cardio` attribution key (earns nothing in the
char-level path until 38d) — no change needed there.

**est-VO₂max — confirmed NET-NEW (no existing code):** sim takes vo2max as a *given
input*; the estimation chain is prose-only in `cardio-stat-plan.md` §2. Two sim VO₂
pathways exist to reuse: (a) per-session `demonstrated_vo2` (:306-311) and (b) the rolling
training-progression curve (`simulate_cardio` :421-423, consts VO2_GAIN_K=0.040,
VO2_STIMULUS_NORM=1200, VO2_CEILING_CAP=90). VO₂→percentile→tier via `_VO2_NORMS`
(:240-253) + `_TIER_ANCHORS` (:255-256). **The app's estimate-from-logged-data chain
(race equations + non-exercise seed + rolling max) is the net-new design — tech-lead
proposes specific equations, sign-off before fixture regen.** Profile fields available
for non-exercise seed need confirming (age/sex/weight yes; **height/BMI = verify**).

### Locked formula constants (from `cardio-xp-simulation.py`, verified 14/14)
`MET_REST=3.5` · `VOLUME_EXPONENT=0.60` (shared w/ strength) · `CARDIO_XP_SCALE=3.5` ·
`WEEKLY_CARDIO_CAP_METMIN=2500` · `OVER_CAP_MULT=0.30` · `VITALITY_XP_FLOOR=0.40` ·
cardio vitality kinetics `τ_down=3.0 wk` / `τ_up=2.0 wk` (**NOT** strength's 6.0/2.0 —
"never copy between stats") · `INTENSITY_ANCHORS` (0.35,.05)(0.50,.35)(0.70,.75)(0.85,1.05)(0.95,1.35)(1.05,1.45) ·
`MODALITY_MULT` run/treadmill/row/swim=1.00, elliptical=0.97, bike/walk=0.95, hiit=1.05,
strength=0.80, circuit=0.90 · `tier_diff_mult` + rank curve reused VERBATIM.
Formula order: `eff_met_min = abs_met×dur×intensity_mult(rel)` → weekly cap split at 2500
→ `base = capped^0.60` → `× tier_diff_mult(rank, demonstrated_tier) × modality × 3.5`
→ `× vitality_xp_mult` (caller-applied, computed once per week from start-of-week conditioning).
14-persona oracle XP values captured in the formula-digest agent output (use for fixture).

### Implementation checklist (TDD per CLAUDE.md pipeline)
- [ ] **product-owner gut-check** (thesis-dilution): confirm cardio-as-7th-track + cross-credit don't dilute the RPG thesis (`project_rpg_thesis`). Quick pass — design is pre-locked.
- [ ] **Migration `00079`**: add `met`, `met_minutes`, `est_met` (+ any est-VO₂max persistence) cols to `cardio_sessions`; new `record_cardio_session(p_workout_id uuid)` reusing tier_diff_mult + rank curve verbatim; cardio `xp_events`/`body_part_progress` writes (distinct conflict key, no set_id); wire into `save_workout` after the batch PERFORM; cross-credit est_met derivation in the strength path. RLS/grants verbatim. Cardio STAYS OUT of `activeBodyParts`/`character_state`.
- [ ] **Dart `CardioXpCalculator`** (`lib/features/rpg/domain/`, mirrors `XpCalculator`) + `CardioXpComponents` w/ `toJson()`.
- [ ] **est-VO₂max util** (net-new): race-equation best-effort + non-exercise seed + rolling per-user max. tech-lead proposes equations → sign-off.
- [ ] **Cross-credit work-density→MET-band fn** (net-new): tech-lead proposes → sign-off.
- [ ] **4-site parity:** extend `cardio-xp-simulation.py` for generator import; regen `rpg_xp_fixtures.json` with raw cardio rows; Dart parity test; SQL integration parity test; **update `phase29_formula_parity_test.dart` section-count guard**.
- [ ] **Tests:** formula unit tests (14 personas @1e-4), est-VO₂max unit tests, cross-credit tests, idempotent re-save integration test (reversal pin), no-cardio-in-character-level assertion.
- [ ] `make gen` + `dart format` + `dart analyze --fatal-infos` + `make test` green; `python tasks/cardio-xp-simulation.py` still 14/14.
- [ ] reviewer → fixes → QA gate (E2E selector impact only; no UI surface in 38c) → `make test-integration` green (local Supabase) → PR.
- [ ] Verify before PR (verification-before-completion skill) → ship → `npx supabase db push` 00079 to hosted.
