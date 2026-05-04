-- =============================================================================
-- 00050_save_workout_skip_zero_weight_peak.sql
-- =============================================================================
--
-- Bugfix: bodyweight workouts (all sets weight = 0) crashed `save_workout` with
--
--   PostgrestException code=23514:
--     new row for relation "exercise_peak_loads"
--     violates check constraint "exercise_peak_loads_peak_weight_check"
--
-- ROOT CAUSE
-- ----------
-- `exercise_peak_loads.peak_weight` is `numeric(8,4) NOT NULL CHECK (peak_weight
-- > 0)` (see migration 00040 line 198). The `record_session_xp_batch` Step 7
-- aggregates per-exercise peak weight from this session's working sets and
-- UPSERTs into `exercise_peak_loads`.
--
-- The original Step 7 in 00040 (lines ~1163-1199) constructed the `per_set`
-- CTE WITHOUT filtering `weight > 0`. When all working-completed sets for a
-- given exercise have `weight = 0` (bodyweight exercises like Plank, Push-Up,
-- Pull-Up, Hanging Leg Raise, etc.), the per-exercise aggregator yields a row
-- with `peak_weight = 0`, the bulk INSERT fires, the CHECK constraint fails,
-- and the entire `save_workout` transaction rolls back.
--
-- Inconsistency proof: the same function's per-set in-memory peak update
-- (lines ~1017-1021) correctly gates on `v_set_record.weight > v_peak`, so a
-- weight=0 set does NOT advance `v_peaks_map`. The bulk UPSERT was a parallel
-- code path that was missing the same filter.
--
-- FIX
-- ---
-- Add `AND s.weight > 0` to the `per_set` CTE filter inside Step 7. This
-- prevents the zero-weight row from even being constructed; the per-exercise
-- aggregator never sees a zero winner; the UPSERT never fires for an
-- exercise whose only sets were bodyweight. `peak_weight` is meaningless for
-- bodyweight movements and `exercise_peak_loads` correctly has no row for
-- them — `strength_mult` defaults to 1.0 when peak is NULL/0 (see
-- `rpg_strength_mult` in 00040 lines 368-381).
--
-- Bodyweight workouts continue to earn XP through the per-set inserts of
-- `xp_events` and the `body_part_progress` UPSERT (Steps 5 + 6). Only the
-- `exercise_peak_loads` UPSERT (Step 7) is skipped, which is the correct
-- semantic: there is no peak to track when there is no external load.
--
-- SCOPE
-- -----
-- This migration changes ONE function: `record_session_xp_batch`. Everything
-- else in 00040 stays identical. The function body below is byte-for-byte
-- identical to the 00040 version EXCEPT for the single line in Step 7's
-- `per_set` CTE WHERE clause.
--
-- =============================================================================

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
  -- Hot-path math runs in float8 (IEEE 754 double, hardware-accelerated).
  -- Storage columns are numeric(14,4); we round-trip to numeric only at the
  -- boundary (when emitting xp_events rows + body_part_progress totals).
  -- Spec parity tolerance is 0.0001 — well inside float8's ~15 sig digits.
  -- See PERF NOTE in function header for the rationale.
  v_base_f           float8;
  v_intensity_f      float8;
  v_strength_f       float8;
  v_novelty_f        float8;
  v_cap_f            float8;
  v_xp_for_bp_f      float8;
  v_set_xp_f         float8;
  v_event_attribution jsonb;
  v_event_payload    jsonb;
  v_peaks_map        jsonb := '{}'::jsonb;
  -- Fixed-size 7-slot float8 accumulators indexed by the BodyPart enum
  -- (chest=1, back=2, legs=3, shoulders=4, arms=5, core=6, cardio=7).
  -- float8[] keeps per-set updates as native CPU operations instead of
  -- arbitrary-precision numeric math (~80x faster in the inner loop).
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
  -- Resolve workout owner. If the workout doesn't exist, this is a logic
  -- error in the caller (save_workout already validated existence).
  SELECT user_id INTO v_user_id FROM public.workouts WHERE id = p_workout_id;
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'record_session_xp_batch: workout % not found', p_workout_id
      USING ERRCODE = 'P0002';
  END IF;

  -- ── Step 2: pre-fetch peaks for every distinct exercise in this session.
  --   Single query, hashed into jsonb. Treated as a mutable in-memory map
  --   that gets advanced inline as PRs land within the batch (matching
  --   record_set_xp which advanced peak BEFORE strength_mult). Distinct
  --   exercise count is bounded (~25 per realistic session) and PR
  --   advancement is rare, so this small jsonb is not the hot path.
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

  -- ── Step 3: pre-fetch prior weekly volume per body_part from xp_events
  --   OUTSIDE this session in the past 7 days. The reversal pattern in
  --   save_workout already cascade-deleted xp_events for THIS session, so a
  --   simple WHERE session_id <> p_workout_id is enough — but we add it
  --   defensively in case the function is ever called outside the
  --   save_workout flow. Result writes directly into the v_weekly_vol[]
  --   slots so the inner loop never touches jsonb for this state.
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

  -- ── Step 4: iterate sets in (we.order, s.set_number) order. For each
  --   set, compute per-bp XP and accumulate into the bulk INSERT arrays
  --   plus the per-bp running totals.
  FOR v_set_record IN
    SELECT
      s.id           AS set_id,
      s.weight       AS weight,
      s.reps         AS reps,
      we.exercise_id AS exercise_id,
      ex.xp_attribution AS xp_attribution,
      ex.muscle_group::text AS primary_muscle
    FROM public.sets s
    JOIN public.workout_exercises we ON we.id = s.workout_exercise_id
    JOIN public.exercises ex          ON ex.id = we.exercise_id
    WHERE we.workout_id = p_workout_id
      AND s.is_completed = TRUE
      AND COALESCE(s.set_type, 'working') = 'working'
      AND s.reps IS NOT NULL AND s.reps >= 1
    ORDER BY we."order" ASC, s.set_number ASC
  LOOP
    -- Resolve attribution map (NULL → primary muscle group at 1.0 share)
    v_attribution := v_set_record.xp_attribution;
    IF v_attribution IS NULL
       OR v_attribution = 'null'::jsonb
       OR v_attribution = '{}'::jsonb THEN
      v_attribution := jsonb_build_object(v_set_record.primary_muscle, 1.0);
    END IF;

    -- Look up current peak for this exercise from the running map.
    v_peak := COALESCE(
                (v_peaks_map ->> v_set_record.exercise_id::text)::numeric,
                0
              );
    -- Advance peak BEFORE strength_mult — matches record_set_xp behavior.
    -- Peak advances are rare (only on PR) so the jsonb concat cost here is
    -- amortized down to near zero across a session.
    IF v_set_record.weight > v_peak THEN
      v_peak := v_set_record.weight;
      v_peaks_map := v_peaks_map
        || jsonb_build_object(v_set_record.exercise_id::text, v_peak);
    END IF;

    -- Helpers return numeric; cast to float8 once for the hot path. The
    -- helpers are called once per set, so their numeric cost is tiny
    -- (~3% of the budget). The inner per-bp loop is what we optimize.
    v_base_f      := public.rpg_base_xp(v_set_record.weight, v_set_record.reps)::float8;
    v_intensity_f := public.rpg_intensity_for_reps(v_set_record.reps)::float8;
    v_strength_f  := public.rpg_strength_mult(v_set_record.weight, v_peak)::float8;

    v_set_xp_f := 0;
    v_event_attribution := '{}'::jsonb;

    -- Per-body-part fan-out. Mirrors record_set_xp's inner loop exactly.
    -- All running state lives in fixed-size float8[] arrays — this loop
    -- does no jsonb concats nor numeric arithmetic on the hot path.
    FOR v_attr_key, v_attr_share IN
      SELECT key, (value::text)::float8 FROM jsonb_each_text(v_attribution)
    LOOP
      IF v_attr_share <= 0 THEN CONTINUE; END IF;

      -- Map body_part text → fixed array index (BodyPart enum). Unknown
      -- keys raise — see header doc, this is a data-integrity guardrail.
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
          USING ERRCODE = '22023'; -- invalid_parameter_value
      END IF;

      v_novelty_f := exp(- v_session_vol[v_bp_idx] / 15.0);
      v_cap_f     := CASE WHEN v_weekly_vol[v_bp_idx] >= 20 THEN 0.5 ELSE 1.0 END;

      v_xp_for_bp_f := v_base_f * v_intensity_f * v_strength_f
                       * v_novelty_f * v_cap_f * v_attr_share;

      v_set_xp_f := v_set_xp_f + v_xp_for_bp_f;
      -- Round at the storage boundary: per-bp xp lands in the event's
      -- attribution jsonb at numeric(14,4) precision (matches Phase 18a
      -- spec parity tolerance of 0.0001).
      v_event_attribution := v_event_attribution
        || jsonb_build_object(v_attr_key, round(v_xp_for_bp_f::numeric, 4));

      -- Advance running state. O(1) array slot updates — no allocations.
      -- We accumulate in float8 so the next iteration sees the full
      -- (un-rounded) volume — matches the original record_set_xp behavior
      -- which carried full numeric precision between sets.
      v_session_vol[v_bp_idx] := v_session_vol[v_bp_idx] + v_xp_for_bp_f;
      v_weekly_vol[v_bp_idx]  := v_weekly_vol[v_bp_idx]  + v_xp_for_bp_f;
      v_bp_total[v_bp_idx]    := v_bp_total[v_bp_idx]    + v_xp_for_bp_f;
    END LOOP;

    v_event_payload := jsonb_build_object(
      'volume_load',
        GREATEST(1.0, COALESCE(v_set_record.weight, 0) * v_set_record.reps),
      'base_xp',        round(v_base_f::numeric,      4),
      'intensity_mult', round(v_intensity_f::numeric, 4),
      'strength_mult',  round(v_strength_f::numeric,  4),
      'set_xp',         round(v_set_xp_f::numeric,    4)
    );

    v_event_id := gen_random_uuid();
    v_event_ids      := v_event_ids      || v_event_id;
    v_event_set_ids  := v_event_set_ids  || v_set_record.set_id;
    v_event_payloads := v_event_payloads || v_event_payload;
    v_event_attrs    := v_event_attrs    || v_event_attribution;
    v_event_totals   := v_event_totals   || round(v_set_xp_f::numeric, 4);
  END LOOP;

  -- Nothing to write? Bail (an all-non-working session, or a session with
  -- only zero-rep entries).
  IF array_length(v_event_ids, 1) IS NULL THEN
    RETURN;
  END IF;

  -- ── Step 5: bulk INSERT xp_events. UNNEST drives the row count; the
  --   ON CONFLICT clause defends against the (rare) concurrent retry where
  --   another writer beat us to a (user_id, set_id) pair.
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

  -- ── Step 6: UPSERT body_part_progress per body part. One statement,
  --   row count bounded by 7 (the body parts enum). rank recomputed on the
  --   new total via rpg_rank_for_xp. Source rows come from the fixed-size
  --   v_bp_total[] array unnested with ordinality so we can map back to
  --   the body_part text token.
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
      -- Round at the storage boundary; total_xp is numeric(14,4).
      round(bp_xp_f::numeric, 4) AS bp_xp
    FROM unnest(v_bp_total) WITH ORDINALITY AS u(bp_xp_f, ord)
    WHERE bp_xp_f > 0
  ) src
  ON CONFLICT (user_id, body_part) DO UPDATE SET
    total_xp     = bpp.total_xp + EXCLUDED.total_xp,
    rank         = public.rpg_rank_for_xp(bpp.total_xp + EXCLUDED.total_xp),
    last_event_at = v_now,
    updated_at   = v_now;

  -- ── Step 7: UPSERT exercise_peak_loads per advanced exercise. Computes
  --   per-exercise max(weight, max_reps_at_max_weight) from the batch,
  --   applies GREATEST against any prior peak in the conflict path.
  --
  -- BUGFIX (00050): added `AND s.weight > 0` to the per_set CTE filter so
  -- bodyweight exercises (every working set has weight = 0 — Plank, Push-Up,
  -- Pull-Up, Hanging Leg Raise, …) do NOT construct a per_exercise row. The
  -- target column `peak_weight numeric(8,4) NOT NULL CHECK (peak_weight > 0)`
  -- previously rejected the row at INSERT time and rolled the entire
  -- save_workout transaction back. peak_weight is meaningless for bodyweight
  -- movements (strength_mult defaults to 1.0 when peak is NULL/0), so the
  -- correct semantic is to not record a peak at all for those exercises.
  -- xp_events and body_part_progress (Steps 5 + 6) continue to apply — the
  -- bodyweight session still earns XP through the per-set inserts.
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
      AND s.weight > 0  -- exclude bodyweight: see BUGFIX note above
  ),
  per_exercise AS (
    -- max weight per exercise, plus the max reps at that max weight (so a
    -- new PR's peak_reps reflects the heaviest set, not the most-recent).
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
    -- Same guard as record_set_xp §9: only fire the update when the new
    -- weight strictly exceeds the existing peak. Skips the row entirely
    -- when peak didn't advance, keeping updated_at honest.
    peak_weight = EXCLUDED.peak_weight,
    peak_reps   = EXCLUDED.peak_reps,
    peak_date   = EXCLUDED.peak_date,
    updated_at  = v_now
  WHERE EXCLUDED.peak_weight > public.exercise_peak_loads.peak_weight;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_session_xp_batch(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.record_session_xp_batch(uuid) TO authenticated;
