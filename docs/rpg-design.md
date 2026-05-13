# RepSaga RPG System v1 — Design Spec

**Date:** 2026-04-25
**Status:** Approved (pending writing-plans handoff)
**Phase:** 18 (PLAN.md)
**Author:** orchestrator + product-owner + ui-ux-critic + sports-science research

---

## 1. Goal

Build a permanent gamified progression system on top of RepSaga's workout logging. Every set lifted feeds two parallel state machines: **Rank** (lifetime peak per body part, the saga) and **Vitality** (current conditioning, the weather). The system replaces no logging surface — it overlays one. It must be free for all users; it is the retention spine, not a paywall feature.

The system must:
- be **honest** (cannot be farmed by light-weight grinding)
- be **permanent** (rank never decays — your saga is inviolate)
- be **alive** (Vitality reflects current capability honestly)
- be **empirically defensible** (math grounded in published sports-science)
- be **culturally accessible** (Brazilian gym-goer, Strong/Hevy migration cohort)
- **scale to v2** without schema rework (cardio + HR + kcal land later)

---

## 2. Mental model

> You don't level up your character. You level up your **body** — six body-part Ranks plus a future Cardio track. Each Rank is earned through real training, never given. Your Character Level is what those Ranks add up to. You earn a saga. The saga lasts forever.

Two numbers per body part:
- **Rank** (1-99): permanent peak achievement. Monotonically increases. Identity-permanent.
- **Vitality** (0-100%): current conditioning. Asymmetric — decays slowly with inactivity, rebuilds fast.

One number for the whole character:
- **Character Level** (1-99+): derived from the sum of all six body-part Ranks. Updates automatically whenever a Rank advances.

Plus three identity layers (cosmetic, never gate content):
- **Class** (dynamic, derived from current Rank distribution)
- **Titles** (unlocked at Rank milestones, mostly per-body-part)
- **Rune sigils** (visual representation of Rank + Vitality glow state)

---

## 3. Body parts

### v1 strength tracks (six)

| Body part | Earned from |
|---|---|
| Chest | Pressing movements |
| Back | Pulling movements |
| Legs | Lower-body compounds + isolation |
| Shoulders | Overhead + deltoid work |
| Arms | Bicep/tricep isolation + supporting compounds |
| Core | Direct ab/oblique + compound stabilization |

### v2 conditioning track (one, deferred)

| Body part | Earned from |
|---|---|
| Cardio | HR-zone-weighted effort, kcal estimates, RPE fallback |

**Cardio implementation deferred to Phase 18b.** v1 ships with the full schema in place (the polymorphic `xp_events` table accepts cardio events from day 1) but no UI surface and no cardio earning paths. Character Level uses `ACTIVE_RANKS` = the six strength tracks; when cardio ships, the constant flips and the formula is unchanged.

---

## 4. Per-set XP formula

```
set_xp = base × intensity_mult × strength_mult × novelty_mult × cap_mult

base                  = volume_load^0.65        # sub-linear; 10× volume ≠ 10× XP
intensity_mult        = lookup(rep_range)       # see §4.1
strength_mult         = clamp(weight / peak_load_for_exercise, 0.40, 1.00)
novelty_mult          = exp(-session_volume_for_body_part / 15)
cap_mult              = 0.50 if weekly_volume_for_body_part >= 20 else 1.00
```

XP is then **distributed** across body parts via the attribution map (§5):

```
xp_awarded[body_part] = set_xp × attribution[exercise][body_part]
```

### 4.1 Intensity multiplier table

| Reps in set | Multiplier | Rationale |
|---|---|---|
| 1 | 1.30 | Max-effort 1RM territory |
| 3 | 1.25 | Heavy strength |
| 5 | 1.20 | Strength range |
| 8 | 1.00 | Standard hypertrophy (baseline) |
| 12 | 0.95 | Higher-volume hypertrophy |
| 15 | 0.90 | Endurance-leaning |
| 20+ | 0.80 | Pure endurance / metabolic |

Lookup is by reps-floor: 4 reps → row 3 (1.25). 13 reps → row 12 (0.95).

### 4.2 Strength multiplier — anti-stagnation

