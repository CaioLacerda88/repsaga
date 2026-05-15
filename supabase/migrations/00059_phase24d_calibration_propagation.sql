-- =============================================================================
-- 00059 — Phase 24d calibration propagation
--
-- ## What this does
--
-- Propagates the Phase 24d six-archetype balance simulation's iter-3 sign-off
-- (see `docs/xp-balance-baseline.md`) into the canonical SQL formula sites:
--
--   * `VOLUME_EXPONENT` 0.65 → 0.60 (more sub-linear; penalizes high
--     volume_load sets, resolves criterion C4 machine_only > intermediate
--     inversion)
--   * `WEEKLY_CAP_SETS` 20 → 15 (tighter weekly cap; bites high-frequency /
--     high-volume profiles like the hypertrophy bodybuilder)
--   * `OVER_CAP_MULTIPLIER` 0.5 → 0.3 (stronger over-cap penalty; asymmetric
--     bodybuilder vs powerlifter benefit per the iter-3 analysis)
--   * Per-slug `difficulty_mult` -0.05 applied to 28 curated T4 slugs
--     (resolves the per-set machine-vs-free-weight ordering at archetype
--     totals while preserving the framework's T4 < T3 ordering)
--
-- The 28-slug T4 set is sourced from:
--   * `00053_add_exercise_difficulty_mult.sql` audit comments — every
--     row tagged `-- T4 + N sec → 0.95±0.04` (23 slugs)
--   * `00055_phase24b_new_default_exercises.sql` Phase-24b T4 additions
--     (5 slugs)
--
-- ## Forward-only semantics (as with every prior 24-series migration)
--
-- xp_events.payload rows written BEFORE this migration's deploy keep their
-- iter-1 / iter-2 / iter-3-provisional values frozen. Sets written AFTER
-- this migration use the new constants + adjusted T4 difficulty_mult column
-- values. No retroactive replay; any user re-running their backfill will
-- get the new chain (this is documented in the framework doc and is the
-- intended behavior — backfill is for "fill in missing XP", not "rewrite
-- history with the latest tuning").
--
-- ## Synchronized formula sites — keep in lockstep
--
-- This migration is the SQL half of an atomic Dart + SQL + Python sim +
-- fixture propagation PR. The other halves:
--
--   * `lib/features/rpg/domain/xp_calculator.dart` — Dart constants
--     `volumeExponent`, `weeklyCapSets`, `overCapMultiplier` updated to
--     match (mirrors the formula chain consumed by the offline Dart paths
--     and surfaced via `XpCalculator.computeSetXp`).
--   * `tasks/rpg-xp-simulation.py` — `VOLUME_EXPONENT`, `WEEKLY_CAP_SETS`,
--     `OVER_CAP_MULTIPLIER` promoted from provisional `_CALIBRATION_*`
--     overrides to canonical; the override scaffolding deleted; per-slug
--     T4 deltas baked into `DIFFICULTY_MULT_BY_SLUG`.
--   * `test/fixtures/rpg_xp_fixtures.json` — regenerated from the new
--     canonical sim values via
--     `python test/fixtures/generate_rpg_fixtures.py`.
--   * Framework doc `docs/xp-difficulty-framework.md` — T4 row
--     tier_mult cell + Phase 24d calibration note.
--   * Launch baseline `docs/xp-balance-baseline.md` — PROVISIONAL markers
--     dropped, propagation section appended.
--
-- ## What's NOT in this migration
--
--   * No schema changes (column shapes preserved).
--   * No retroactive xp_events replay.
--   * No grant changes (functions retain SECURITY DEFINER + GRANT EXECUTE
--     TO authenticated set in 00040 / 00054 / 00057).
--   * The wrapper `backfill_rpg_v1(uuid, int)` is intentionally NOT
--     replaced — it manages cursor + checkpoint and delegates ALL XP math
--     to `_rpg_backfill_chunk`. Same rationale as 00054 / 00057.
--   * No migration of `exercise_peak_loads` — peaks are entered-weight only,
--     unaffected by either constant or T4-delta changes.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- PART A — UPDATE 28 T4 slugs (-0.05 difficulty_mult)
-- ---------------------------------------------------------------------------
--
-- One UPDATE statement covers all 28 slugs. `round(..., 2)` matches the
-- numeric(4,2) column scale and keeps the audit numbers human-readable
-- (e.g. 0.97 - 0.05 = 0.92, not 0.92000004 from float drift).
--
-- The 28-slug list MUST stay byte-identical to the canonical
-- `_CALIBRATION_T4_SLUGS` set in `tasks/rpg-xp-simulation.py` (now baked
-- into `DIFFICULTY_MULT_BY_SLUG` rather than tracked as a separate
-- `_CALIBRATION_T4_SLUGS` constant — that override scaffolding has been
-- deleted as part of this propagation).
-- ---------------------------------------------------------------------------

UPDATE public.exercises
SET difficulty_mult = round(difficulty_mult - 0.05, 2)
WHERE slug IN (
  -- 00053 (23 slugs) — every `-- T4 + N sec → 0.95±0.04` row
  'machine_chest_press',     -- 0.99 → 0.94
  'cable_chest_press',       -- 0.99 → 0.94
  'cable_crossover',         -- 0.99 → 0.94
  'cable_row',               -- 0.99 → 0.94
  'machine_row',             -- 0.99 → 0.94
  'lat_pulldown',            -- 0.99 → 0.94
  'close_grip_lat_pulldown', -- 0.99 → 0.94
  'face_pull',               -- 0.99 → 0.94
  'leg_press',               -- 0.97 → 0.92
  'single_leg_leg_press',    -- 0.97 → 0.92
  'reverse_hyperextension',  -- 0.99 → 0.94
  'cable_glute_kickback',    -- 0.97 → 0.92
  'cable_pull_through',      -- 0.99 → 0.94
  'band_squat',              -- 0.97 → 0.92
  'machine_shoulder_press',  -- 0.99 → 0.94
  'cable_face_pull',         -- 0.99 → 0.94
  'band_face_pull',          -- 0.99 → 0.94
  'upright_row',             -- 0.99 → 0.94
  'tricep_pushdown',         -- 0.97 → 0.92
  'rope_pushdown',           -- 0.97 → 0.92
  'cable_crunch',            -- 0.95 → 0.90
  'cable_woodchop',          -- 0.99 → 0.94
  'pallof_press',            -- 0.97 → 0.92
  -- 00055 (5 slugs) — Phase 24b T4 additions
  'belt_squat',              -- 0.97 → 0.92
  'pendulum_squat',          -- 0.97 → 0.92
  'glute_ham_raise',         -- 0.99 → 0.94
  'cable_pullover',          -- 1.01 → 0.96
  'cable_overhead_extension' -- 0.97 → 0.92
);

-- DO-block sanity assert: all 28 T4 slugs landed at <= 0.96 difficulty_mult.
-- Pre-migration values ranged 0.95-1.01; post -0.05 they land 0.90-0.96, all
-- comfortably above the framework floor (0.85). If this trips, either a
-- migration (re-)applied the delta twice (see ON CONFLICT semantics — but we
-- use bare UPDATE so this can't happen), or a slug from the list isn't
-- present in the table (drift between sim list and 00053/00055).
DO $$
DECLARE
  v_match int;
  v_total int;
BEGIN
  SELECT count(*) INTO v_total
  FROM public.exercises
  WHERE slug IN (
    'machine_chest_press', 'cable_chest_press', 'cable_crossover',
    'cable_row', 'machine_row', 'lat_pulldown', 'close_grip_lat_pulldown',
    'face_pull', 'leg_press', 'single_leg_leg_press',
    'reverse_hyperextension', 'cable_glute_kickback', 'cable_pull_through',
    'band_squat', 'machine_shoulder_press', 'cable_face_pull',
    'band_face_pull', 'upright_row', 'tricep_pushdown', 'rope_pushdown',
    'cable_crunch', 'cable_woodchop', 'pallof_press',
    'belt_squat', 'pendulum_squat', 'glute_ham_raise',
    'cable_pullover', 'cable_overhead_extension'
  );
  IF v_total <> 28 THEN
    RAISE EXCEPTION
      '00059 PART A: expected 28 T4 slugs in exercises table, found % — '
      'the canonical T4 list is out of sync with 00053/00055.', v_total;
  END IF;

  SELECT count(*) INTO v_match
  FROM public.exercises
  WHERE slug IN (
    'machine_chest_press', 'cable_chest_press', 'cable_crossover',
    'cable_row', 'machine_row', 'lat_pulldown', 'close_grip_lat_pulldown',
    'face_pull', 'leg_press', 'single_leg_leg_press',
    'reverse_hyperextension', 'cable_glute_kickback', 'cable_pull_through',
    'band_squat', 'machine_shoulder_press', 'cable_face_pull',
    'band_face_pull', 'upright_row', 'tricep_pushdown', 'rope_pushdown',
    'cable_crunch', 'cable_woodchop', 'pallof_press',
    'belt_squat', 'pendulum_squat', 'glute_ham_raise',
    'cable_pullover', 'cable_overhead_extension'
  ) AND difficulty_mult <= 0.96;
  IF v_match <> 28 THEN
    RAISE EXCEPTION
      '00059 PART A: expected all 28 T4 slugs at difficulty_mult <= 0.96, '
      'got % — Phase 24d delta did not apply uniformly.', v_match;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- PART B — Update rpg_base_xp helper (volume_exponent 0.65 → 0.60)
-- ---------------------------------------------------------------------------
--
-- The helper is consumed by all three RPCs below; one update covers them
-- all. Signature unchanged so nothing in callers needs to change.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpg_base_xp(p_weight numeric, p_reps int)
RETURNS numeric
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
AS $$
DECLARE
  v_vl numeric;
BEGIN
  IF p_reps IS NULL OR p_reps < 1 THEN
    v_vl := 1.0;
  ELSE
    v_vl := GREATEST(1.0, COALESCE(p_weight, 0) * p_reps);
  END IF;
  -- Phase 24d: 0.65 → 0.60. Mirrors `XpCalculator.volumeExponent` and
  -- `tasks/rpg-xp-simulation.py::VOLUME_EXPONENT`.
  RETURN power(v_vl, 0.60);
END;
$$;

-- ---------------------------------------------------------------------------
-- PART C — record_set_xp: cap constants (20 → 15, 0.5 → 0.3)
--
-- Diff vs 00057:
--   * Single-line cap-mult update: `>= 20 THEN 0.5` → `>= 15 THEN 0.3`.
--   * No other change. All Phase 24a / 24b / 24c logic preserved.
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
  v_weight       numeric;
  v_reps         int;
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
  v_bodyweight_kg        numeric(5,2);
  v_uses_bodyweight_load boolean;
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
BEGIN
  SELECT
    we.exercise_id, we.workout_id, w.user_id,
    s.weight, s.reps, s.is_completed,
    COALESCE(s.set_type, 'working')
  INTO
    v_exercise_id, v_workout_id, v_user_id, v_weight, v_reps,
    v_set_completed, v_set_type
  FROM public.sets s
  JOIN public.workout_exercises we ON we.id = s.workout_exercise_id
  JOIN public.workouts w ON w.id = we.workout_id
  WHERE s.id = p_set_id;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'record_set_xp: set % not found', p_set_id
      USING ERRCODE = 'P0002';
  END IF;
  IF NOT v_set_completed OR v_set_type <> 'working' THEN
    RETURN;
  END IF;
  IF v_reps IS NULL OR v_reps < 1 THEN
    RETURN;
  END IF;

  SELECT id INTO v_existing_event_id
  FROM public.xp_events
  WHERE user_id = v_user_id AND set_id = p_set_id
  LIMIT 1;
  IF v_existing_event_id IS NOT NULL THEN
    RETURN;
  END IF;

  SELECT bodyweight_kg INTO v_bodyweight_kg
  FROM public.profiles
  WHERE id = v_user_id;

  SELECT xp_attribution, primary_muscle_group::text,
         COALESCE(difficulty_mult, 1.0),
         COALESCE(uses_bodyweight_load, FALSE)
  INTO v_attribution, v_primary_muscle, v_difficulty_mult,
       v_uses_bodyweight_load
  FROM (
    SELECT xp_attribution, muscle_group AS primary_muscle_group,
           difficulty_mult, uses_bodyweight_load
    FROM public.exercises WHERE id = v_exercise_id
  ) src;

  IF v_attribution IS NULL OR v_attribution = 'null'::jsonb OR v_attribution = '{}'::jsonb THEN
    v_attribution := jsonb_build_object(v_primary_muscle, 1.0);
  END IF;

  SELECT peak_weight INTO v_peak
  FROM public.exercise_peak_loads
  WHERE user_id = v_user_id AND exercise_id = v_exercise_id;
  IF v_peak IS NULL THEN
    v_peak := 0;
  END IF;

  v_effective_weight := CASE
    WHEN v_uses_bodyweight_load THEN
      COALESCE(v_weight, 0) + COALESCE(v_bodyweight_kg, 0)
    ELSE
      COALESCE(v_weight, 0)
  END;

  -- Phase 24d: rpg_base_xp now applies VOLUME_EXPONENT = 0.60 (was 0.65 in
  -- 00040). Helper signature unchanged.
  v_base := public.rpg_base_xp(v_effective_weight, v_reps);
  v_intensity := public.rpg_intensity_for_reps(v_reps);
  IF v_weight > v_peak THEN
    v_peak := v_weight;
  END IF;
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
  IF v_event_id IS NULL THEN
    RETURN;
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
    -- Phase 24d: WEEKLY_CAP_SETS 20 → 15, OVER_CAP_MULTIPLIER 0.5 → 0.3.
    v_cap     := CASE WHEN v_weekly_vol >= 15 THEN 0.3 ELSE 1.0 END;

    v_xp_for_bp := v_base * v_intensity * v_strength * v_novelty * v_cap
                   * v_difficulty_mult * v_attr_share;
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

  v_event_payload := jsonb_build_object(
    'volume_load',    GREATEST(1.0, COALESCE(v_effective_weight, 0) * v_reps),
    'base_xp',        v_base,
    'intensity_mult', v_intensity,
    'strength_mult',  v_strength,
    'difficulty_mult', v_difficulty_mult,
    'effective_load',  round(v_effective_weight::numeric, 4),
    'bodyweight_used', v_uses_bodyweight_load,
    'set_xp',         v_set_xp
  );

  UPDATE public.xp_events
  SET payload     = v_event_payload,
      attribution = v_event_attribution,
      total_xp    = v_set_xp
  WHERE id = v_event_id;

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

  RETURN;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_set_xp(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.record_set_xp(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- PART D — record_session_xp_batch: cap constants (20 → 15, 0.5 → 0.3)
--
-- Diff vs 00057:
--   * Single-line cap-mult update inside the per-bp inner loop.
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
  v_bodyweight_kg     numeric(5,2);
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
  v_event_ids        uuid[]        := ARRAY[]::uuid[];
  v_event_set_ids    uuid[]        := ARRAY[]::uuid[];
  v_event_payloads   jsonb[]       := ARRAY[]::jsonb[];
  v_event_attrs      jsonb[]       := ARRAY[]::jsonb[];
  v_event_totals     numeric[]     := ARRAY[]::numeric[];
  v_event_id         uuid;
BEGIN
  SELECT user_id INTO v_user_id FROM public.workouts WHERE id = p_workout_id;
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'record_session_xp_batch: workout % not found', p_workout_id
      USING ERRCODE = 'P0002';
  END IF;

  SELECT bodyweight_kg INTO v_bodyweight_kg
  FROM public.profiles
  WHERE id = v_user_id;
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

  WITH agg AS (
    SELECT
      kv.key            AS bp_key,
      SUM(kv.value::float8) AS bp_sum
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
  INTO
    v_weekly_chest, v_weekly_back, v_weekly_legs,
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
      we.exercise_id AS exercise_id,
      ex.xp_attribution AS xp_attribution,
      ex.muscle_group::text AS primary_muscle,
      COALESCE(ex.difficulty_mult, 1.0) AS difficulty_mult,
      COALESCE(ex.uses_bodyweight_load, FALSE) AS uses_bodyweight_load
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
    IF v_attribution IS NULL
       OR v_attribution = 'null'::jsonb
       OR v_attribution = '{}'::jsonb THEN
      v_attribution := jsonb_build_object(v_set_record.primary_muscle, 1.0);
    END IF;

    v_peak := COALESCE(
                (v_peaks_map ->> v_set_record.exercise_id::text)::numeric,
                0
              );
    IF v_set_record.weight > v_peak THEN
      v_peak := v_set_record.weight;
      v_peaks_map := v_peaks_map
        || jsonb_build_object(v_set_record.exercise_id::text, v_peak);
    END IF;

    v_effective_weight_f := CASE
      WHEN v_set_record.uses_bodyweight_load THEN
        COALESCE(v_set_record.weight, 0)::float8 + v_bodyweight_f
      ELSE
        COALESCE(v_set_record.weight, 0)::float8
    END;

    -- Phase 24d: rpg_base_xp now applies VOLUME_EXPONENT = 0.60.
    v_base_f      := public.rpg_base_xp(v_effective_weight_f::numeric, v_set_record.reps)::float8;
    v_intensity_f := public.rpg_intensity_for_reps(v_set_record.reps)::float8;
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
      -- Phase 24d: WEEKLY_CAP_SETS 20 → 15, OVER_CAP_MULTIPLIER 0.5 → 0.3.
      v_cap_f     := CASE WHEN v_weekly_vol[v_bp_idx] >= 15 THEN 0.3 ELSE 1.0 END;

      v_xp_for_bp_f := v_base_f * v_intensity_f * v_strength_f
                       * v_novelty_f * v_cap_f * v_difficulty_mult_f
                       * v_attr_share;

      v_set_xp_f := v_set_xp_f + v_xp_for_bp_f;
      v_event_attribution := v_event_attribution
        || jsonb_build_object(v_attr_key, round(v_xp_for_bp_f::numeric, 4));

      v_session_vol[v_bp_idx] := v_session_vol[v_bp_idx] + v_xp_for_bp_f;
      v_weekly_vol[v_bp_idx]  := v_weekly_vol[v_bp_idx]  + v_xp_for_bp_f;
      v_bp_total[v_bp_idx]    := v_bp_total[v_bp_idx]    + v_xp_for_bp_f;
    END LOOP;

    v_event_payload := jsonb_build_object(
      'volume_load',
        GREATEST(1.0, v_effective_weight_f * v_set_record.reps),
      'base_xp',         round(v_base_f::numeric,             4),
      'intensity_mult',  round(v_intensity_f::numeric,        4),
      'strength_mult',   round(v_strength_f::numeric,         4),
      'difficulty_mult', round(v_difficulty_mult_f::numeric,  4),
      'effective_load',  round(v_effective_weight_f::numeric, 4),
      'bodyweight_used', v_set_record.uses_bodyweight_load,
      'set_xp',          round(v_set_xp_f::numeric,           4)
    );

    v_event_id := gen_random_uuid();
    v_event_ids      := v_event_ids      || v_event_id;
    v_event_set_ids  := v_event_set_ids  || v_set_record.set_id;
    v_event_payloads := v_event_payloads || v_event_payload;
    v_event_attrs    := v_event_attrs    || v_event_attribution;
    v_event_totals   := v_event_totals   || round(v_set_xp_f::numeric, 4);
  END LOOP;

  IF array_length(v_event_ids, 1) IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.xp_events (
    id, user_id, event_type, set_id, session_id,
    occurred_at, payload, attribution, total_xp, created_at
  )
  SELECT
    eid, v_user_id, 'set', sid, p_workout_id,
    v_now, pld, attr, tot, v_now
  FROM unnest(
    v_event_ids,
    v_event_set_ids,
    v_event_payloads,
    v_event_attrs,
    v_event_totals
  ) AS u(eid, sid, pld, attr, tot)
  ON CONFLICT (user_id, set_id) WHERE set_id IS NOT NULL DO NOTHING;

  INSERT INTO public.body_part_progress AS bpp (
    user_id, body_part, total_xp, rank,
    vitality_ewma, vitality_peak, last_event_at, updated_at
  )
  SELECT
    v_user_id,
    bp_token,
    bp_xp,
    public.rpg_rank_for_xp(bp_xp),
    0, 0, v_now, v_now
  FROM (
    SELECT
      CASE ord
        WHEN 1 THEN 'chest'
        WHEN 2 THEN 'back'
        WHEN 3 THEN 'legs'
        WHEN 4 THEN 'shoulders'
        WHEN 5 THEN 'arms'
        WHEN 6 THEN 'core'
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

  WITH per_set AS (
    SELECT
      we.exercise_id,
      s.weight,
      s.reps
    FROM public.sets s
    JOIN public.workout_exercises we ON we.id = s.workout_exercise_id
    WHERE we.workout_id = p_workout_id
      AND s.is_completed = TRUE
      AND COALESCE(s.set_type, 'working') = 'working'
      AND s.reps IS NOT NULL AND s.reps >= 1
      AND s.weight > 0
  ),
  per_exercise AS (
    SELECT DISTINCT ON (exercise_id)
      exercise_id,
      weight     AS peak_weight,
      reps       AS peak_reps
    FROM per_set
    ORDER BY exercise_id, weight DESC, reps DESC
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
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_session_xp_batch(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.record_session_xp_batch(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- PART E — _rpg_backfill_chunk: cap constants (20 → 15, 0.5 → 0.3)
--
-- Diff vs 00057:
--   * Single-line cap-mult update inside the per-bp inner loop.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._rpg_backfill_chunk(p_user_id uuid, p_chunk_size int)
RETURNS TABLE (
  processed     bigint,
  visited       bigint,
  last_set_id   uuid,
  last_set_ts   timestamptz
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
  v_bodyweight_kg    numeric(5,2);
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

  SELECT bodyweight_kg INTO v_bodyweight_kg
  FROM public.profiles
  WHERE id = p_user_id;

  FOR r_set IN
    SELECT
      s.id            AS set_id,
      s.workout_exercise_id,
      we.exercise_id,
      we.workout_id,
      s.weight,
      s.reps,
      s.is_completed,
      COALESCE(s.set_type, 'working') AS set_type,
      w.started_at    AS occurred_at,
      ex.muscle_group::text AS primary_muscle,
      ex.xp_attribution,
      COALESCE(ex.difficulty_mult, 1.0) AS difficulty_mult,
      COALESCE(ex.uses_bodyweight_load, FALSE) AS uses_bodyweight_load
    FROM public.sets s
    JOIN public.workout_exercises we ON we.id = s.workout_exercise_id
    JOIN public.workouts w           ON w.id = we.workout_id
    JOIN public.exercises ex         ON ex.id = we.exercise_id
    WHERE w.user_id = p_user_id
      AND w.finished_at IS NOT NULL
      AND s.is_completed = TRUE
      AND COALESCE(s.set_type, 'working') = 'working'
      AND s.reps IS NOT NULL AND s.reps >= 1
      AND (
        v_cursor_ts IS NULL
        OR (w.started_at, s.id) > (v_cursor_ts, v_cursor_id)
      )
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
        COALESCE(r_set.weight, 0) + COALESCE(v_bodyweight_kg, 0)
      ELSE
        COALESCE(r_set.weight, 0)
    END;

    -- Phase 24d: rpg_base_xp now applies VOLUME_EXPONENT = 0.60.
    v_base      := public.rpg_base_xp(v_effective_weight, r_set.reps);
    v_intensity := public.rpg_intensity_for_reps(r_set.reps);
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
      -- Phase 24d: WEEKLY_CAP_SETS 20 → 15, OVER_CAP_MULTIPLIER 0.5 → 0.3.
      v_cap     := CASE WHEN v_weekly_vol >= 15 THEN 0.3 ELSE 1.0 END;

      v_xp_for_bp := v_base * v_intensity * v_strength * v_novelty * v_cap
                     * v_difficulty_mult * v_attr_share;
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
      'volume_load',    GREATEST(1.0, COALESCE(v_effective_weight, 0) * r_set.reps),
      'base_xp',        v_base,
      'intensity_mult', v_intensity,
      'strength_mult',  v_strength,
      'difficulty_mult', v_difficulty_mult,
      'effective_load',  round(v_effective_weight::numeric, 4),
      'bodyweight_used', r_set.uses_bodyweight_load,
      'set_xp',         v_set_xp
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
-- _rpg_backfill_chunk is intentionally NOT granted to authenticated — only
-- the wrapper `backfill_rpg_v1` is callable by clients.

COMMIT;

NOTIFY pgrst, 'reload schema';
