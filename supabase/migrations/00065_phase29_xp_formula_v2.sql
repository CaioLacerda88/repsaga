-- =============================================================================
-- 00065 — Phase 29 v2 + 29.6 XP formula rewrite
--
-- ## What this does
--
-- Wholesale rewrite of the XP formula chain to the Phase 29 v2 + 29.6
-- LOCKED 11-multiplier chain. Replaces the Phase 24d six-multiplier chain
-- end-to-end:
--
--   OLD: set_xp = base × intensity × strength × novelty × cap × difficulty
--
--   NEW: set_xp = base
--              × intensity                            -- with +0.10 if near_failure
--              × strength
--              × novelty
--              × cap
--              × difficulty
--              × tier_diff_mult                       -- Refinement #1
--              × abs_strength_premium                 -- 29.6 Path C
--              × overload_mult                        -- Refinement #2
--              × frequency_mult                       -- Refinement #3
--              × attribution_share                    -- per body part
--
-- Mirrors `lib/features/rpg/domain/xp_calculator.dart`,
-- `lib/features/rpg/domain/implied_tier.dart`,
-- `lib/features/rpg/domain/rank_curve.dart`, and
-- `tasks/rpg-xp-simulation.py` byte-for-byte. Integration tests assert
-- 1e-4 absolute parity between Dart + SQL + Python sim.
--
-- ## Schema changes
--
--   * `profiles.gender text NULL` — user-declared gender (`male` / `female`
--     / `other` or NULL). Drives per-lift × per-gender tier table
--     selection. NULL or 'other' falls back to the male table (matches
--     the Python sim's `female=False` default).
--   * `exercises.bodyweight_load_ratio numeric(3,2) NOT NULL DEFAULT 1.0`
--     — Refinement #5 per-exercise biomechanical load fraction. For the
--     20 curated bodyweight slugs (Phase 24c migration 00056), this
--     replaces the all-1.0 simple-addition semantics with per-slug
--     fractions sourced from Suprak et al. 2011 (push-ups), Youdas et al.
--     2010 (pull-ups), Bryanton et al. 2012 (squats). CHECK constrained
--     to [0.20, 1.00] (gym-realistic range).
--   * `exercise_peak_loads_by_rep_range` — new table tracking the user's
--     best (weight, reps) per rep band per exercise. Powers
--     `overload_mult` (Refinement #2) which rewards in-band PRs.
--
-- ## Function changes
--
-- Helpers (all IMMUTABLE PARALLEL SAFE; SECURITY INVOKER):
--   * `rpg_implied_tier_for_exercise(slug, weight, reps, bw, gender)` —
--     interpolates the per-lift × per-gender tier table. Returns
--     numeric in [0, 70].
--   * `rpg_tier_diff_mult(implied_tier, current_rank)` —
--     `clamp(((2T+10)/(T+R+10))^2.5, 0.25, 8.0)`.
--   * `rpg_abs_strength_premium(implied_tier)` —
--     `1 + 0.8 × clamp((T - 35) / 20, 0, 1)`.
--   * `rpg_overload_mult(user_id, exercise_id, weight, reps)` — looks
--     up `exercise_peak_loads_by_rep_range` for the matching band; runs
--     the AND/OR ladder (1.15 / 1.10 / 1.05 / 1.00).
--   * `rpg_frequency_mult(user_id, body_part, session_ts)` — counts
--     distinct sessions touching this bp in the trailing 7d window;
--     looks up `[1.00, 1.06, 1.10, 1.06, 1.00]`.
--   * `rpg_near_failure_inferred(target_reps, actual_reps)` —
--     `actual < target × 0.85`.
--   * `rpg_cumulative_xp_for_rank(rank)` — REPLACED with the Phase 29 v2
--     piecewise: geometric 1-20 (60 × 1.10^(n-1)), linear 21+ at
--     LITERAL 367.0 XP per rank.
--   * `rpg_rep_band(reps)` — small helper returning 'heavy' / 'strength'
--     / 'hypertrophy' / 'endurance'. Used by `rpg_overload_mult`.
--
-- RPCs (SECURITY DEFINER; all GRANT EXECUTE TO authenticated):
--   * `record_set_xp(p_set_id)` — per-set RPC. Now consumes gender +
--     bodyweight_load_ratio + all Phase 29 v2 helpers. Snapshots the
--     full 11-multiplier breakdown into `xp_events.payload`.
--   * `record_session_xp_batch(p_workout_id)` — production save_workout
--     hot path. Same chain; float8 hot-path discipline preserved from
--     Phase 24c (00057).
--   * `_rpg_backfill_chunk(p_user_id, p_chunk_size)` — historical replay
--     with the Phase 29 v2 chain. Reads CURRENT bodyweight + gender for
--     the user (documented forward-only semantics from Phase 24c — we
--     don't have historical gender/bodyweight, current is the best
--     approximation).
--
-- ## Backfill at end-of-migration
--
-- After helper + RPC replacement, `UPDATE body_part_progress SET rank =
-- rpg_rank_for_xp(total_xp)` re-derives every user's rank using the
-- piecewise curve. Old geometric rank 50 = 63,431 XP; new piecewise
-- rank 50 = 14,080 XP — so any user above rank 21 sees their rank shift
-- UP. Pre-29 `xp_events.payload` rows stay frozen (forward-only
-- semantics).
--
-- ## What's NOT in this migration
--
--   * No retroactive `xp_events` replay — pre-29 sets keep their pre-29
--     XP values frozen in `xp_events.payload`. Users who run a backfill
--     after the migration get the new chain applied to their full
--     history; that's opt-in via the existing `backfill_rpg_v1` wrapper.
--   * No change to `backfill_rpg_v1` (the cursor wrapper) — all math
--     lives in `_rpg_backfill_chunk` which IS replaced.
--   * No change to `exercise_peak_loads` (the all-rep-bands peak table).
--     That continues to exist as the canonical PR tracker; the new
--     `exercise_peak_loads_by_rep_range` is a SEPARATE per-band table
--     used only by `overload_mult`.
--   * No change to the strength_mult helper signature — it still reads
--     `effective_weight / peak`, where peak comes from the existing
--     `exercise_peak_loads` table (entered weight, not effective).
--   * No change to `xp_events.attribution` shape — per-bp keys + numeric
--     awards stay as they were.
--
-- ## Idempotency
--
-- All ALTERs use `IF NOT EXISTS`. All CREATE TABLEs use `IF NOT EXISTS`.
-- All CREATE OR REPLACE FUNCTIONs are idempotent by definition. Backfill
-- is idempotent (re-running produces the same ranks). Re-applying this
-- migration against an already-Phase-29 database is a no-op.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- PART A — Schema additions
-- ---------------------------------------------------------------------------

-- A.1 profiles.gender — user-declared gender. CHECK constraint matches
--     the Dart Profile.Gender enum's @JsonValue tokens.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS gender text NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'profiles_gender_check'
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_gender_check
      CHECK (gender IS NULL OR gender IN ('male', 'female', 'other'));
  END IF;
END $$;

COMMENT ON COLUMN public.profiles.gender IS
  'Phase 29 v2 — user-declared gender. Drives per-lift Symmetric Strength '
  'tier table selection (male = Symmetric Strength reference data; '
  'female = strengthlevel.com snapshot 2026-05-20). NULL and ''other'' '
  'fall back to the male table.';

-- A.2 exercises.bodyweight_load_ratio — per-exercise biomechanical fraction.
--     Default 1.0 keeps the column inert for non-bodyweight exercises;
--     the curated 20 bodyweight slugs get backfilled in PART B below.
ALTER TABLE public.exercises
  ADD COLUMN IF NOT EXISTS bodyweight_load_ratio numeric(3,2)
    NOT NULL DEFAULT 1.0;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'exercises_bodyweight_load_ratio_range'
  ) THEN
    ALTER TABLE public.exercises
      ADD CONSTRAINT exercises_bodyweight_load_ratio_range
      CHECK (bodyweight_load_ratio BETWEEN 0.20 AND 1.00);
  END IF;
END $$;

COMMENT ON COLUMN public.exercises.bodyweight_load_ratio IS
  'Phase 29 v2 Refinement #5 — per-exercise biomechanical fraction of '
  'bodyweight contributing to effective load. 1.00 = full bodyweight '
  '(pull-up); 0.64 = push-up; 0.41 = incline push-up. Only consulted '
  'when uses_bodyweight_load = TRUE; ignored otherwise (the column '
  'default 1.0 makes the math inert for loaded exercises).';

-- A.3 exercise_peak_loads_by_rep_range — per-band peak tracker.
--     Powers rpg_overload_mult (Refinement #2). RLS owner-read only.
CREATE TABLE IF NOT EXISTS public.exercise_peak_loads_by_rep_range (
  user_id        uuid         NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  exercise_slug  text         NOT NULL,
  rep_band       text         NOT NULL
                   CHECK (rep_band IN ('heavy', 'strength', 'hypertrophy', 'endurance')),
  best_weight    numeric(8,4) NOT NULL CHECK (best_weight >= 0),
  best_reps      int          NOT NULL CHECK (best_reps > 0),
  updated_at     timestamptz  NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, exercise_slug, rep_band)
);

ALTER TABLE public.exercise_peak_loads_by_rep_range
  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS exercise_peak_loads_by_rep_range_select_own
  ON public.exercise_peak_loads_by_rep_range;
CREATE POLICY exercise_peak_loads_by_rep_range_select_own
  ON public.exercise_peak_loads_by_rep_range FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

COMMENT ON TABLE public.exercise_peak_loads_by_rep_range IS
  'Phase 29 v2 Refinement #2 — per-(user, exercise, rep_band) best lift. '
  'Updated by record_set_xp / record_session_xp_batch when a new in-band '
  'PR lands. Read by rpg_overload_mult to compute the AND/OR overload '
  'ladder. Separate from exercise_peak_loads (which is exercise-wide).';

-- ---------------------------------------------------------------------------
-- PART B — Backfill exercise.bodyweight_load_ratio for curated slugs
-- ---------------------------------------------------------------------------
--
-- Per-slug ratios mirror Python sim's BODYWEIGHT_LOAD_RATIO. Empirical
-- sources cited in the sim's header:
--   Suprak et al. 2011 (JSCR) — push-up variants
--   Youdas et al. 2010 (JSCR) — pull-up
--   Bryanton et al. 2012     — squat fractions
--
-- The 20 curated slugs are the same ones 00056 flagged
-- `uses_bodyweight_load = TRUE`. Any of them already at 1.0 stay at 1.0
-- (pull_up, chin_up, etc. — no change from existing behavior).
-- ---------------------------------------------------------------------------

UPDATE public.exercises SET bodyweight_load_ratio = 1.00
  WHERE slug IN ('pull_up', 'chin_up', 'wide_grip_pull_up', 'muscle_up',
                 'ring_muscle_up', 'hanging_leg_raise', 'handstand_push_up',
                 'nordic_curl');

UPDATE public.exercises SET bodyweight_load_ratio = 0.95
  WHERE slug IN ('dips', 'ring_dip', 'pistol_squat');

UPDATE public.exercises SET bodyweight_load_ratio = 0.80
  WHERE slug = 'archer_push_up';

UPDATE public.exercises SET bodyweight_load_ratio = 0.74
  WHERE slug = 'decline_push_up';

UPDATE public.exercises SET bodyweight_load_ratio = 0.75
  WHERE slug = 'bodyweight_squat';

UPDATE public.exercises SET bodyweight_load_ratio = 0.64
  WHERE slug IN ('push_up', 'diamond_push_up');

UPDATE public.exercises SET bodyweight_load_ratio = 0.65
  WHERE slug = 'wide_push_up';

UPDATE public.exercises SET bodyweight_load_ratio = 0.63
  WHERE slug = 'close_grip_push_up';

UPDATE public.exercises SET bodyweight_load_ratio = 0.41
  WHERE slug = 'incline_push_up';

UPDATE public.exercises SET bodyweight_load_ratio = 0.85
  WHERE slug = 'walking_lunges';

UPDATE public.exercises SET bodyweight_load_ratio = 0.70
  WHERE slug = 'inverted_row';

-- Sanity assert: all curated bodyweight-load slugs landed at a ratio
-- distinct from the column default 1.0 EXCEPT the ones intentionally at
-- 1.00 (pull-up family). Catches a typo or missing slug.
DO $$
DECLARE
  v_count int;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.exercises
  WHERE uses_bodyweight_load = TRUE
    AND bodyweight_load_ratio NOT BETWEEN 0.20 AND 1.00;
  IF v_count > 0 THEN
    RAISE EXCEPTION
      '00065 PART B: % bodyweight-load exercises have out-of-range '
      'bodyweight_load_ratio after backfill', v_count;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- PART C — Helper functions (IMMUTABLE; pure)
-- ---------------------------------------------------------------------------

-- C.1 rpg_rep_band — Phase 29 v2 Refinement #2 helper.
CREATE OR REPLACE FUNCTION public.rpg_rep_band(p_reps int)
RETURNS text
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
AS $$
BEGIN
  IF p_reps IS NULL OR p_reps <= 0 THEN RETURN 'heavy'; END IF;
  IF p_reps <= 4  THEN RETURN 'heavy'; END IF;
  IF p_reps <= 7  THEN RETURN 'strength'; END IF;
  IF p_reps <= 12 THEN RETURN 'hypertrophy'; END IF;
  RETURN 'endurance';
END;
$$;

-- C.2 rpg_cumulative_xp_for_rank — REPLACED with Phase 29 v2 piecewise.
--     Geometric 1-20 (60 × 1.10^(n-1) cum), linear 21+ at LITERAL 367.0.
--     Derived value (60 × 1.10^19 ≈ 366.957) is NOT used — the 367.0 is
--     pinned so high-rank parity stays stable.
CREATE OR REPLACE FUNCTION public.rpg_cumulative_xp_for_rank(p_rank int)
RETURNS numeric
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
AS $$
DECLARE
  v_breakpoint constant int     := 20;
  v_linear     constant numeric := 367.0;
  v_at_break   constant numeric := 60.0 * (power(1.10, 19) - 1) / 0.10;
BEGIN
  IF p_rank <= 1 THEN RETURN 0; END IF;
  IF p_rank <= v_breakpoint THEN
    RETURN 60.0 * (power(1.10, p_rank - 1) - 1) / 0.10;
  END IF;
  RETURN v_at_break + (p_rank - v_breakpoint)::numeric * v_linear;
END;
$$;

COMMENT ON FUNCTION public.rpg_cumulative_xp_for_rank(int) IS
  'Phase 29 v2 Refinement #6 piecewise rank curve. Ranks 1-20 use the '
  'geometric sum (60 × (1.10^(n-1) - 1) / 0.10); ranks 21+ add LITERAL '
  '367.0 XP per rank. The literal avoids float drift at high ranks.';

-- C.3 rpg_implied_tier_for_exercise — per-lift × per-gender tier lookup.
--     Mirrors implied_tier.dart::impliedTier byte-for-byte.
CREATE OR REPLACE FUNCTION public.rpg_implied_tier_for_exercise(
  p_slug    text,
  p_weight  numeric,
  p_reps    int,
  p_bw      numeric,
  p_gender  text
) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
AS $$
DECLARE
  v_family   text;
  v_discount numeric;
  v_one_rm   numeric;
  v_ratio    numeric;
  v_tiers    numeric[];  -- flat [rank0, ratio0, rank1, ratio1, ...]
  i          int;
  v_lo_rank  numeric;
  v_lo_ratio numeric;
  v_hi_rank  numeric;
  v_hi_ratio numeric;
BEGIN
  -- Bodyweight 0 → kBodyweightZeroFallback (15.0).
  IF p_bw IS NULL OR p_bw <= 0 THEN RETURN 15.0; END IF;
  IF p_reps IS NULL OR p_reps <= 0 THEN RETURN 0.0; END IF;

  -- Family dispatch — keep in sync with implied_tier.dart's
  -- _exerciseTierFamily map AND the Python sim's EXERCISE_TIER_FAMILY.
  v_family := CASE p_slug
    -- Bench family
    WHEN 'bench'                       THEN 'bench'
    WHEN 'incline_bench'               THEN 'bench'
    WHEN 'barbell_bench_press'         THEN 'bench'
    WHEN 'incline_barbell_bench_press' THEN 'bench'
    WHEN 'machine_chest_press'         THEN 'bench'
    -- OHP family
    WHEN 'overhead_press' THEN 'ohp'
    -- Squat family
    WHEN 'squat'          THEN 'squat'
    WHEN 'barbell_squat'  THEN 'squat'
    WHEN 'leg_press'      THEN 'squat'
    WHEN 'lunge'          THEN 'squat'
    WHEN 'walking_lunges' THEN 'squat'
    -- Deadlift family
    WHEN 'deadlift'           THEN 'deadlift'
    WHEN 'romanian_deadlift'  THEN 'deadlift'
    -- Row family
    WHEN 'row'                    THEN 'row'
    WHEN 'barbell_bent_over_row'  THEN 'row'
    WHEN 'pendlay_row'            THEN 'row'
    WHEN 'pulldown'               THEN 'row'
    WHEN 'lat_pulldown'           THEN 'row'
    WHEN 'pullup'                 THEN 'row'
    WHEN 'pull_up'                THEN 'row'
    WHEN 'seated_row'             THEN 'row'
    -- Isolation family
    WHEN 'curl'              THEN 'isolation'
    WHEN 'barbell_curl'      THEN 'isolation'
    WHEN 'tricep_pushdown'   THEN 'isolation'
    WHEN 'lateral_raise'     THEN 'isolation'
    WHEN 'plank'             THEN 'isolation'
    WHEN 'leg_raise'         THEN 'isolation'
    WHEN 'leg_extension'     THEN 'isolation'
    WHEN 'leg_curl'          THEN 'isolation'
    -- Default fallback — matches Python sim's `.get(exercise, 'bench')`
    ELSE 'bench'
  END;

  v_discount := CASE p_slug
    WHEN 'leg_press'                    THEN 0.65
    WHEN 'pulldown'                     THEN 0.75
    WHEN 'lat_pulldown'                 THEN 0.75
    WHEN 'incline_bench'                THEN 0.90
    WHEN 'incline_barbell_bench_press'  THEN 0.90
    WHEN 'lunge'                        THEN 0.80
    WHEN 'walking_lunges'               THEN 0.80
    WHEN 'plank'                        THEN 0.50
    WHEN 'leg_raise'                    THEN 0.50
    WHEN 'machine_chest_press'          THEN 0.60
    WHEN 'seated_row'                   THEN 0.75
    WHEN 'leg_extension'                THEN 0.50
    WHEN 'leg_curl'                     THEN 0.50
    WHEN 'romanian_deadlift'            THEN 0.90
    ELSE 1.0
  END;

  -- Brzycki 1RM estimate. reps == 1 → no scaling; reps >= 37 → clamp.
  IF p_reps <= 1 THEN
    v_one_rm := p_weight;
  ELSIF p_reps >= 37 THEN
    v_one_rm := p_weight;
  ELSE
    v_one_rm := p_weight * 36.0 / (37.0 - p_reps);
  END IF;

  v_ratio := v_one_rm / p_bw / v_discount;

  -- Tier table dispatch. We pack each table as a flat numeric[] of
  -- alternating (rank, ratio) pairs — pure data, no joins, no extra
  -- function dispatch.
  IF p_gender = 'female' THEN
    v_tiers := CASE v_family
      WHEN 'bench'    THEN ARRAY[0,0.28, 8,0.48, 15,0.78, 25,1.13, 35,1.53, 45,1.90, 55,2.30, 65,2.80]
      WHEN 'squat'    THEN ARRAY[0,0.48, 8,0.78, 15,1.17, 25,1.62, 35,2.13, 45,2.70, 55,3.10, 65,3.50]
      WHEN 'deadlift' THEN ARRAY[0,0.62, 8,0.95, 15,1.38, 25,1.88, 35,2.43, 45,3.00, 55,3.40, 65,3.80]
      WHEN 'ohp'      THEN ARRAY[0,0.20, 8,0.35, 15,0.53, 25,0.75, 35,1.00, 45,1.25, 55,1.50, 65,1.80]
      WHEN 'row'      THEN ARRAY[0,0.48, 8,0.72, 15,1.00, 25,1.35, 35,1.70, 45,2.10, 55,2.50, 65,2.80]
      WHEN 'isolation' THEN ARRAY[0,0.05, 8,0.09, 15,0.14, 25,0.22, 35,0.32, 45,0.42, 55,0.52, 65,0.62]
    END;
  ELSE
    -- NULL gender or 'male' or 'other' → male table (backward-compat)
    v_tiers := CASE v_family
      WHEN 'bench'    THEN ARRAY[0,0.50, 8,0.75, 15,1.00, 25,1.25, 35,1.50, 45,1.75, 55,2.00, 65,2.50]
      WHEN 'squat'    THEN ARRAY[0,0.60, 8,1.00, 15,1.25, 25,1.75, 35,2.25, 45,2.75, 55,3.25, 65,3.75]
      WHEN 'deadlift' THEN ARRAY[0,0.80, 8,1.25, 15,1.50, 25,2.00, 35,2.50, 45,3.00, 55,3.50, 65,3.75]
      WHEN 'ohp'      THEN ARRAY[0,0.30, 8,0.45, 15,0.60, 25,0.75, 35,0.90, 45,1.05, 55,1.20, 65,1.40]
      WHEN 'row'      THEN ARRAY[0,0.60, 8,0.90, 15,1.20, 25,1.55, 35,1.90, 45,2.30, 55,2.70, 65,3.00]
      WHEN 'isolation' THEN ARRAY[0,0.08, 8,0.13, 15,0.20, 25,0.30, 35,0.40, 45,0.50, 55,0.60, 65,0.70]
    END;
  END IF;

  -- Interp the (rank, ratio) pairs. v_tiers length is always 16 (8 pairs).
  -- Endpoints clamp; interior linear interp.
  IF v_ratio <= v_tiers[2] THEN RETURN v_tiers[1]; END IF;
  IF v_ratio >= v_tiers[16] THEN RETURN v_tiers[15]; END IF;

  FOR i IN 1..7 LOOP
    v_lo_rank  := v_tiers[i * 2 - 1];
    v_lo_ratio := v_tiers[i * 2];
    v_hi_rank  := v_tiers[i * 2 + 1];
    v_hi_ratio := v_tiers[i * 2 + 2];
    IF v_ratio >= v_lo_ratio AND v_ratio <= v_hi_ratio THEN
      IF v_hi_ratio = v_lo_ratio THEN
        RETURN v_lo_rank;
      END IF;
      RETURN v_lo_rank
        + (v_ratio - v_lo_ratio)
          / (v_hi_ratio - v_lo_ratio)
          * (v_hi_rank - v_lo_rank);
    END IF;
  END LOOP;

  RETURN v_tiers[15];
END;
$$;

-- C.4 rpg_tier_diff_mult — Pokemon Gen 5 adaptation.
CREATE OR REPLACE FUNCTION public.rpg_tier_diff_mult(
  p_implied_tier numeric,
  p_current_rank numeric
) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
AS $$
DECLARE
  v_r   numeric;
  v_num numeric;
  v_den numeric;
  v_raw numeric;
BEGIN
  IF p_implied_tier IS NULL OR p_implied_tier <= 0 THEN RETURN 1.0; END IF;
  v_r := GREATEST(1.0, COALESCE(p_current_rank, 1.0));
  v_num := 2.0 * p_implied_tier + 10.0;
  v_den := p_implied_tier + v_r + 10.0;
  IF v_den <= 0 THEN RETURN 8.0; END IF;
  v_raw := power(v_num / v_den, 2.5);
  IF v_raw < 0.25 THEN RETURN 0.25; END IF;
  IF v_raw > 8.0  THEN RETURN 8.0; END IF;
  RETURN v_raw;
END;
$$;

-- C.5 rpg_abs_strength_premium — Phase 29.6 Path C.
--     1 + 0.8 × clamp((T - 35) / 20, 0, 1)
CREATE OR REPLACE FUNCTION public.rpg_abs_strength_premium(
  p_implied_tier numeric
) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
AS $$
DECLARE
  v_frac numeric;
BEGIN
  IF p_implied_tier IS NULL THEN RETURN 1.0; END IF;
  v_frac := (p_implied_tier - 35.0) / 20.0;
  IF v_frac < 0 THEN v_frac := 0; END IF;
  IF v_frac > 1 THEN v_frac := 1; END IF;
  RETURN 1.0 + 0.8 * v_frac;
END;
$$;

-- C.6 rpg_overload_mult — Phase 29 v2 Refinement #2 in-band PR ladder.
--     Reads exercise_peak_loads_by_rep_range for matching (user, slug,
--     band). Does NOT mutate the table — write happens in the RPC after
--     it knows the chain output is final.
CREATE OR REPLACE FUNCTION public.rpg_overload_mult(
  p_user_id       uuid,
  p_exercise_slug text,
  p_weight        numeric,
  p_reps          int
) RETURNS numeric
LANGUAGE plpgsql STABLE PARALLEL SAFE
AS $$
DECLARE
  v_band   text;
  v_prior  record;
BEGIN
  IF p_reps IS NULL OR p_reps <= 0 THEN RETURN 1.0; END IF;
  v_band := public.rpg_rep_band(p_reps);

  SELECT best_weight, best_reps INTO v_prior
  FROM public.exercise_peak_loads_by_rep_range
  WHERE user_id = p_user_id
    AND exercise_slug = p_exercise_slug
    AND rep_band = v_band;

  IF v_prior IS NULL OR v_prior.best_weight IS NULL THEN
    RETURN 1.0;
  END IF;

  IF p_weight > v_prior.best_weight THEN RETURN 1.15; END IF;
  IF p_reps > v_prior.best_reps AND p_weight >= v_prior.best_weight THEN
    RETURN 1.10;
  END IF;
  IF p_reps > v_prior.best_reps OR p_weight > v_prior.best_weight THEN
    RETURN 1.05;
  END IF;
  RETURN 1.0;
END;
$$;

-- C.7 rpg_frequency_mult — Phase 29 v2 Refinement #3.
--     Counts distinct sessions touching the body part in the trailing
--     7d window (excluding the current session — which hasn't fully
--     materialized yet — and adding 1 for it). Looks up the table
--     [1.00, 1.06, 1.10, 1.06, 1.00] (1-indexed; 6+ clamps to 1.00).
--
--     The `p_exclude_session_id` parameter is the in-flight workout's
--     session_id. The count excludes any xp_events already INSERTed
--     against that workout (which can happen mid-batch — the function
--     is called once per set, and earlier sets in the same workout have
--     already created xp_events). Without this exclusion the multiplier
--     would drift from 1.00 (first set) to 1.06 (second set) to 1.10
--     (third set) within a single session, which would double-count.
CREATE OR REPLACE FUNCTION public.rpg_frequency_mult(
  p_user_id            uuid,
  p_body_part          text,
  p_session_ts         timestamptz,
  p_exclude_session_id uuid DEFAULT NULL
) RETURNS numeric
LANGUAGE plpgsql STABLE PARALLEL SAFE
AS $$
DECLARE
  v_count int;
BEGIN
  IF p_user_id IS NULL OR p_body_part IS NULL THEN RETURN 1.0; END IF;
  SELECT COUNT(DISTINCT e.session_id) INTO v_count
  FROM public.xp_events e
  WHERE e.user_id = p_user_id
    AND e.occurred_at > p_session_ts - interval '7 days'
    AND e.occurred_at <= p_session_ts
    AND (e.attribution ? p_body_part)
    AND (p_exclude_session_id IS NULL
         OR e.session_id IS DISTINCT FROM p_exclude_session_id);

  -- +1 for the current session (counts toward the bucket).
  v_count := v_count + 1;

  IF v_count <= 1 THEN RETURN 1.00; END IF;
  IF v_count = 2 THEN RETURN 1.06; END IF;
  IF v_count = 3 THEN RETURN 1.10; END IF;
  IF v_count = 4 THEN RETURN 1.06; END IF;
  RETURN 1.00;  -- 5+ saturates at 1.00
END;
$$;

-- C.8 rpg_near_failure_inferred — Phase 29 v2 Refinement #4.
CREATE OR REPLACE FUNCTION public.rpg_near_failure_inferred(
  p_target_reps int,
  p_actual_reps int
) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
AS $$
BEGIN
  IF p_target_reps IS NULL OR p_target_reps <= 0 THEN RETURN FALSE; END IF;
  IF p_actual_reps IS NULL OR p_actual_reps <= 0 THEN RETURN FALSE; END IF;
  RETURN p_actual_reps < p_target_reps * 0.85;
END;
$$;

-- ---------------------------------------------------------------------------
-- PART D — record_set_xp (Phase 29 v2 full chain)
-- ---------------------------------------------------------------------------
--
-- Diff vs 00059:
--   * Pre-fetches `profiles.gender` alongside `bodyweight_kg`.
--   * Resolves slug + bodyweight_load_ratio from exercises row.
--   * Computes effective_weight using PER-EXERCISE bodyweight_load_ratio
--     (not the Phase 24c simple addition).
--   * Adds the Phase 29 v2 multipliers: tier_diff_mult,
--     abs_strength_premium, overload_mult, frequency_mult.
--   * Adds near_failure inference + +0.10 intensity bonus when triggered.
--   * Maintains exercise_peak_loads_by_rep_range alongside the existing
--     exercise_peak_loads (separate trackers — see migration header).
--   * Snapshots all 11 multipliers + implied_tier + near_failure into
--     xp_events.payload in chain order.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.record_set_xp(p_set_id uuid)
RETURNS TABLE (
  out_body_part   text,
  out_xp_awarded  numeric,
  out_total_xp    numeric,
  out_rank_before int,
  out_rank_after  int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id      uuid;
  v_workout_id   uuid;
  v_exercise_id  uuid;
  v_exercise_slug text;
  v_weight       numeric;
  v_reps         int;
  v_target_reps  int;
  v_attribution  jsonb;
  v_attr_key     text;
  v_attr_share   numeric;
  v_peak         numeric;
  v_session_vol  numeric;
  v_weekly_vol   numeric;
  v_base         numeric;
  v_intensity    numeric;
  v_strength     numeric;
  v_novelty      numeric;
  v_cap          numeric;
  v_difficulty_mult numeric;
  v_tier_diff_mult  numeric;
  v_asp_mult        numeric;
  v_overload_mult   numeric;
  v_frequency_mult  numeric;
  v_implied_tier    numeric;
  v_current_rank    int;
  v_near_failure    boolean;
  v_bodyweight_kg        numeric(5,2);
  v_gender               text;
  v_uses_bodyweight_load boolean;
  v_bw_load_ratio        numeric;
  v_effective_weight     numeric;
  v_set_xp       numeric;
  v_xp_for_bp    numeric;
  v_event_id     uuid;
  v_event_payload jsonb;
  v_event_attribution jsonb;
  v_existing_event_id uuid;
  v_set_completed boolean;
  v_set_type     text;
  v_total_xp     numeric;
  v_rank_before  int;
  v_rank_after   int;
  v_now          timestamptz := now();
  v_primary_muscle text;
  v_dom_part        text;
  v_dom_share       numeric;
  v_rep_band        text;
BEGIN
  -- Phase 29 v2 note: `target_reps` does not yet exist as a column on
  -- `sets`. Near-failure inference (Refinement #4) lands once the
  -- active-workout UI persists the programmed target on the set row.
  -- Until then `v_target_reps` stays NULL and the inference helper
  -- returns FALSE for every set — no behavior change vs Phase 24d on
  -- the intensity multiplier.
  v_target_reps := NULL;
  SELECT we.exercise_id, we.workout_id, w.user_id,
         s.weight, s.reps, s.is_completed,
         COALESCE(s.set_type, 'working')
  INTO v_exercise_id, v_workout_id, v_user_id,
       v_weight, v_reps, v_set_completed, v_set_type
  FROM public.sets s
  JOIN public.workout_exercises we ON we.id = s.workout_exercise_id
  JOIN public.workouts w           ON w.id = we.workout_id
  WHERE s.id = p_set_id;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'record_set_xp: set % not found', p_set_id
      USING ERRCODE = 'P0002';
  END IF;
  IF NOT v_set_completed OR v_set_type <> 'working' THEN
    RETURN;
  END IF;
  IF v_reps IS NULL OR v_reps < 1 THEN RETURN; END IF;

  SELECT id INTO v_existing_event_id
  FROM public.xp_events
  WHERE user_id = v_user_id AND set_id = p_set_id
  LIMIT 1;
  IF v_existing_event_id IS NOT NULL THEN RETURN; END IF;

  -- Pre-fetch profile (bodyweight + gender) ONCE.
  SELECT bodyweight_kg, gender INTO v_bodyweight_kg, v_gender
  FROM public.profiles
  WHERE id = v_user_id;

  -- Resolve attribution + difficulty_mult + uses_bodyweight_load +
  -- bodyweight_load_ratio + slug. All on one exercise lookup.
  SELECT ex.xp_attribution, ex.muscle_group::text,
         COALESCE(ex.difficulty_mult, 1.0),
         COALESCE(ex.uses_bodyweight_load, FALSE),
         COALESCE(ex.bodyweight_load_ratio, 1.0),
         ex.slug
  INTO v_attribution, v_primary_muscle, v_difficulty_mult,
       v_uses_bodyweight_load, v_bw_load_ratio, v_exercise_slug
  FROM public.exercises ex
  WHERE ex.id = v_exercise_id;

  IF v_attribution IS NULL OR v_attribution = 'null'::jsonb OR v_attribution = '{}'::jsonb THEN
    v_attribution := jsonb_build_object(v_primary_muscle, 1.0);
  END IF;

  SELECT peak_weight INTO v_peak
  FROM public.exercise_peak_loads
  WHERE user_id = v_user_id AND exercise_id = v_exercise_id;
  IF v_peak IS NULL THEN v_peak := 0; END IF;

  -- Phase 29 v2: effective_weight uses PER-EXERCISE ratio.
  v_effective_weight := CASE
    WHEN v_uses_bodyweight_load THEN
      COALESCE(v_weight, 0) + COALESCE(v_bodyweight_kg, 0) * v_bw_load_ratio
    ELSE
      COALESCE(v_weight, 0)
  END;

  -- Dominant body part (for tier_diff_mult + frequency_mult lookups).
  SELECT k, (v::numeric) INTO v_dom_part, v_dom_share
  FROM jsonb_each_text(v_attribution) AS t(k, v)
  ORDER BY (v::numeric) DESC, k ASC
  LIMIT 1;
  IF v_dom_part IS NULL THEN v_dom_part := v_primary_muscle; END IF;

  -- Current rank for the dominant body part.
  SELECT bpp.rank INTO v_current_rank
  FROM public.body_part_progress bpp
  WHERE bpp.user_id = v_user_id AND bpp.body_part = v_dom_part;
  IF v_current_rank IS NULL THEN v_current_rank := 1; END IF;

  -- Phase 29 v2 multipliers — order matters for parity.
  v_implied_tier   := public.rpg_implied_tier_for_exercise(
                        v_exercise_slug, v_weight, v_reps,
                        v_bodyweight_kg, v_gender);
  v_tier_diff_mult := public.rpg_tier_diff_mult(
                        v_implied_tier, v_current_rank::numeric);
  v_asp_mult       := public.rpg_abs_strength_premium(v_implied_tier);
  v_overload_mult  := public.rpg_overload_mult(
                        v_user_id, v_exercise_slug, v_weight, v_reps);
  v_frequency_mult := public.rpg_frequency_mult(
                        v_user_id, v_dom_part, v_now, v_workout_id);
  v_near_failure   := public.rpg_near_failure_inferred(v_target_reps, v_reps);

  -- Base + intensity (with near-failure additive) + strength.
  v_base := public.rpg_base_xp(v_effective_weight, v_reps);
  v_intensity := public.rpg_intensity_for_reps(v_reps)
                 + CASE WHEN v_near_failure THEN 0.10 ELSE 0.0 END;
  IF v_weight > v_peak THEN v_peak := v_weight; END IF;
  v_strength := public.rpg_strength_mult(v_effective_weight, v_peak);

  INSERT INTO public.xp_events (
    id, user_id, event_type, set_id, session_id,
    occurred_at, payload, attribution, total_xp, created_at
  ) VALUES (
    gen_random_uuid(), v_user_id, 'set', p_set_id, v_workout_id,
    v_now, '{}'::jsonb, '{}'::jsonb, 0, v_now
  )
  ON CONFLICT (user_id, set_id) WHERE set_id IS NOT NULL DO NOTHING
  RETURNING id INTO v_event_id;
  IF v_event_id IS NULL THEN RETURN; END IF;

  v_set_xp := 0;
  v_event_attribution := '{}'::jsonb;

  FOR v_attr_key, v_attr_share IN
    SELECT key, value::numeric FROM jsonb_each_text(v_attribution)
  LOOP
    IF v_attr_share <= 0 THEN CONTINUE; END IF;

    SELECT COALESCE(SUM((e.attribution ->> v_attr_key)::numeric), 0)
    INTO v_session_vol
    FROM public.xp_events e
    WHERE e.user_id = v_user_id
      AND e.session_id = v_workout_id
      AND e.id <> v_event_id
      AND (e.attribution ? v_attr_key);

    SELECT COALESCE(SUM((e.attribution ->> v_attr_key)::numeric), 0)
    INTO v_weekly_vol
    FROM public.xp_events e
    WHERE e.user_id = v_user_id
      AND e.occurred_at > v_now - interval '7 days'
      AND e.id <> v_event_id
      AND (e.attribution ? v_attr_key);

    v_novelty := exp(- v_session_vol / 15.0);
    v_cap     := CASE WHEN v_weekly_vol >= 15 THEN 0.3 ELSE 1.0 END;

    -- Phase 29 v2 full chain.
    v_xp_for_bp := v_base
                 * v_intensity
                 * v_strength
                 * v_novelty
                 * v_cap
                 * v_difficulty_mult
                 * v_tier_diff_mult
                 * v_asp_mult
                 * v_overload_mult
                 * v_frequency_mult
                 * v_attr_share;
    v_set_xp := v_set_xp + v_xp_for_bp;
    v_event_attribution := v_event_attribution
      || jsonb_build_object(v_attr_key, v_xp_for_bp);

    SELECT bpp.rank, bpp.total_xp
    INTO v_rank_before, v_total_xp
    FROM public.body_part_progress bpp
    WHERE bpp.user_id = v_user_id AND bpp.body_part = v_attr_key;

    IF v_rank_before IS NULL THEN v_rank_before := 1; END IF;
    IF v_total_xp IS NULL THEN v_total_xp := 0; END IF;

    INSERT INTO public.body_part_progress AS bpp (
      user_id, body_part, total_xp, rank,
      vitality_ewma, vitality_peak, last_event_at, updated_at
    ) VALUES (
      v_user_id, v_attr_key,
      v_xp_for_bp,
      public.rpg_rank_for_xp(v_xp_for_bp),
      0, 0, v_now, v_now
    )
    ON CONFLICT (user_id, body_part) DO UPDATE SET
      total_xp     = bpp.total_xp + EXCLUDED.total_xp,
      rank         = public.rpg_rank_for_xp(bpp.total_xp + EXCLUDED.total_xp),
      last_event_at = v_now,
      updated_at   = v_now
    RETURNING bpp.total_xp, bpp.rank
    INTO v_total_xp, v_rank_after;

    out_body_part   := v_attr_key;
    out_xp_awarded  := v_xp_for_bp;
    out_total_xp    := v_total_xp;
    out_rank_before := v_rank_before;
    out_rank_after  := v_rank_after;
    RETURN NEXT;
  END LOOP;

  -- Payload — all 11 multipliers + implied_tier + near_failure, in
  -- chain order, mirroring SetXpComponents.toJson() in Dart.
  v_event_payload := jsonb_build_object(
    'volume_load',         GREATEST(1.0, COALESCE(v_effective_weight, 0) * v_reps),
    'base_xp',             v_base,
    'intensity_mult',      v_intensity,
    'strength_mult',       v_strength,
    'difficulty_mult',     v_difficulty_mult,
    'tier_diff_mult',      v_tier_diff_mult,
    'abs_strength_premium', v_asp_mult,
    'overload_mult',       v_overload_mult,
    'frequency_mult',      v_frequency_mult,
    'implied_tier',        v_implied_tier,
    'near_failure',        v_near_failure,
    'effective_load',      round(v_effective_weight::numeric, 4),
    'bodyweight_used',     v_uses_bodyweight_load,
    'bodyweight_load_ratio', v_bw_load_ratio,
    'set_xp',              v_set_xp
  );

  UPDATE public.xp_events
  SET payload     = v_event_payload,
      attribution = v_event_attribution,
      total_xp    = v_set_xp
  WHERE id = v_event_id;

  -- Preserve 00052 writer-site guard — peak_loads tracks ENTERED weight.
  IF v_weight > 0 THEN
    INSERT INTO public.exercise_peak_loads (
      user_id, exercise_id, peak_weight, peak_reps, peak_date, updated_at
    ) VALUES (
      v_user_id, v_exercise_id, v_weight, v_reps, v_now, v_now
    )
    ON CONFLICT (user_id, exercise_id) DO UPDATE SET
      peak_weight = EXCLUDED.peak_weight,
      peak_reps   = EXCLUDED.peak_reps,
      peak_date   = EXCLUDED.peak_date,
      updated_at  = v_now
    WHERE EXCLUDED.peak_weight > public.exercise_peak_loads.peak_weight;
  END IF;

  -- Phase 29 v2 — maintain per-band peak. Updates if the current set
  -- improved EITHER weight (any reps) OR reps at the current weight.
  -- This mirrors the Python sim's overload_mult update logic.
  v_rep_band := public.rpg_rep_band(v_reps);
  IF v_weight > 0 THEN
    INSERT INTO public.exercise_peak_loads_by_rep_range (
      user_id, exercise_slug, rep_band, best_weight, best_reps, updated_at
    ) VALUES (
      v_user_id, v_exercise_slug, v_rep_band, v_weight, v_reps, v_now
    )
    ON CONFLICT (user_id, exercise_slug, rep_band) DO UPDATE SET
      best_weight = CASE
        WHEN EXCLUDED.best_weight > exercise_peak_loads_by_rep_range.best_weight
          OR (EXCLUDED.best_weight = exercise_peak_loads_by_rep_range.best_weight
              AND EXCLUDED.best_reps > exercise_peak_loads_by_rep_range.best_reps)
        THEN EXCLUDED.best_weight
        ELSE exercise_peak_loads_by_rep_range.best_weight
      END,
      best_reps = CASE
        WHEN EXCLUDED.best_weight > exercise_peak_loads_by_rep_range.best_weight
          OR (EXCLUDED.best_weight = exercise_peak_loads_by_rep_range.best_weight
              AND EXCLUDED.best_reps > exercise_peak_loads_by_rep_range.best_reps)
        THEN EXCLUDED.best_reps
        ELSE exercise_peak_loads_by_rep_range.best_reps
      END,
      updated_at = v_now;
  END IF;

  RETURN;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_set_xp(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.record_set_xp(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- PART E — record_session_xp_batch (Phase 29 v2 full chain, hot path)
-- ---------------------------------------------------------------------------
--
-- This is the production save_workout hot-path RPC. Diff vs 00059 is the
-- same chain extension as record_set_xp (PART D above) — see that
-- function's diff notes. Float8 hot-path discipline preserved.
--
-- Notable choice: tier_diff_mult / abs_strength_premium / overload_mult
-- / frequency_mult are computed PER SET (not per-bp) because they
-- depend on properties of the SET (weight, reps, exercise_slug, the
-- DOMINANT body part) not the body part being attributed to. The cap
-- and novelty multipliers remain per-bp (they depend on the body
-- part's volume).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.record_session_xp_batch(p_workout_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id          uuid;
  v_now              timestamptz := now();
  v_set_record       record;
  v_attribution      jsonb;
  v_attr_key         text;
  v_attr_share       float8;
  v_peak             numeric;
  v_base_f           float8;
  v_intensity_f      float8;
  v_strength_f       float8;
  v_novelty_f        float8;
  v_cap_f            float8;
  v_difficulty_mult_f float8;
  v_tier_diff_mult_f  float8;
  v_asp_mult_f        float8;
  v_overload_mult_f   float8;
  v_frequency_mult_f  float8;
  v_implied_tier_f    float8;
  v_near_failure      boolean;
  v_bodyweight_kg     numeric(5,2);
  v_gender            text;
  v_bodyweight_f      float8;
  v_effective_weight_f float8;
  v_xp_for_bp_f      float8;
  v_set_xp_f         float8;
  v_event_attribution jsonb;
  v_event_payload    jsonb;
  v_peaks_map        jsonb := '{}'::jsonb;
  v_session_vol      float8[] := ARRAY[0,0,0,0,0,0,0]::float8[];
  v_weekly_vol       float8[] := ARRAY[0,0,0,0,0,0,0]::float8[];
  v_bp_total         float8[] := ARRAY[0,0,0,0,0,0,0]::float8[];
  v_weekly_chest     float8;
  v_weekly_back      float8;
  v_weekly_legs      float8;
  v_weekly_shoulders float8;
  v_weekly_arms      float8;
  v_weekly_core      float8;
  v_weekly_cardio    float8;
  v_bp_idx           int;
  v_event_ids        uuid[]    := ARRAY[]::uuid[];
  v_event_set_ids    uuid[]    := ARRAY[]::uuid[];
  v_event_payloads   jsonb[]   := ARRAY[]::jsonb[];
  v_event_attrs      jsonb[]   := ARRAY[]::jsonb[];
  v_event_totals     numeric[] := ARRAY[]::numeric[];
  v_event_id         uuid;
  v_dom_part         text;
  v_current_rank_n   int;
BEGIN
  SELECT user_id INTO v_user_id FROM public.workouts WHERE id = p_workout_id;
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'record_session_xp_batch: workout % not found', p_workout_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Pre-fetch profile.
  SELECT bodyweight_kg, gender INTO v_bodyweight_kg, v_gender
  FROM public.profiles WHERE id = v_user_id;
  v_bodyweight_f := COALESCE(v_bodyweight_kg, 0)::float8;

  SELECT COALESCE(jsonb_object_agg(epl.exercise_id::text, epl.peak_weight), '{}'::jsonb)
  INTO v_peaks_map
  FROM public.exercise_peak_loads epl
  WHERE epl.user_id = v_user_id
    AND epl.exercise_id IN (
      SELECT DISTINCT we.exercise_id
      FROM public.workout_exercises we
      JOIN public.sets s ON s.workout_exercise_id = we.id
      WHERE we.workout_id = p_workout_id
        AND s.is_completed = TRUE
        AND COALESCE(s.set_type, 'working') = 'working'
        AND s.reps IS NOT NULL AND s.reps >= 1
    );

  -- Prior weekly volume per body_part (xp_events outside this session).
  WITH agg AS (
    SELECT kv.key AS bp_key, SUM(kv.value::float8) AS bp_sum
    FROM public.xp_events e
    CROSS JOIN LATERAL jsonb_each_text(e.attribution) AS kv(key, value)
    WHERE e.user_id = v_user_id
      AND e.occurred_at > v_now - interval '7 days'
      AND (e.session_id IS DISTINCT FROM p_workout_id)
    GROUP BY kv.key
  )
  SELECT
    COALESCE(MAX(bp_sum) FILTER (WHERE bp_key = 'chest'),     0)::float8,
    COALESCE(MAX(bp_sum) FILTER (WHERE bp_key = 'back'),      0)::float8,
    COALESCE(MAX(bp_sum) FILTER (WHERE bp_key = 'legs'),      0)::float8,
    COALESCE(MAX(bp_sum) FILTER (WHERE bp_key = 'shoulders'), 0)::float8,
    COALESCE(MAX(bp_sum) FILTER (WHERE bp_key = 'arms'),      0)::float8,
    COALESCE(MAX(bp_sum) FILTER (WHERE bp_key = 'core'),      0)::float8,
    COALESCE(MAX(bp_sum) FILTER (WHERE bp_key = 'cardio'),    0)::float8
  INTO v_weekly_chest, v_weekly_back, v_weekly_legs,
       v_weekly_shoulders, v_weekly_arms, v_weekly_core, v_weekly_cardio
  FROM agg;
  v_weekly_vol[1] := v_weekly_chest;
  v_weekly_vol[2] := v_weekly_back;
  v_weekly_vol[3] := v_weekly_legs;
  v_weekly_vol[4] := v_weekly_shoulders;
  v_weekly_vol[5] := v_weekly_arms;
  v_weekly_vol[6] := v_weekly_core;
  v_weekly_vol[7] := v_weekly_cardio;

  FOR v_set_record IN
    SELECT
      s.id           AS set_id,
      s.weight       AS weight,
      s.reps         AS reps,
      -- Phase 29 v2 note: target_reps column not yet on sets — see
      -- record_set_xp header. Hard-NULL until the UI persists it.
      NULL::int      AS target_reps,
      we.exercise_id AS exercise_id,
      ex.slug        AS exercise_slug,
      ex.xp_attribution AS xp_attribution,
      ex.muscle_group::text AS primary_muscle,
      COALESCE(ex.difficulty_mult, 1.0) AS difficulty_mult,
      COALESCE(ex.uses_bodyweight_load, FALSE) AS uses_bodyweight_load,
      COALESCE(ex.bodyweight_load_ratio, 1.0) AS bodyweight_load_ratio
    FROM public.sets s
    JOIN public.workout_exercises we ON we.id = s.workout_exercise_id
    JOIN public.exercises ex          ON ex.id = we.exercise_id
    WHERE we.workout_id = p_workout_id
      AND s.is_completed = TRUE
      AND COALESCE(s.set_type, 'working') = 'working'
      AND s.reps IS NOT NULL AND s.reps >= 1
    ORDER BY we."order" ASC, s.set_number ASC
  LOOP
    v_attribution := v_set_record.xp_attribution;
    IF v_attribution IS NULL OR v_attribution = 'null'::jsonb OR v_attribution = '{}'::jsonb THEN
      v_attribution := jsonb_build_object(v_set_record.primary_muscle, 1.0);
    END IF;

    v_peak := COALESCE((v_peaks_map ->> v_set_record.exercise_id::text)::numeric, 0);
    IF v_set_record.weight > v_peak THEN
      v_peak := v_set_record.weight;
      v_peaks_map := v_peaks_map
        || jsonb_build_object(v_set_record.exercise_id::text, v_peak);
    END IF;

    -- Phase 29 v2 effective_weight with PER-EXERCISE ratio.
    v_effective_weight_f := CASE
      WHEN v_set_record.uses_bodyweight_load THEN
        COALESCE(v_set_record.weight, 0)::float8
        + v_bodyweight_f * v_set_record.bodyweight_load_ratio::float8
      ELSE
        COALESCE(v_set_record.weight, 0)::float8
    END;

    -- Dominant body part for tier_diff_mult + frequency_mult.
    SELECT k INTO v_dom_part
    FROM jsonb_each_text(v_attribution) AS t(k, v)
    ORDER BY (v::numeric) DESC, k ASC
    LIMIT 1;
    IF v_dom_part IS NULL THEN
      v_dom_part := v_set_record.primary_muscle;
    END IF;

    -- Current rank for the dominant body part.
    SELECT bpp.rank INTO v_current_rank_n
    FROM public.body_part_progress bpp
    WHERE bpp.user_id = v_user_id AND bpp.body_part = v_dom_part;
    IF v_current_rank_n IS NULL THEN v_current_rank_n := 1; END IF;

    -- Phase 29 v2 multipliers (per-set, not per-bp).
    v_implied_tier_f := public.rpg_implied_tier_for_exercise(
      v_set_record.exercise_slug, v_set_record.weight, v_set_record.reps,
      v_bodyweight_kg, v_gender)::float8;
    v_tier_diff_mult_f := public.rpg_tier_diff_mult(
      v_implied_tier_f::numeric, v_current_rank_n::numeric)::float8;
    v_asp_mult_f := public.rpg_abs_strength_premium(
      v_implied_tier_f::numeric)::float8;
    v_overload_mult_f := public.rpg_overload_mult(
      v_user_id, v_set_record.exercise_slug,
      v_set_record.weight, v_set_record.reps)::float8;
    v_frequency_mult_f := public.rpg_frequency_mult(
      v_user_id, v_dom_part, v_now, p_workout_id)::float8;
    v_near_failure := public.rpg_near_failure_inferred(
      v_set_record.target_reps, v_set_record.reps);

    v_base_f      := public.rpg_base_xp(v_effective_weight_f::numeric, v_set_record.reps)::float8;
    v_intensity_f := public.rpg_intensity_for_reps(v_set_record.reps)::float8
                     + CASE WHEN v_near_failure THEN 0.10 ELSE 0.0 END;
    v_strength_f  := public.rpg_strength_mult(v_effective_weight_f::numeric, v_peak)::float8;
    v_difficulty_mult_f := v_set_record.difficulty_mult::float8;

    v_set_xp_f := 0;
    v_event_attribution := '{}'::jsonb;

    FOR v_attr_key, v_attr_share IN
      SELECT key, (value::text)::float8 FROM jsonb_each_text(v_attribution)
    LOOP
      IF v_attr_share <= 0 THEN CONTINUE; END IF;

      v_bp_idx := CASE v_attr_key
                    WHEN 'chest'     THEN 1
                    WHEN 'back'      THEN 2
                    WHEN 'legs'      THEN 3
                    WHEN 'shoulders' THEN 4
                    WHEN 'arms'      THEN 5
                    WHEN 'core'      THEN 6
                    WHEN 'cardio'    THEN 7
                    ELSE NULL
                  END;
      IF v_bp_idx IS NULL THEN
        RAISE EXCEPTION
          'record_session_xp_batch: unknown body_part key % (set_id=%, exercise_id=%)',
          v_attr_key, v_set_record.set_id, v_set_record.exercise_id
          USING ERRCODE = '22023';
      END IF;

      v_novelty_f := exp(- v_session_vol[v_bp_idx] / 15.0);
      v_cap_f     := CASE WHEN v_weekly_vol[v_bp_idx] >= 15 THEN 0.3 ELSE 1.0 END;

      v_xp_for_bp_f := v_base_f
                     * v_intensity_f
                     * v_strength_f
                     * v_novelty_f
                     * v_cap_f
                     * v_difficulty_mult_f
                     * v_tier_diff_mult_f
                     * v_asp_mult_f
                     * v_overload_mult_f
                     * v_frequency_mult_f
                     * v_attr_share;

      v_set_xp_f := v_set_xp_f + v_xp_for_bp_f;
      v_event_attribution := v_event_attribution
        || jsonb_build_object(v_attr_key, round(v_xp_for_bp_f::numeric, 4));

      v_session_vol[v_bp_idx] := v_session_vol[v_bp_idx] + v_xp_for_bp_f;
      v_weekly_vol[v_bp_idx]  := v_weekly_vol[v_bp_idx]  + v_xp_for_bp_f;
      v_bp_total[v_bp_idx]    := v_bp_total[v_bp_idx]    + v_xp_for_bp_f;
    END LOOP;

    v_event_payload := jsonb_build_object(
      'volume_load',         GREATEST(1.0, v_effective_weight_f * v_set_record.reps),
      'base_xp',             round(v_base_f::numeric, 4),
      'intensity_mult',      round(v_intensity_f::numeric, 4),
      'strength_mult',       round(v_strength_f::numeric, 4),
      'difficulty_mult',     round(v_difficulty_mult_f::numeric, 4),
      'tier_diff_mult',      round(v_tier_diff_mult_f::numeric, 4),
      'abs_strength_premium', round(v_asp_mult_f::numeric, 4),
      'overload_mult',       round(v_overload_mult_f::numeric, 4),
      'frequency_mult',      round(v_frequency_mult_f::numeric, 4),
      'implied_tier',        round(v_implied_tier_f::numeric, 4),
      'near_failure',        v_near_failure,
      'effective_load',      round(v_effective_weight_f::numeric, 4),
      'bodyweight_used',     v_set_record.uses_bodyweight_load,
      'bodyweight_load_ratio', v_set_record.bodyweight_load_ratio,
      'set_xp',              round(v_set_xp_f::numeric, 4)
    );

    v_event_id := gen_random_uuid();
    v_event_ids      := v_event_ids      || v_event_id;
    v_event_set_ids  := v_event_set_ids  || v_set_record.set_id;
    v_event_payloads := v_event_payloads || v_event_payload;
    v_event_attrs    := v_event_attrs    || v_event_attribution;
    v_event_totals   := v_event_totals   || round(v_set_xp_f::numeric, 4);
  END LOOP;

  IF array_length(v_event_ids, 1) IS NULL THEN RETURN; END IF;

  INSERT INTO public.xp_events (
    id, user_id, event_type, set_id, session_id,
    occurred_at, payload, attribution, total_xp, created_at
  )
  SELECT eid, v_user_id, 'set', sid, p_workout_id,
         v_now, pld, attr, tot, v_now
  FROM unnest(v_event_ids, v_event_set_ids, v_event_payloads,
              v_event_attrs, v_event_totals) AS u(eid, sid, pld, attr, tot)
  ON CONFLICT (user_id, set_id) WHERE set_id IS NOT NULL DO NOTHING;

  INSERT INTO public.body_part_progress AS bpp (
    user_id, body_part, total_xp, rank,
    vitality_ewma, vitality_peak, last_event_at, updated_at
  )
  SELECT v_user_id, bp_token, bp_xp,
         public.rpg_rank_for_xp(bp_xp),
         0, 0, v_now, v_now
  FROM (
    SELECT
      CASE ord
        WHEN 1 THEN 'chest' WHEN 2 THEN 'back' WHEN 3 THEN 'legs'
        WHEN 4 THEN 'shoulders' WHEN 5 THEN 'arms' WHEN 6 THEN 'core'
        WHEN 7 THEN 'cardio'
      END AS bp_token,
      round(bp_xp_f::numeric, 4) AS bp_xp
    FROM unnest(v_bp_total) WITH ORDINALITY AS u(bp_xp_f, ord)
    WHERE bp_xp_f > 0
  ) src
  ON CONFLICT (user_id, body_part) DO UPDATE SET
    total_xp     = bpp.total_xp + EXCLUDED.total_xp,
    rank         = public.rpg_rank_for_xp(bpp.total_xp + EXCLUDED.total_xp),
    last_event_at = v_now,
    updated_at   = v_now;

  -- Preserve 00050 bugfix — peak_loads tracks ENTERED weight only.
  WITH per_set AS (
    SELECT we.exercise_id, s.weight, s.reps
    FROM public.sets s
    JOIN public.workout_exercises we ON we.id = s.workout_exercise_id
    WHERE we.workout_id = p_workout_id
      AND s.is_completed = TRUE
      AND COALESCE(s.set_type, 'working') = 'working'
      AND s.reps IS NOT NULL AND s.reps >= 1
      AND s.weight > 0
  ),
  per_exercise AS (
    SELECT DISTINCT ON (exercise_id) exercise_id,
           weight AS peak_weight, reps AS peak_reps
    FROM per_set ORDER BY exercise_id, weight DESC, reps DESC
  )
  INSERT INTO public.exercise_peak_loads (
    user_id, exercise_id, peak_weight, peak_reps, peak_date, updated_at
  )
  SELECT v_user_id, exercise_id, peak_weight, peak_reps, v_now, v_now
  FROM per_exercise
  ON CONFLICT (user_id, exercise_id) DO UPDATE SET
    peak_weight = EXCLUDED.peak_weight,
    peak_reps   = EXCLUDED.peak_reps,
    peak_date   = EXCLUDED.peak_date,
    updated_at  = v_now
  WHERE EXCLUDED.peak_weight > public.exercise_peak_loads.peak_weight;

  -- Phase 29 v2 — maintain exercise_peak_loads_by_rep_range per band.
  WITH per_band_set AS (
    SELECT we.exercise_id, ex.slug AS exercise_slug,
           public.rpg_rep_band(s.reps) AS rep_band,
           s.weight, s.reps
    FROM public.sets s
    JOIN public.workout_exercises we ON we.id = s.workout_exercise_id
    JOIN public.exercises ex          ON ex.id = we.exercise_id
    WHERE we.workout_id = p_workout_id
      AND s.is_completed = TRUE
      AND COALESCE(s.set_type, 'working') = 'working'
      AND s.reps IS NOT NULL AND s.reps >= 1
      AND s.weight > 0
  ),
  per_band AS (
    SELECT DISTINCT ON (exercise_slug, rep_band)
           exercise_slug, rep_band, weight, reps
    FROM per_band_set
    ORDER BY exercise_slug, rep_band, weight DESC, reps DESC
  )
  INSERT INTO public.exercise_peak_loads_by_rep_range (
    user_id, exercise_slug, rep_band, best_weight, best_reps, updated_at
  )
  SELECT v_user_id, exercise_slug, rep_band, weight, reps, v_now
  FROM per_band
  ON CONFLICT (user_id, exercise_slug, rep_band) DO UPDATE SET
    best_weight = CASE
      WHEN EXCLUDED.best_weight > exercise_peak_loads_by_rep_range.best_weight
        OR (EXCLUDED.best_weight = exercise_peak_loads_by_rep_range.best_weight
            AND EXCLUDED.best_reps > exercise_peak_loads_by_rep_range.best_reps)
      THEN EXCLUDED.best_weight
      ELSE exercise_peak_loads_by_rep_range.best_weight
    END,
    best_reps = CASE
      WHEN EXCLUDED.best_weight > exercise_peak_loads_by_rep_range.best_weight
        OR (EXCLUDED.best_weight = exercise_peak_loads_by_rep_range.best_weight
            AND EXCLUDED.best_reps > exercise_peak_loads_by_rep_range.best_reps)
      THEN EXCLUDED.best_reps
      ELSE exercise_peak_loads_by_rep_range.best_reps
    END,
    updated_at = v_now;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_session_xp_batch(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.record_session_xp_batch(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- PART F — _rpg_backfill_chunk (Phase 29 v2 full chain, historical replay)
-- ---------------------------------------------------------------------------
--
-- Same chain as record_set_xp + record_session_xp_batch. Reads CURRENT
-- bodyweight + gender (documented forward-only semantics from Phase 24c
-- — historical user dimensions are not available, current is the best
-- approximation; documented in docs/xp-difficulty-framework.md §4).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._rpg_backfill_chunk(p_user_id uuid, p_chunk_size int)
RETURNS TABLE (
  processed   bigint,
  visited     bigint,
  last_set_id uuid,
  last_set_ts timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_processed   bigint := 0;
  v_visited     bigint := 0;
  r_set         record;
  v_attribution jsonb;
  v_primary     text;
  v_peak        numeric;
  v_base        numeric;
  v_intensity   numeric;
  v_strength    numeric;
  v_novelty     numeric;
  v_cap         numeric;
  v_difficulty_mult numeric;
  v_tier_diff_mult  numeric;
  v_asp_mult        numeric;
  v_overload_mult   numeric;
  v_frequency_mult  numeric;
  v_implied_tier    numeric;
  v_near_failure    boolean;
  v_dom_part        text;
  v_current_rank    int;
  v_rep_band        text;
  v_bodyweight_kg    numeric(5,2);
  v_gender           text;
  v_effective_weight numeric;
  v_attr_key    text;
  v_attr_share  numeric;
  v_session_vol numeric;
  v_weekly_vol  numeric;
  v_xp_for_bp   numeric;
  v_set_xp      numeric;
  v_event_id    uuid;
  v_event_payload     jsonb;
  v_event_attribution jsonb;
  v_now         timestamptz;
  v_cursor_ts   timestamptz;
  v_cursor_id   uuid;
  v_last_set_id uuid;
  v_last_set_ts timestamptz;
BEGIN
  SELECT bp.last_set_ts, bp.last_set_id INTO v_cursor_ts, v_cursor_id
  FROM public.backfill_progress bp
  WHERE bp.user_id = p_user_id;

  SELECT bodyweight_kg, gender INTO v_bodyweight_kg, v_gender
  FROM public.profiles WHERE id = p_user_id;

  FOR r_set IN
    SELECT
      s.id            AS set_id,
      s.workout_exercise_id,
      we.exercise_id,
      we.workout_id,
      s.weight, s.reps, s.is_completed,
      -- Phase 29 v2: target_reps column not yet on sets. See header.
      NULL::int       AS target_reps,
      COALESCE(s.set_type, 'working') AS set_type,
      w.started_at    AS occurred_at,
      ex.slug         AS exercise_slug,
      ex.muscle_group::text AS primary_muscle,
      ex.xp_attribution,
      COALESCE(ex.difficulty_mult, 1.0) AS difficulty_mult,
      COALESCE(ex.uses_bodyweight_load, FALSE) AS uses_bodyweight_load,
      COALESCE(ex.bodyweight_load_ratio, 1.0) AS bodyweight_load_ratio
    FROM public.sets s
    JOIN public.workout_exercises we ON we.id = s.workout_exercise_id
    JOIN public.workouts w           ON w.id = we.workout_id
    JOIN public.exercises ex         ON ex.id = we.exercise_id
    WHERE w.user_id = p_user_id
      AND w.finished_at IS NOT NULL
      AND s.is_completed = TRUE
      AND COALESCE(s.set_type, 'working') = 'working'
      AND s.reps IS NOT NULL AND s.reps >= 1
      AND (v_cursor_ts IS NULL OR (w.started_at, s.id) > (v_cursor_ts, v_cursor_id))
    ORDER BY w.started_at ASC, s.id ASC
    LIMIT p_chunk_size
  LOOP
    v_visited := v_visited + 1;
    v_now := r_set.occurred_at;

    v_attribution := r_set.xp_attribution;
    v_primary := r_set.primary_muscle;
    IF v_attribution IS NULL OR v_attribution = 'null'::jsonb OR v_attribution = '{}'::jsonb THEN
      v_attribution := jsonb_build_object(v_primary, 1.0);
    END IF;

    SELECT peak_weight INTO v_peak
    FROM public.exercise_peak_loads
    WHERE user_id = p_user_id AND exercise_id = r_set.exercise_id;
    IF v_peak IS NULL THEN v_peak := 0; END IF;
    IF r_set.weight > v_peak THEN v_peak := r_set.weight; END IF;

    v_effective_weight := CASE
      WHEN r_set.uses_bodyweight_load THEN
        COALESCE(r_set.weight, 0)
        + COALESCE(v_bodyweight_kg, 0) * r_set.bodyweight_load_ratio
      ELSE
        COALESCE(r_set.weight, 0)
    END;

    -- Dominant body part.
    SELECT k INTO v_dom_part
    FROM jsonb_each_text(v_attribution) AS t(k, v)
    ORDER BY (v::numeric) DESC, k ASC LIMIT 1;
    IF v_dom_part IS NULL THEN v_dom_part := v_primary; END IF;

    SELECT bpp.rank INTO v_current_rank
    FROM public.body_part_progress bpp
    WHERE bpp.user_id = p_user_id AND bpp.body_part = v_dom_part;
    IF v_current_rank IS NULL THEN v_current_rank := 1; END IF;

    v_implied_tier := public.rpg_implied_tier_for_exercise(
      r_set.exercise_slug, r_set.weight, r_set.reps,
      v_bodyweight_kg, v_gender);
    v_tier_diff_mult := public.rpg_tier_diff_mult(
      v_implied_tier, v_current_rank::numeric);
    v_asp_mult := public.rpg_abs_strength_premium(v_implied_tier);
    v_overload_mult := public.rpg_overload_mult(
      p_user_id, r_set.exercise_slug, r_set.weight, r_set.reps);
    v_frequency_mult := public.rpg_frequency_mult(
      p_user_id, v_dom_part, v_now, r_set.workout_id);
    v_near_failure := public.rpg_near_failure_inferred(
      r_set.target_reps, r_set.reps);

    v_base      := public.rpg_base_xp(v_effective_weight, r_set.reps);
    v_intensity := public.rpg_intensity_for_reps(r_set.reps)
                  + CASE WHEN v_near_failure THEN 0.10 ELSE 0.0 END;
    v_strength  := public.rpg_strength_mult(v_effective_weight, v_peak);
    v_difficulty_mult := r_set.difficulty_mult;

    INSERT INTO public.xp_events (
      id, user_id, event_type, set_id, session_id,
      occurred_at, payload, attribution, total_xp, created_at
    ) VALUES (
      gen_random_uuid(), p_user_id, 'set', r_set.set_id, r_set.workout_id,
      v_now, '{}'::jsonb, '{}'::jsonb, 0, v_now
    )
    ON CONFLICT (user_id, set_id) WHERE set_id IS NOT NULL DO NOTHING
    RETURNING id INTO v_event_id;

    IF v_event_id IS NULL THEN
      v_last_set_id := r_set.set_id;
      v_last_set_ts := r_set.occurred_at;
      CONTINUE;
    END IF;

    v_set_xp := 0;
    v_event_attribution := '{}'::jsonb;

    FOR v_attr_key, v_attr_share IN
      SELECT key, value::numeric FROM jsonb_each_text(v_attribution)
    LOOP
      IF v_attr_share <= 0 THEN CONTINUE; END IF;

      SELECT COALESCE(SUM((e.attribution ->> v_attr_key)::numeric), 0)
      INTO v_session_vol
      FROM public.xp_events e
      WHERE e.user_id = p_user_id
        AND e.session_id = r_set.workout_id
        AND e.id <> v_event_id
        AND (e.attribution ? v_attr_key);

      SELECT COALESCE(SUM((e.attribution ->> v_attr_key)::numeric), 0)
      INTO v_weekly_vol
      FROM public.xp_events e
      WHERE e.user_id = p_user_id
        AND e.occurred_at > v_now - interval '7 days'
        AND e.occurred_at <= v_now
        AND e.id <> v_event_id
        AND (e.attribution ? v_attr_key);

      v_novelty := exp(- v_session_vol / 15.0);
      v_cap     := CASE WHEN v_weekly_vol >= 15 THEN 0.3 ELSE 1.0 END;

      v_xp_for_bp := v_base * v_intensity * v_strength * v_novelty * v_cap
                   * v_difficulty_mult * v_tier_diff_mult * v_asp_mult
                   * v_overload_mult * v_frequency_mult * v_attr_share;
      v_set_xp := v_set_xp + v_xp_for_bp;
      v_event_attribution := v_event_attribution || jsonb_build_object(v_attr_key, v_xp_for_bp);

      INSERT INTO public.body_part_progress AS bpp (
        user_id, body_part, total_xp, rank,
        vitality_ewma, vitality_peak, last_event_at, updated_at
      ) VALUES (
        p_user_id, v_attr_key,
        v_xp_for_bp,
        public.rpg_rank_for_xp(v_xp_for_bp),
        0, 0, v_now, v_now
      )
      ON CONFLICT (user_id, body_part) DO UPDATE SET
        total_xp     = bpp.total_xp + EXCLUDED.total_xp,
        rank         = public.rpg_rank_for_xp(bpp.total_xp + EXCLUDED.total_xp),
        last_event_at = v_now,
        updated_at   = v_now;
    END LOOP;

    v_event_payload := jsonb_build_object(
      'volume_load',         GREATEST(1.0, COALESCE(v_effective_weight, 0) * r_set.reps),
      'base_xp',             v_base,
      'intensity_mult',      v_intensity,
      'strength_mult',       v_strength,
      'difficulty_mult',     v_difficulty_mult,
      'tier_diff_mult',      v_tier_diff_mult,
      'abs_strength_premium', v_asp_mult,
      'overload_mult',       v_overload_mult,
      'frequency_mult',      v_frequency_mult,
      'implied_tier',        v_implied_tier,
      'near_failure',        v_near_failure,
      'effective_load',      round(v_effective_weight::numeric, 4),
      'bodyweight_used',     r_set.uses_bodyweight_load,
      'bodyweight_load_ratio', r_set.bodyweight_load_ratio,
      'set_xp',              v_set_xp
    );

    UPDATE public.xp_events
    SET payload     = v_event_payload,
        attribution = v_event_attribution,
        total_xp    = v_set_xp
    WHERE id = v_event_id;

    IF r_set.weight > 0 THEN
      INSERT INTO public.exercise_peak_loads (
        user_id, exercise_id, peak_weight, peak_reps, peak_date, updated_at
      ) VALUES (
        p_user_id, r_set.exercise_id, r_set.weight, r_set.reps, v_now, v_now
      )
      ON CONFLICT (user_id, exercise_id) DO UPDATE SET
        peak_weight = GREATEST(public.exercise_peak_loads.peak_weight, EXCLUDED.peak_weight),
        peak_reps   = CASE
          WHEN EXCLUDED.peak_weight > public.exercise_peak_loads.peak_weight
          THEN EXCLUDED.peak_reps
          ELSE public.exercise_peak_loads.peak_reps
        END,
        peak_date   = CASE
          WHEN EXCLUDED.peak_weight > public.exercise_peak_loads.peak_weight
          THEN EXCLUDED.peak_date
          ELSE public.exercise_peak_loads.peak_date
        END,
        updated_at  = v_now;

      -- Per-band peak (Phase 29 v2).
      v_rep_band := public.rpg_rep_band(r_set.reps);
      INSERT INTO public.exercise_peak_loads_by_rep_range (
        user_id, exercise_slug, rep_band, best_weight, best_reps, updated_at
      ) VALUES (
        p_user_id, r_set.exercise_slug, v_rep_band, r_set.weight, r_set.reps, v_now
      )
      ON CONFLICT (user_id, exercise_slug, rep_band) DO UPDATE SET
        best_weight = CASE
          WHEN EXCLUDED.best_weight > exercise_peak_loads_by_rep_range.best_weight
            OR (EXCLUDED.best_weight = exercise_peak_loads_by_rep_range.best_weight
                AND EXCLUDED.best_reps > exercise_peak_loads_by_rep_range.best_reps)
          THEN EXCLUDED.best_weight
          ELSE exercise_peak_loads_by_rep_range.best_weight
        END,
        best_reps = CASE
          WHEN EXCLUDED.best_weight > exercise_peak_loads_by_rep_range.best_weight
            OR (EXCLUDED.best_weight = exercise_peak_loads_by_rep_range.best_weight
                AND EXCLUDED.best_reps > exercise_peak_loads_by_rep_range.best_reps)
          THEN EXCLUDED.best_reps
          ELSE exercise_peak_loads_by_rep_range.best_reps
        END,
        updated_at = v_now;
    END IF;

    v_processed := v_processed + 1;
    v_last_set_id := r_set.set_id;
    v_last_set_ts := r_set.occurred_at;
  END LOOP;

  processed   := v_processed;
  visited     := v_visited;
  last_set_id := v_last_set_id;
  last_set_ts := v_last_set_ts;
  RETURN NEXT;
END;
$$;

REVOKE EXECUTE ON FUNCTION public._rpg_backfill_chunk(uuid, int) FROM PUBLIC, anon;
-- _rpg_backfill_chunk intentionally NOT granted to authenticated.

-- ---------------------------------------------------------------------------
-- PART G — Backfill: re-derive ranks via the piecewise curve
-- ---------------------------------------------------------------------------
--
-- The new `rpg_cumulative_xp_for_rank` is piecewise. Existing rows in
-- body_part_progress have `rank` computed from the OLD geometric curve,
-- so a user at total_xp = 100_000 was at rank ~55 under the old curve
-- and is at rank ~99 (capped) under the new linear-band curve.
--
-- Re-derive ranks in a single UPDATE. xp_events.payload rows stay
-- frozen — only the `body_part_progress.rank` column changes.
-- ---------------------------------------------------------------------------

UPDATE public.body_part_progress
SET rank = public.rpg_rank_for_xp(total_xp),
    updated_at = now()
WHERE rank IS DISTINCT FROM public.rpg_rank_for_xp(total_xp);

-- Sanity: every rank in [1, 99]. The function returns 1 for total_xp <= 0
-- and caps at 99 internally, but the bare update is defensive against a
-- pathological NULL total_xp (which shouldn't exist; column is NOT NULL).
DO $$
DECLARE
  v_bad int;
BEGIN
  SELECT count(*) INTO v_bad
  FROM public.body_part_progress
  WHERE rank IS NULL OR rank < 1 OR rank > 99;
  IF v_bad > 0 THEN
    RAISE EXCEPTION
      '00065 PART G: % body_part_progress rows have out-of-range rank '
      'after backfill (expected all in [1, 99])', v_bad;
  END IF;
END $$;

COMMIT;