`strength_mult = clamp(weight / peak_load, 0.40, 1.00)` per exercise.

`peak_load` = the heaviest weight ever lifted on this exercise at any rep count (lifetime, never decays).

**Behavior:**
- Working at peak weight → 1.0× XP
- Deload at 70% of peak → 0.7× XP
- Light technique sets at 50% → 0.5× XP
- Floor at 40% — recovery sets still count, but token amount

**Why a floor:** zero-XP punishes deloading and rehab. 0.4× is "you're moving, but it's not your earning weight." Empirically validated by simulation: stagnant 5kg-forever lifter caps at max rank ~50 across 5 years vs intermediate's 64. **Stagnation cannot grind past genuine progression.**

### 4.3 Novelty multiplier

`novelty_mult = exp(-session_volume_for_body_part / 15)`

Per-session diminishing returns within a single workout. After ~15 effective sets attributed to a body part, the next set earns `e^-1 ≈ 37%` of base XP. Mirrors recovery science: late-session volume produces dwindling stimulus.

`session_volume_for_body_part` is reset at the start of each session (a session = one workout, regardless of how it's structured).

### 4.4 Weekly cap

Per body part, after **20 effective sets attributed within a 7-day rolling window**, all subsequent set XP for that body part is multiplied by 0.5. Mirrors training-volume-for-hypertrophy research (Schoenfeld, Helms): >20 sets/week is junk volume territory. We don't *forbid* it — we just stop rewarding it linearly.

### 4.5 Volume load definition

`volume_load = max(1.0, weight_kg × reps)`

For bodyweight exercises: weight = bodyweight × difficulty_factor (handled in exercise metadata). E.g., pullup base = bodyweight, dip base = bodyweight, plank base = 1 (time-based; reps interpreted as seconds × 0.1).

The `max(1.0, ...)` floor prevents zero-XP for bodyweight beginners (`pullup_assisted` with full assistance still produces a small base).

---

## 5. Attribution map

The map drives Q1 of the brainstorm. Per-exercise body-part proportions, drafted from training literature (Schoenfeld 2010 *Mechanisms of Hypertrophy*; Helms et al., *The Muscle and Strength Pyramid*; Israetel/Davis Renaissance Periodization frameworks).

### 5.1 Storage strategy

Attribution lives in **the exercises table**, not in code. Each exercise row carries:

```sql
ALTER TABLE exercises
  ADD COLUMN primary_muscle_group TEXT NOT NULL,    -- already exists
  ADD COLUMN secondary_muscle_groups JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN xp_attribution JSONB;                  -- {chest: 0.7, shoulders: 0.2, arms: 0.1}
```

`xp_attribution` is the proportional split. Sum must equal 1.00 ± 0.01 (CHECK constraint). NULL attribution falls back to `{primary_muscle_group: 1.0}`.

### 5.2 Default exercise mappings (literature-grounded draft)

Push:
- `bench_press`: chest 0.70, shoulders 0.20, arms 0.10
- `incline_bench`: chest 0.60, shoulders 0.30, arms 0.10
- `overhead_press`: shoulders 0.60, arms 0.20, core 0.20
- `lateral_raise`: shoulders 0.85, arms 0.10, core 0.05
- `tricep_pushdown`: arms 0.95, shoulders 0.05
- `dip`: chest 0.45, arms 0.40, shoulders 0.15

Pull:
- `barbell_row`: back 0.70, arms 0.20, core 0.10
- `lat_pulldown`: back 0.75, arms 0.20, core 0.05
- `pullup`: back 0.65, arms 0.25, core 0.10
- `barbell_curl`: arms 0.90, back 0.10
- `face_pull`: shoulders 0.55, back 0.40, arms 0.05

Legs:
- `back_squat`: legs 0.80, core 0.10, back 0.10
- `front_squat`: legs 0.75, core 0.15, back 0.10
- `deadlift`: back 0.40, legs 0.40, core 0.10, arms 0.10
- `romanian_deadlift`: legs 0.55, back 0.35, core 0.10
- `leg_press`: legs 0.95, core 0.05
- `lunge`: legs 0.90, core 0.10
- `calf_raise`: legs 1.00

Core:
- `plank`: core 0.90, shoulders 0.05, arms 0.05
- `hanging_leg_raise`: core 0.85, arms 0.10, back 0.05
- `russian_twist`: core 1.00

Shipping disclaimer: this is a v1 draft. Telemetry will surface misattributions; future migrations adjust per-exercise weights based on real training data.

---

## 6. Rank curve

```
xp_to_next(n) = 60 × 1.10^(n-1)
xp_cumulative_for_rank(n) = 60 × (1.10^(n-1) - 1) / 0.10
```

Sample milestones:

| Rank | Cumulative XP | XP from previous |
|---|---|---|
| 2 | 60 | 60 |
| 5 | 278 | 218 |
| 10 | 814 | 536 |
| 20 | 3,069 | 1,391 |
| 30 | 8,917 | 5,848 |
| 50 | 63,431 | 39,345 |
| 70 | 430,171 | 264,691 |
| 90 | 2,897,412 | 1,780,703 |
| 99 | 6,832,761 | 3,935,349 |

**Pacing (validated by 260-week simulation):**
- Rank 1→20: ~8 weeks of consistent training (newbie honeymoon)
- Rank 1→50: ~12 months (intermediate plateau, matches real strength progression)
- Rank 50→99: 3-5+ years (the lifer's flex, à la RuneScape)
- Rank 99 ≈ 6.8M XP (vs RuneScape's 13M — ours is intentionally faster because gym training is slower than RPG grinding)

Cap at Rank 99. Beyond 99 is the same XP table running indefinitely (no level cap on the underlying XP, just the visible cap).

---

## 7. Character Level (derived)

```
character_level = max(1, floor((Σ active_ranks - N_active) / 4) + 1)

active_ranks = chest, back, legs, shoulders, arms, core
N_active = 6

# v2 additive: when cardio ships, append it to active_ranks; N_active becomes 7;
# denominator stays 4. Existing characters get a one-time recompute.
```

**Examples:**
- All ranks at 1 → Lvl 1
- All ranks at 5 → Lvl `(30-6)/4+1 = 7`
- All ranks at 20 → Lvl `(120-6)/4+1 = 29`
- All ranks at 50 → Lvl `(300-6)/4+1 = 74`
- All ranks at 99 → Lvl `(594-6)/4+1 = 148`

The denominator (4) was chosen so that **a single body part's rank advancement produces visible Character Level progress**. With 6 active body parts, you need ~4 collective rank-ups to gain a character level — frequent enough to feel rewarding, infrequent enough to feel earned.

---

## 8. Vitality

### 8.1 Formula

```
weekly_volume[body_part] = sum(volume_load × attribution[bp]) over all sets in the past 7 days

Vitality_EWMA[bp] update each week:
  if weekly_volume[bp] >= prior_EWMA[bp]:
    α = 1 - exp(-1 / 2.0)   ≈ 0.393   # τ_up = 2 weeks (rebuild fast)
  else:
    α = 1 - exp(-1 / 6.0)   ≈ 0.154   # τ_down = 6 weeks (decay slow)
  EWMA[bp] = α × weekly_volume[bp] + (1-α) × prior_EWMA[bp]

Vitality_peak[bp] = max(Vitality_peak[bp], EWMA[bp])    # PERMANENT, never decays

Vitality_pct[bp] = clamp(EWMA[bp] / Vitality_peak[bp], 0, 1)
```

### 8.2 Behavior (validated by simulation)

| Scenario | Vitality trajectory |
|---|---|
| Active training | Stays at 100% |
| 2-week vacation | Dips to 84-95%, recovers fully within 2 weeks |
| 6-week injury layoff | Drops to ~50%, recovers in 3-4 weeks of return |
| 6-month full layoff | Drops to ~3%, climbs back to 79% in 3 weeks of return, 100% in ~11 weeks |
| Untrained body part | 0% (Vitality_peak = 0, EWMA = 0) |

**Asymmetry rationale (Bruusgaard 2010, Seaborne 2018, Psilander 2019):** myonuclear retention and epigenetic muscle memory mean retraining is empirically 2-3× faster than initial acquisition. Our τ_up=2wk / τ_down=6wk encodes this directly into the EWMA.

### 8.3 Permanent peak rationale

Peak never decays. The EWMA's smoothing inherently caps a single specialization block from creating an unreachable ceiling — a one-off 4-week peaking block only partially climbs the EWMA before it ends. **Sustained capacity** (12+ weeks of high volume) is what sets the peak. This addresses the unreachable-ceiling concern empirically without needing a recency-decay constant.

### 8.4 Visual states (rune glow)

Vitality % is **never displayed as a number on the primary character sheet**. It drives the rune sigil's visual state:

| Vitality % | Glow state | Copy / context |
|---|---|---|
| 0% (Vitality_peak = 0) | **Dormant** | "Awaits your first stride" — onboarding, never-trained |
| 1-30% | **Fading** | "Conditioning lost — return to the path" |
| 31-70% | **Active** | "On the path" — default state |
| 71-100% | **Radiant** | "Path mastered" — peak conditioning |

Number is accessible only in the deep-dive stats screen (§13.3).

---

## 9. Class system

Class is **derived** from current Rank distribution. Cosmetic only — no mechanical effects, no XP modifiers, no content gates. Updates whenever ranks change.

### 9.1 Class table

| Class | Trigger | Identity |
|---|---|---|
| **Initiate** | All ranks ≤ 4 | Newcomer to the path |
| **Berserker** | Arms is the dominant rank, gap ≥ 5 over next | Bicep / tricep specialist |
| **Bulwark** | Chest dominant | Pressing specialist |
| **Sentinel** | Back dominant | Pulling specialist |
| **Pathfinder** | Legs dominant | Lower-body specialist |
| **Atlas** | Shoulders dominant | Overhead / yoke specialist |
| **Anchor** | Core dominant | Stability / midline specialist |
| **Wayfarer** | Cardio dominant *(v2 only)* | Endurance specialist |
| **Ascendant** | All ranks within 30% of max, min rank ≥ 5 | Balanced (rare, prestigious) |

### 9.2 Resolution order

```
if max_rank < 5: return "Initiate"
if (max_rank - min_rank) / max_rank <= 0.30 and min_rank >= 5: return "Ascendant"
return CLASS_BY_DOMINANT[argmax(ranks)]
```

Ascendant takes precedence over the dominant-class lookup because balance is rarer and more rewarded.

---

## 10. Titles

Per-body-part ladder of fantasy-themed titles, unlocked at Rank thresholds. Honor only — display on character sheet, post-workout summary, optional shareable card.

### 10.1 Per-body-part ladder (every 5 ranks → 13 titles each, 6 parts → 78 titles)

| Rank | Chest | Back | Legs | Shoulders | Arms | Core |
|---|---|---|---|---|---|---|
| 5 | Initiate of the Forge | Lattice-Touched | Ground-Walker | Burden-Tester | Vein-Stirrer | Spine-Tested |
| 10 | Plate-Bearer | Wing-Marked | Stone-Stepper | Yoke-Apprentice | Iron-Fingered | Core-Forged |
| 15 | Forge-Marked | Rope-Hauler | Pillar-Apprentice | Sky-Reach | Sinew-Drawn | Pillar-Spined |
| 20 | Iron-Chested | Lat-Crowned | Pillar-Walker | Atlas-Touched | Marrow-Cleaver | Iron-Belted |
| 25 | Anvil-Heart | Talon-Backed | Quarry-Strider | Sky-Vaulter | Steel-Sleeved | Stonewall |
| 30 | Forge-Born | Wing-Spread | Mountain-Strider | Yoke-Crowned | Sinew-Sworn | Diamond-Spine |
| 40 | Bulwark-Sworn | Lattice-Lord | Pillar-Sworn | Atlas-Sworn | Iron-Sworn | Anchor-Sworn |
| 50 | Forge-Lord | Wing-Lord | Mountain-Lord | Sky-Lord | Steel-Lord | Stone-Lord |
| 60 | Anvil-King | Lattice-King | Mountain-King | Sky-King | Sinew-King | Marrow-King |
| 70 | Forge-Eternal | Wingmaster | Pillar-Eternal | Sky-Eternal | Iron-Eternal | Stone-Eternal |
| 80 | Heart of Forge | Wing of Storms | Pillar of Storms | Sky-Sundered | Sinew of Storms | Spine of Storms |
| 90 | Forge-Untouched | Sky-Lattice | Mountain-Untouched | Sky-Untouched | Iron-Untouched | Marrow-Untouched |
| 99 | The Anvil | The Lattice | The Pillar | The Atlas | The Sinew | The Spine |

### 10.2 Character-level titles (7)

| Lvl | Title |
|---|---|
| 10 | Wanderer |
| 25 | Path-Trodden |
| 50 | Path-Sworn |
| 75 | Path-Forged |
| 100 | Saga-Scribed |
| 125 | Saga-Bound |
| 148 | Saga-Eternal *(theoretical max)* |

### 10.3 Cross-build titles (5)

Awarded for distinctive Rank distributions:

| Trigger | Title |
|---|---|
| Legs ≥ 40 AND Legs ≥ 2× Arms | "The Pillar-Walker" |
| Chest+Back+Shoulders ≥ 2× (Legs+Core), all upper ≥ 30 | "The Broad-Shouldered" |
| All 6 body parts within 30% of max at Rank 30+ | "The Even-Handed" |
| Chest ≥ 60 AND Back ≥ 60 AND Legs ≥ 60, low Cardio (when v2 ships) | "The Iron-Bound" |
| All ranks ≥ 60 (true generalist endgame) | "The Saga-Forged" |

**Total: 78 + 7 + 5 = 90 titles in v1.**

### 10.4 Title display

- One active title at a time (user choice)
- Default = highest-tier earned title
- Shown on character sheet header, post-workout celebration, post-rank-up overlay
- Title library accessible from character sheet → "Titles" tab — shows earned + locked + unlock criteria

---

## 11. Schema

### 11.1 New tables

```sql
-- Polymorphic XP event log. v1 records 'set' events from workouts.
-- v2 will record 'cardio_session', 'hr_zone', 'kcal_burn' without schema rework.
CREATE TABLE xp_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,           -- 'set' | 'cardio_session' | 'hr_zone' | 'kcal'
  source_id UUID,                     -- FK to workout_set / cardio_session etc.
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  payload JSONB NOT NULL,             -- event-type-specific shape
  total_xp NUMERIC(12, 2) NOT NULL,   -- post-multiplier total
  attribution JSONB NOT NULL,         -- {chest: xp_to_chest, ...}
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX xp_events_user_occurred_idx ON xp_events(user_id, occurred_at DESC);
CREATE INDEX xp_events_user_type_idx ON xp_events(user_id, event_type);

-- Materialized per-body-part state. Updated incrementally via trigger or
-- Edge Function on xp_events insert.
CREATE TABLE body_part_progress (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  body_part TEXT NOT NULL,            -- 'chest' | 'back' | ... | 'cardio'
  total_xp NUMERIC(14, 2) NOT NULL DEFAULT 0,
  rank INT NOT NULL DEFAULT 1,        -- derived but cached for fast reads
  vitality_ewma NUMERIC(12, 2) NOT NULL DEFAULT 0,
  vitality_peak NUMERIC(12, 2) NOT NULL DEFAULT 0,
  last_event_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, body_part)
);

-- Per-exercise lifetime peak load (drives strength_mult).
CREATE TABLE exercise_peak_loads (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  exercise_id UUID NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
  peak_weight NUMERIC(8, 2) NOT NULL,
  peak_reps INT NOT NULL,             -- reps at which peak was set (for context)
  peak_date TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, exercise_id)
);

-- Earned titles log (allows multiple unlocks, history).
CREATE TABLE earned_titles (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title_id TEXT NOT NULL,             -- 'forge_lord' | 'pillar_walker' | ...
  earned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  is_active BOOLEAN NOT NULL DEFAULT FALSE,    -- user's currently-displayed title
  PRIMARY KEY (user_id, title_id)
);

CREATE UNIQUE INDEX earned_titles_one_active
  ON earned_titles(user_id) WHERE is_active = TRUE;
```

### 11.2 Modifications to existing tables

```sql
-- Attribution map per exercise (default exercises and user-created)
ALTER TABLE exercises
  ADD COLUMN secondary_muscle_groups JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN xp_attribution JSONB;

-- PostgreSQL forbids subqueries in CHECK constraints, so the sum-to-one
-- invariant is enforced via an IMMUTABLE helper function. (Original spec
-- attempted an inline SELECT ... FROM jsonb_each_text(...), which PG rejects
-- with: "cannot use subquery in check constraint".)
CREATE OR REPLACE FUNCTION xp_attribution_sum(attr jsonb)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(sum(value::numeric), 0)
  FROM jsonb_each_text(attr)
$$;

ALTER TABLE exercises
  ADD CONSTRAINT xp_attribution_sums_to_one
    CHECK (
      xp_attribution IS NULL
      OR abs(xp_attribution_sum(xp_attribution) - 1.0) <= 0.01
    );

-- A workout_set INSERT must trigger an xp_events row. Implementation is the
-- responsibility of the workout-completion path (Edge Function or Postgres
-- trigger), see §12.
```

### 11.3 Derived views

```sql
-- character_level computed from body_part_progress
CREATE VIEW character_state AS
SELECT
  user_id,
  GREATEST(1, FLOOR((SUM(rank) - COUNT(*)) / 4)::INT + 1) AS character_level,
  MAX(rank) AS max_rank,
  MIN(rank) AS min_rank,
  SUM(total_xp) AS lifetime_xp
FROM body_part_progress
WHERE body_part IN ('chest', 'back', 'legs', 'shoulders', 'arms', 'core')   -- v1
GROUP BY user_id;
```

### 11.4 Migration strategy

- Single migration file: `supabase/migrations/00040_rpg_system_v1.sql`
- Backfill `body_part_progress` and `exercise_peak_loads` from existing `workout_sets` history in the same migration (synchronous, run in transaction)
- For each existing user: replay all historical sets in chronological order, computing XP and Vitality using the v1 formulas. Backfilled state is exactly what the user would have if the system had always existed.
- Migration must be idempotent (re-runnable) and safe under concurrent writes
- Rollback script: `scripts/emergency_rollback_phase18.sql` — drops new tables, removes new columns from `exercises`, restores schema to pre-Phase-18

---

## 12. Computation flow

### 12.1 On set completion

```
INSERT workout_set → trigger handler (Postgres function or Edge Function):

1. Look up exercise + xp_attribution
2. Look up exercise_peak_loads[user, exercise].peak_weight
3. Compute set_xp = volume_load^0.65 × intensity_mult × strength_mult × novelty_mult × cap_mult
   - novelty_mult uses sets-this-session via session_id grouping
   - cap_mult uses 7-day rolling sum from xp_events
4. INSERT xp_events row with total_xp + attribution payload
5. UPDATE body_part_progress per attributed body part:
   - total_xp += attribution[bp] × set_xp
   - rank = rank_for_xp(total_xp)
6. UPDATE exercise_peak_loads if weight > current peak
7. RETURN deltas to client (rank-up, level-up, title unlock) for UI overlay
```

### 12.2 Vitality update (separate cadence)

Vitality EWMA updates **once per day per user**, not per-set. Background job (Supabase scheduled function or `pg_cron`):

```
For each user with activity in past 7 days:
  For each body_part:
    weekly_volume = SUM(attribution[bp] × volume_load) FROM xp_events WHERE occurred_at > now()-7d
    update_vitality(weekly_volume) per §8.1
```

Why daily not per-set: EWMA is a smoothing operation; per-set updates would produce sawtooth noise. Daily is the right granularity for a multi-week metric.

### 12.3 Performance budget

- Set-completion XP path: must be <50ms p95 (it's in the workout-logging hot path)
- Vitality nightly job: must complete within 10min for 100k users (3.3M events/night at 50 events/user)

Caching:
- `body_part_progress.rank` cached so character-sheet reads don't recompute from XP cumulative
- Pre-computed `xp_for_rank` lookup table (99 entries, immutable) shipped client-side and server-side

---

## 13. UX / UI surface

### 13.1 Character sheet (new screen)

Accessible from the bottom nav as a new "Saga" tab (replacing or extending the existing "Profile"). Layout:

```
┌────────────────────────────────────────┐
│  [active title]   Lvl 47 · Pathfinder │
│  [character avatar with rune halo]     │
│                                        │
│  ────── Body-Part Ranks ──────         │
│  Chest       ████████░░  Rank 38       │
│  Back        █████████░  Rank 42       │
│  Legs        ██████████  Rank 51 ★     │
│  Shoulders   ███████░░░  Rank 35       │
│  Arms        ████████░░  Rank 39       │
│  Core        ██████░░░░  Rank 28       │
│                                        │
│  Cardio          dormant — coming v2   │
│                                        │
│  [Stats deep-dive] [Titles] [History]  │
└────────────────────────────────────────┘
```

**Rune halo** around the avatar reflects average Vitality state. A radiantly-glowing rune = peak conditioning; a dim rune = the user has stepped off the path.

**Per-body-part progress bar** is the rank progress to next rank (XP-based). Width = `xp_in_current_rank / xp_for_next_rank`.

**No Vitality % shown.** The bar color/glow encodes Vitality state via §8.4 visual states.

### 13.2 Mid-workout rank-up overlay

Already specced in Phase 17a. With v1 RPG, the overlay fires on:
- Rank-up (per body part)
- Character Level up (derived from rank changes)
- Title unlock

Multiple events in one set are queued and shown sequentially, each ~1.1s. Title unlocks open a half-sheet after the workout ends (per Phase 17a UX revision).

### 13.3 Stats deep-dive screen

Accessible via character sheet → "Stats". For the data-curious user. Layout:

```
┌────────────────────────────────────────┐
│  Stats                                 │
│                                        │
│  ─── Vitality (live state) ───         │
│  Chest       Active · 84%              │
│  Back        Radiant · 96%             │
│  Legs        Active · 67%              │
│  ...                                   │
│                                        │
│  ─── 90-day Vitality trend ───         │
│  [line chart, all 6 body parts]        │
│                                        │
│  ─── Volume + Peak (per body part) ─── │
│  Chest    EWMA 8,420   Peak 9,850      │
│  Back     EWMA 7,100   Peak 7,100      │
│  ...                                   │
│                                        │
│  ─── Peak Loads (per exercise) ───     │
│  Bench Press     85kg × 5 (2026-03-12) │
│  Deadlift       140kg × 3 (2026-04-02) │
│  ...                                   │
└────────────────────────────────────────┘
```

This is where the percentage lives. Numbers are cold and informational here — the warm/identity surface is the character sheet.

### 13.4 Onboarding gate

A first-day user has no Rank history, no Vitality_peak. The character sheet shows:

```
┌────────────────────────────────────────┐
│  [active title]   Lvl 1 · Initiate    │
│  [avatar with all-dim runes]          │
│                                        │
│  Chest       dormant — first set awakens this path
│  Back        dormant — first set awakens this path
│  Legs        dormant — first set awakens this path
│  ...                                   │
└────────────────────────────────────────┘
```

After the first set: that body part's rune awakens with a light celebration. "Chest awakens" / "The Path of the Chest opens." Single small-screen overlay, 800ms.

### 13.5 No global leaderboards, no friend comparison in v1

Leaderboards are body-dysmorphia bait. Friend comparison adds social pressure without value at v1 scope. Both deferred to v2 with explicit opt-in onboarding.

---

## 14. Integration with Phase 17a

Phase 17a (already specced and partially implemented) defines the **mid-workout rank-up overlay**, set-haptic feedback, and post-workout summary. v1 RPG provides the **data** that drives those UX surfaces.

What Phase 17a built:
- Mid-set XP delta animation
- Rank-up overlay choreography (1.1s, dismissable)
- Title unlock half-sheet
- Set-completion lightImpact() haptic
- Mid-workout rank banner (3s, no buttons)
- Empty-state copy

What Phase 18 (this spec) adds underneath:
- The actual XP, Rank, Character Level computation
- Vitality tracking
- Class derivation
- Title catalog + unlock logic
- Schema + migration + backfill
- Character sheet screen
- Stats deep-dive screen

**Phase 17a's rank-up overlay was provisionally wired against placeholder XP math.** Phase 18 swaps the placeholder for the real formula. No further UX changes required — the overlay is data-source-agnostic.

---

## 15. Premium gating

**RPG system is free for all users.** Locked permanently — never gate the saga.

Rationale (from product-owner research):
- The RPG IS the product now. Gating kills the retention story.
- Subscription should gate **advanced analytics, export, coaching** — not the core loop.
- Free RPG drives the free→paid funnel via differentiation against Strong/Hevy (no RPG) and conversion to premium analytics.

This is documented in PLAN.md Phase 16 as a hard constraint on what subscription can and cannot gate.

---

## 16. v2 roadmap (explicitly NOT in v1)

Held for Phase 18b+:

### 16.1 Cardio track
- HR-zone XP weighting (zone 2 = 1×, zone 4 = 2.5×)
- Kcal-burn XP fallback (no wearable)
- RPE-based fallback (no HR, no GPS)
- Wearable integrations: Apple Health, Google Fit, Garmin Connect

### 16.2 Power / Endurance sub-tracks per body part
Each body-part Rank splits into Power (low-rep, high-load) + Endurance (high-rep, time-under-tension) sub-ranks. Profile reads "Legs 40 — 32 Power / 28 Endurance." Doubles attribution complexity — needs RPE or %1RM input, not feasible without an estimated 1RM model.

### 16.3 Synergy multipliers
Training Chest+Back+Shoulders consistently → "Upper-Body Mastery" synergy → 10% XP bonus on those three. D2 skill-synergy parallel.

### 16.4 Rival comparison
Friend-only, opt-in, never global. Friend's character sheet visible for motivation, not their raw weights.

### 16.5 PR mini-events
Hitting a 1RM PR triggers an enhanced overlay — level-up scale animation, shareable rune card, entry in personal "legend log."

---

## 17. Open questions

None at design-spec time. Implementation-time discoveries (perf, edge cases) will be triaged in the implementation plan.

---

## 18. Acceptance criteria

The implementation is done when:

1. Schema migrated; backfill computes correct Ranks for all existing users from historical workout_sets
2. Per-set XP computed live in workout-logging path with <50ms p95 overhead
3. Character sheet screen renders for all users (including zero-history users → all dormant)
4. Stats deep-dive screen renders accurate live numbers for active users
5. Mid-workout rank-up overlay fires correctly on real Phase 18 XP math (replacing Phase 17a placeholder math)
6. Vitality updates daily via scheduled job; trajectory matches the simulation harness within 5% tolerance
7. Title unlocks fire correctly on Rank threshold crossings during workout
8. Class label updates immediately on Rank changes
9. Strength_mult correctly applied — confirmed by integration test where the same volume at varying %peak produces predictably different XP
10. Permanent peak invariant: no code path can decrease `body_part_progress.rank` or `vitality_peak`
11. CI green: format, analyze, unit tests, widget tests, full E2E suite (with new RPG flows)
12. Migration applied to hosted Supabase; verified end-to-end with a manually replayed user history

---

## 19. References

**Sports science:**
- Mujika & Padilla 2000a/b — *Detraining: Loss of training-induced physiological and performance adaptations* (Sports Med)
- Schoenfeld 2010 — *The Mechanisms of Muscle Hypertrophy* (J Strength Cond Res)
- Helms et al. — *The Muscle and Strength Pyramid* (training framework)
- Bruusgaard et al. 2010, 2012 — myonuclear retention / muscle memory
- Seaborne et al. 2018 — epigenetic memory of resistance training
- Psilander et al. 2019 — retraining hypertrophy rate
- Banister 1991; Busso 2003 — fitness-fatigue / CTL model
- Bosquet et al. 2013 — taper / detraining meta-analysis

**Game design:**
- RuneScape per-skill 1-99 progression
- Diablo II permanent character progression
- Zwift dual-track (XP levels + Training Score)
- Garmin Body Battery vs VO2 Max (peak vs current)

**Brainstorm artifacts:**
- `tasks/rpg-system-brainstorm.md` — initial concept and Q1-Q5 decisions
- `tasks/rpg-xp-simulation.py` — pacing simulation harness, 5-year trajectories validated

---

*End of design spec. Next: handoff to writing-plans skill to convert into Phase 18 implementation plan in PLAN.md.*
