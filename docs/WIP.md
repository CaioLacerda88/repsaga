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
0. **DESIGN PROPOSAL ACCEPTED** (tech-lead, appended below) — all formulas/constants in
   "Phase 38c DESIGN PROPOSAL" are the implementation spec. Accepted defaults: best-effort
   VO₂ = velocity→ACSM running eq → back-project via sim `sustainable_fraction` (run/treadmill
   only in v1; bike/row/swim = duration-only, distance still stored); p25 non-exercise seed;
   42-day best-of rolling window stored as `profiles.cardio_vo2max`; cross-credit consts
   `SET_WORK_SECONDS=30`/`REST_DEFAULT=90`; est-VO₂max + cross-credit are app-only with
   parity-checked pure cores (NO persona re-tune). Sub-decisions D2–D5 = tech-lead defaults.
0a. **AGE handling** (user pick): add **nullable `profiles.date_of_birth`** column NOW
   (migration only, **no onboarding UI** in 38c); formula uses real age when present,
   **`AGE_FALLBACK=35`** when NULL; gender NULL→male table (Phase-29 default). The DOB
   collection UI + LGPD consent + existing-user backfill = **separate later task** (note in
   PROJECT.md §2 backlog at merge).
1. **est-VO₂max = full chain** (user pick): race-equation best-effort (velocity→ACSM running
   VO₂ → back-project via the sim's `sustainable_fraction` curve) when distance+duration
   present → **rolling per-user max** (`profiles.cardio_vo2max`); **p25 non-exercise seed**
   from (age|35, sex|male) for cold-start & duration-only logs.
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

---

### 38c DESIGN PROPOSAL — est-VO₂max chain + cross-credit work-density fn (sign-off pending)

> Status: **proposal, no code yet.** Reviewed → user-signed-off → becomes the impl spec
> for the 00079 migration + Dart utils + fixture sections. Precision over prose.

#### ⚠ Hard constraint that reshapes the whole chain: the profiles table has NO age and NO height

Confirmed against every `profiles` migration (00001 base + 00002/00006 weight_unit, 00011
training_freq, 00022 locale, 00056 `bodyweight_kg numeric(5,2) NULL`, 00065 `gender text NULL`,
00072 onboarded_at) and the Dart `Profile` model. **Stored & usable for VO₂ estimation:
`gender` (nullable text male/female/other) + `bodyweight_kg` (nullable numeric).** There is
**no `date_of_birth`, no `age`, no `height`.**

This is load-bearing because the sim's ENTIRE VO₂→tier path is age-keyed:
`_age_band(age)` selects the `_VO2_NORMS[(sex, decade)]` row used by both `vo2_to_percentile`
(→ standing tier) and `demonstrated_vo2`→`implied_cardio_tier` (→ per-session burst tier).
Age is also the dominant term in every non-exercise VO₂ seed equation in the literature
(Jackson 1990, NHANES). We literally cannot evaluate the locked formula without an age.

**Resolution (recommended, see Open Decision #1):** add **`profiles.date_of_birth date NULL`**
in 00079 and collect it at onboarding (single date picker; LGPD-minimal — store DOB not age so
age stays correct over time; derive `age = floor(months_between(now, dob)/12)`). When DOB is
NULL, fall back to a fixed **`AGE_FALLBACK = 35`** (median adult; lands mid-decade-band, the
most-forgiving misclassification). Gender NULL → `'male'` table (verbatim mirror of the Phase 29
`female=False` default + the sim's own default). This keeps the formula evaluable for every user
on day one and makes age a sharpener, not a hard dependency.

---

#### A. est-VO₂max chain — concrete formulas

The chain produces ONE number per user, `standing_vo2max` (mL·kg⁻¹·min⁻¹), which feeds
`session_met_and_intensity(vo2max, …)` (relative intensity) AND is the value the rolling
estimate maintains. **Per-session `demonstrated_vo2` is computed separately and verbatim from
the sim** (`abs_met×3.5 / sustainable_fraction(dur)`) — it drives the tier burst and is NOT the
standing estimate. Keep the two strictly separate exactly as the sim does (the thesis honesty
guarantee). The estimation chain below only computes/updates `standing_vo2max`.

**A1. Best-effort from a logged session (primary method — REUSES sim code for parity)**

Primary method = **velocity → ACSM running VO₂ → back-project via the sim's
`sustainable_fraction`**, NOT Cooper. Rationale: (a) it reuses `sustainable_fraction` and
`MET_REST` already in the sim → zero new constants to calibrate, automatically parity-correct;
(b) Cooper is a *fixed-12-min protocol* equation — applying it to an arbitrary-duration logged
run is a misuse; (c) it generalizes across durations, which manual logs are.

For a session with `distance_m` and `duration_seconds`, modality ∈ running family:

```
v_m_per_min      = distance_m / (duration_seconds / 60)
acsm_vo2         = 0.2 * v_m_per_min + 3.5          # ACSM horizontal-running eq, grade=0
demonstrated     = min(90, acsm_vo2 / sustainable_fraction(duration_min))   # ← sim fn, verbatim
best_effort_vo2  = demonstrated
```

This is *exactly* `demonstrated_vo2`, but with `abs_met` derived from measured pace
(`acsm_vo2/3.5`) instead of an estimated MET. So `best_effort_vo2 == demonstrated_vo2(acsm_vo2/3.5, dur)`.
One code path, reused.

> **Worked example — 30-min, 5 km run:** v = 5000/30 = 166.7 m/min → acsm_vo2 = 0.2·166.7+3.5
> = 36.83. sustainable_fraction(30) = 0.88. best_effort = 36.83/0.88 = **41.9 mL/kg/min**.
> (Sanity: a 30-min 5 k is a 6:00/km recreational effort → ~42 VO₂max ≈ 50th pct M30. Correct.)

**ACSM grade term deliberately dropped** (`0.9·v·grade`): we store no incline. Flat assumption
slightly *under*-credits hill runs — acceptable and conservative (never inflates fitness).

**A2. Selection logic (which method fires)**

```
if duration_seconds present AND distance_m present AND modality ∈ DISTANCE_MODALITIES:
        → A1 best-effort (velocity→ACSM→back-project)
elif duration_seconds present (duration-only, OR non-distance modality):
        → no new demonstration; standing estimate unchanged this session
            (rolling max is NOT lowered — see A4). The session still EARNS XP using the
            current standing estimate for rel-intensity; it just doesn't re-estimate VO₂max.
else: impossible (duration mandatory per 00078 CHECK).
```

`DISTANCE_MODALITIES = {run, treadmill}`. Distance is only physiologically interpretable as
pace→VO₂ via the ACSM *running* equation for run/treadmill. **Cycling/rowing/swim distance is
NOT used for A1** — bike VO₂-from-speed needs power/resistance we don't capture; rowing pace→VO₂
needs a different (Concept2) equation; swim distance→VO₂ is a different equation again with huge
technique variance. v1: those modalities are **duration-only for estimation** (A2 branch 2),
even when the user logged a distance. Distance is still *stored* and shown; it just doesn't feed
est-VO₂max in v1. (Open Decision #2: add row/bike equations in 38f calibration.)

**A3. Non-exercise seed (cold start — no qualifying history)**

Uses only confirmed fields (DOB→age, gender, bodyweight_kg) plus the `AGE_FALLBACK`/gender
defaults. **Source: the non-exercise VO₂max equation requires height for BMI; we don't store
height, so use the weight-only NHANES/Jackson-family form anchored on the ACSM percentile
midpoint instead of inventing a height proxy.** Cleanest defensible v1:

```
seed_vo2 = _VO2_NORMS[(sex, age_band)] interpolated at the 25th percentile
            (a "below-median, untrained-adult" prior — deliberately conservative)
```

i.e. `seed_vo2 = norms[1]` (the p25 anchor) for the user's `(sex, age_band)`. This is
self-consistent with the rest of the system (same `_VO2_NORMS` table → same tier scale), needs
zero new constants, and encodes the right prior: a brand-new user is assumed below-median until
they demonstrate otherwise, so their first real efforts can only *raise* the estimate. bodyweight
is NOT used in the seed v1 (the only weight-using non-exercise equations need height too); it
stays available for a future BMI-based refinement once/if height is collected. **Citation:**
ACSM/Cooper Institute VO₂max percentile norms (the `_VO2_NORMS` table, already in the sim, cited
in `cardio-balance-baseline.md`); the "p25 untrained prior" choice is ours, documented here.

> Worked: new M, age 30 (or NULL→35), no logs → seed = `_VO2_NORMS[("M",30)][1]` = **35.9**.
> First 30-min 5 k (A1 → 41.9) demonstrates fitness → rolling max lifts seed to 41.9 (A4).

**A4. Rolling per-user estimate (how standing_vo2max updates)**

**Best-of trailing window, NOT EWMA, NOT max-ever.** Rule:

```
standing_vo2max = max( seed_vo2,
                       max(best_effort_vo2 over qualifying sessions in trailing 42 days) )
```

- **Why best-of-window, not EWMA:** VO₂max estimation should credit your *best demonstrated*
    effort (you don't get less fit because your last run was easy), but must *decay* if you stop
    demonstrating (a 42-day-old PR shouldn't define you forever — mirrors the Coyle detraining
    physiology the Vitality layer already encodes). 42 days ≈ 6 weeks ≈ the τ_down=3wk Vitality
    window doubled (a full conditioning half-life). **The standing estimate is NEVER lowered
    *within* the window** (best-of), only when the best qualifying session ages out.
- **Seed floor:** can't drop below the non-exercise seed (a deconditioned user still has a
    baseline VO₂max).
- This is distinct from the sim's `simulate_cardio` progression curve (VO2_GAIN_K=0.040…). That
    curve is the *Python persona generator's* model of how VO₂ rises over a simulated 12 weeks;
    the **app** doesn't simulate progression — it reads it from real logged efforts via best-of-
    window. The two never need to agree numerically (the sim's vo2 is a persona INPUT; the app's
    is derived from logs). See §C.

**Storage:** `standing_vo2max` is per-user, not per-session → does NOT belong on
`cardio_sessions`. **Recommended: a new column on `profiles`:**

```sql
ALTER TABLE public.profiles
    ADD COLUMN cardio_vo2max numeric(4,1) NULL,         -- last computed standing estimate
    ADD COLUMN cardio_vo2max_updated_at timestamptz NULL,
    ADD COLUMN date_of_birth date NULL;                 -- see hard-constraint section
```

Rejected `user_cardio_state` side-table: standing VO₂max is a single scalar per user, 1:1 with
profile, read on every cardio session save — a column avoids a join on the hot path. The
recompute (best-of-window query over `cardio_sessions` joined through `workouts`) runs inside
`record_cardio_session` and writes back `cardio_vo2max`. Storing it (vs recomputing every read)
also lets the UI show "your est. VO₂max" in 38d without a window scan. The `idx_cardio_sessions_
exercise_id` + workout join already exists (00078:78) for the window query.

**A5. First-ever session resolution (end to end)**

1. Save fires `record_cardio_session(workout_id)`.
2. Read `profiles.cardio_vo2max`; NULL → compute A3 seed from (DOB→age|35, gender|male) → that's
     the `vo2max` used for THIS session's rel-intensity (`session_met_and_intensity`).
3. Compute the session XP (verbatim sim chain) using that vo2max.
4. AFTER XP: recompute rolling max (A4) including this session's `best_effort_vo2` if it
     qualifies (A1); write `cardio_vo2max` + `_updated_at`. So the seed governs session #1's
     reward, and session #1 immediately updates the standing estimate for session #2.

---

#### B. Cross-credit: strength work-density → MET band

**Inputs available in the save path** (boundary inventory): per-set `weight, reps, set_type,
is_completed` via `sets`→`workout_exercises`; session wall-clock `workouts.duration_seconds`;
per-exercise `rest_seconds` on `workout_exercises`; completed-set count. **No per-set
timestamps** → inter-set rest comes from `workout_exercises.rest_seconds` (the planned rest),
which is the honest available signal.

**Definition of work density** (the single discriminating signal):

```
completed_sets   = count(sets WHERE is_completed AND set_type IN ('working','warmup'? no → working only))
work_seconds_est = completed_sets * SET_WORK_SECONDS         # SET_WORK_SECONDS = 30 (a ~8-12 rep set under tension)
total_rest_est   = sum over working sets of COALESCE(we.rest_seconds, REST_DEFAULT)   # REST_DEFAULT = 90
session_seconds  = GREATEST(workouts.duration_seconds, work_seconds_est + total_rest_est)
density          = work_seconds_est / session_seconds        # fraction of the session spent under load, [0,1]
sets_per_min     = completed_sets / (session_seconds / 60)
avg_rest         = total_rest_est / max(1, completed_sets)
```

**Decision function → one of {3.5, 5.0, 6.0, 8.0}** (ACSM 2024 Compendium RT codes, the bands
locked in WIP §2):

```
est_met =
    8.0   if density >= 0.45 AND avg_rest <= 45          # dense circuit / metcon (02040)
    6.0   if avg_rest <= 75  AND sets_per_min >= 0.50    # vigorous PL/BB, moderate rest (≈02054 high)
    5.0   if avg_rest <= 120                             # vigorous free-weight (02054)
    3.5   otherwise                                      # light/moderate, long rest (02050)
```

Evaluated top-down (first match wins). All thresholds are on *estimated/planned* signals —
**never user-declared.** The user never sees or sets MET; "I did a hard workout" cannot move it.
One-directional: this `est_met` only ever feeds the cardio pipeline as a `kind='abs'` entry; it
never touches the strength formula. (Structural gate already in 00077 per boundary inventory.)

**Worked examples (cross-checked against the sim's `_lift(met=3.8)` / `_metcon(met=8.0)`):**

- *Powerlifter* — 20 working sets, 60-min session, rest_seconds=180. work_est=600s,
    rest_est=3600s, session=GREATEST(3600, 4200)=4200s. density=600/4200=0.14, avg_rest=180,
    sets/min=20/70=0.29 → no branch hits until `else` → **est_met=3.5**. Sim persona uses
    `_lift` met=3.8; 3.5 is one band below, lands in the SAME tier outcome: `demonstrated_vo2(3.5,
    60)=3.5·3.5/0.80=15.3` → tier ≈3 → rank band 1-10. Powerlifter stays ~0 cardio rank. ✓ (The
    0.3-MET gap vs the persona's 3.8 is immaterial to the tier/rank outcome — both demonstrate
    walking-level VO₂. If parity needs the persona to land *exactly*, see §C — the persona keeps
    its literal 3.8 MET; the derivation fn is app-only.)
- *Metcon* — 15 working sets, 28-min session, rest_seconds=30. work_est=450s, rest_est=450s,
    session=GREATEST(1680, 900)=1680s. density=450/1680=0.27 → not ≥0.45. avg_rest=30≤45 but the
    8.0 branch also requires density≥0.45 → fails. Falls to 6.0? avg_rest 30≤75 AND sets/min
    15/28=0.54≥0.50 → **est_met=6.0.** ⚠ **This UNDER-shoots the persona's 8.0.** The density
    threshold is too strict when `workouts.duration_seconds` is the binding term. **Fix:** for the
    8.0 band, gate on `avg_rest <= 30 AND sets_per_min >= 0.50` (drop the density requirement;
    rest+cadence already identify a metcon). Re-eval: avg_rest=30≤30, sets/min=0.54 → **est_met=
    8.0.** ✓ matches `_metcon`. **Locked decision function (corrected):**

```
est_met =
    8.0   if avg_rest <= 35  AND sets_per_min >= 0.50    # dense circuit / metcon (02040)
    6.0   if avg_rest <= 75  AND sets_per_min >= 0.40    # vigorous PL/BB (≈02054 high)
    5.0   if avg_rest <= 120                             # vigorous free-weight (02054)
    3.5   otherwise                                      # light/moderate, long rest (02050)
```

`SET_WORK_SECONDS=30`, `REST_DEFAULT=90` are NEW constants → must be added to BOTH the sim (so
the fixture can exercise the derivation) and the SQL/Dart. They are *cross-credit-only* and do
not affect the 14 existing personas (which pass literal MET via `_lift`/`_metcon`). See §C for
whether the derivation enters the parity oracle at all.

---

#### C. Sim + fixture integration plan

**Recommendation: a clean split.** Two different kinds of "net-new" with different parity needs.

1. **The XP formula (compute_session_xp + tier/intensity/cap/vitality chain) — FULL 4-site
     parity, vo2max stays an INPUT.** This is the part that must be byte-identical Python↔fixture↔
     Dart↔SQL. The oracle keeps taking `vo2max` as a given (exactly as today). **No persona
     re-tune.** Add to the fixture:
     - `cardio_session_xp` — end-to-end `(vo2max, age, female, modality, dur, kind, value,
         current_rank, week_used) → (xp, met_minutes, rel_intensity)` rows. Drive it from the 14
         personas' week-1 first-session states + a handful of edge rows (walk-when-fit=~0, metcon,
         over-cap split). Store **raw unrounded** floats.
     - `cardio_components` — component lists mirroring the strength fixture style:
         `intensity_mult` (the 6 INTENSITY_ANCHORS + midpoints), `sustainable_fraction` (the 8
         _SUSTAIN_ANCHORS + midpoints), `demonstrated_vo2` (a few abs_met×dur rows),
         `implied_cardio_tier` (VO₂→tier by sex/age), `modality_mult` (the 10 modalities),
         `cardio_base_xp` (capped_met_min^0.60), `cardio_weekly_cap` (under/over split at 2500).
     - Dart `CardioXpCalculator` replays these @1e-4; SQL integration replays `record_cardio_
         session` live-row @0.01.

2. **The est-VO₂max chain (A1–A5) — APP-ONLY, its own unit tests, does NOT enter the parity
     oracle.** Reasons: (a) it's an *input-derivation*, not part of the scored formula — putting it
     in the oracle would force the personas to also model log history (distance/duration per
     session) they don't carry; (b) A1 is just `demonstrated_vo2` with a measured MET, which is
     ALREADY in the parity set via `cardio_components`; (c) the rolling best-of-window + seed are
     stateful/temporal — fixture parity is the wrong tool, deterministic unit tests are right.
     **However:** A1's core (`acsm_vo2` + `sustainable_fraction` reuse) and the seed's
     `_VO2_NORMS[p25]` lookup SHOULD get a tiny fixture section **`est_vo2max_cases`** (pure
     functions, no state) so Dart's ACSM eq + p25 seed match Python exactly — cheap insurance, no
     persona involvement. The rolling-window/recompute logic is Dart+SQL unit/integration tests
     only.

3. **The cross-credit derivation fn (§B) — APP-ONLY with a parity-checked pure core.** Add the
     `_lift`/`_metcon` helpers' *literal* MET to the personas (unchanged — they pass 3.8/8.0
     directly). Add a NEW pure fn `est_met_from_density(completed_sets, session_seconds,
     avg_rest)` to the sim + a fixture section **`cross_credit_met_bands`** (~8 rows: the two
     worked examples + each band boundary). This pins Dart/SQL's derivation to Python WITHOUT
     making the personas depend on it. The personas validate the *formula*; `cross_credit_met_
     bands` validates the *derivation* feeds the right band.

**`phase29_formula_parity_test.dart` (:44-138) section-count guard updates** — add required
sections + row-count assertions for: `cardio_session_xp`, `cardio_components` (with its
sub-lists), `est_vo2max_cases`, `cross_credit_met_bands`. Each new top-level section needs its
key + expected length pinned, mirroring the existing `set_xp_v2`/`implied_tier`/`tier_diff_mult`
guards, or the new sections ship unguarded (the exact gap the guard exists to prevent).

**Net new sim symbols** (so the generator can import them): `est_met_from_density(...)`,
`best_effort_vo2_from_pace(distance_m, duration_s)` (the A1 wrapper), `nonexercise_seed_vo2(age,
female)` (the A3 p25 lookup), plus the constants `SET_WORK_SECONDS=30`, `REST_DEFAULT=90`,
`AGE_FALLBACK=35`, `VO2_ROLLING_WINDOW_DAYS=42`. The persona panel still runs 14/14 unchanged
(none of these touch `compute_session_xp`).

---

#### D. Open sub-decisions needing a USER ruling

1. **Collect date_of_birth?** (RECOMMEND: yes — add `profiles.date_of_birth`, onboarding date
     picker, fall back to age 35 when NULL.) The locked formula is age-keyed and we store no age
     today; without DOB the entire VO₂-norm/tier chain runs on a hardcoded 35 for everyone, which
     systematically mis-tiers older and younger users (a 55-yr-old's 38 VO₂ is ~75th pct, but
     scored as ~50th at age-35 norms → under-credited). DOB is the minimal honest fix. LGPD: DOB
     is personal data → gate behind the same consent toggle pattern as gender/bodyweight, NULL-OK.
2. **Distance→VO₂ for bike/row/swim in v1, or run/treadmill only?** (RECOMMEND: run/treadmill
     only in v1; bike/row/swim are duration-only for estimation, distance still stored/shown.)
     Each non-running modality needs a distinct, separately-cited equation (Concept2 for row,
     power-based for bike) — out of scope to calibrate honestly in 38c. Defer to 38f.
3. **Rolling window length — 42 days?** (RECOMMEND: 42d = 6wk ≈ 2×τ_down.) Shorter (28d) makes
     the estimate more reactive but drops a fit user faster after a 1-month gap; longer (84d)
     over-credits stale efforts. 42d ties it to the existing Vitality kinetics. Pure tuning knob —
     fine to default and revisit in 38f.
4. **Non-exercise seed percentile — p25 prior?** (RECOMMEND: p25 "below-median untrained" prior.)
     p50 would assume every newcomer is median-fit (over-credits day-zero); p25 makes the first
     real efforts earn the lift. Defensible default; flag if you'd rather a gentler p40.
5. **Cross-credit `SET_WORK_SECONDS`/`REST_DEFAULT` estimates (30s/90s)?** (RECOMMEND: 30/90 as
     stated.) These only matter for the strength→cardio MET band, never for strength XP. 30s/set
     and 90s default rest are standard hypertrophy-block assumptions; the band thresholds were
     tuned around them. Pure tuning, defaultable.
