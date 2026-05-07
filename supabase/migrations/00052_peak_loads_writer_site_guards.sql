-- ============================================================================
-- 00052 — exercise_peak_loads writer-site guards (legacy writers)
--
-- ## What this does
--
-- CREATE OR REPLACE FUNCTION for the two legacy `exercise_peak_loads` writers
-- in 00040, adding an explicit `IF weight > 0 THEN ... END IF` wrap around
-- each unguarded INSERT:
--   * `record_set_xp(p_set_id uuid)`               — line 9 / step 9 of the
--                                                    function (peak_loads UPSERT)
--   * `_rpg_backfill_chunk(p_user_id uuid, p_chunk_size int)` — inside the
--                                                    set-replay loop
--
-- The function bodies are otherwise identical to their 00040 originals — the
-- ONLY behavioral diff is the `IF weight > 0` wrap. No new params, no
-- changed return shape, no recomputed math.
--
-- ## Why this exists (rationale, NOT correctness)
--
-- Migration 00051 installed a BEFORE-INSERT trigger
-- (`guard_exercise_peak_loads_weight()`) that silently drops any
-- `exercise_peak_loads` row with `peak_weight <= 0`. That trigger absorbs
-- every writer's bodyweight-set INSERT (where `weight = 0`) regardless of
-- whether the writer guards explicitly.
--
-- Migration 00050 added an explicit `AND s.weight > 0` filter to the modern
-- `record_session_xp_batch` writer's `per_set` CTE — so its peak_loads
-- INSERT can never see a zero-weight row. That writer is self-evidently
-- correct from its own source.
--
-- The two LEGACY writers — `record_set_xp` (per-set, diagnostic-only after
-- 00050) and `_rpg_backfill_chunk` (used by `runRetroBackfill`) — still emit
-- INSERT statements that include zero-weight rows. The trigger absorbs them
-- silently, so the bug doesn't surface in production. But:
--
--   1. **Reader's surprise.** Anyone debugging `record_set_xp` or the
--      backfill loop will see the unguarded INSERT and wonder why
--      bodyweight sets work. The trigger is invisible at the function
--      source level.
--   2. **Defense in depth at both layers.** The trigger is the architectural
--      backstop, but the writer-site guard is the cheap second layer. If
--      the trigger ever gets dropped (intentionally or as collateral in a
--      future cleanup migration), the writer site would silently break
--      again.
--   3. **Single pattern across writers.** `record_session_xp_batch` already
--      has the explicit `AND weight > 0` filter; mirroring that pattern in
--      both legacy writers makes the codebase behave the same way at
--      every entry point.
--
-- This is a clean-code migration, not a correctness fix. The trigger from
-- 00051 stays in place as the architectural backstop — the writer-site
-- guards are additive defense-in-depth, not a replacement.
--
-- ## What's NOT in this migration
--
--   * No schema changes (no new columns, no new constraints, no new tables).
--   * No new permissions / RLS policy changes — both functions retain the
--     same SECURITY DEFINER + GRANT EXECUTE TO authenticated set in 00040.
--   * No change to `record_session_xp_batch` (already guarded in 00050).
--   * No drop of the BEFORE-INSERT trigger from 00051. The two layers
--     coexist by design.
--
-- ## Idempotency
--
-- `CREATE OR REPLACE FUNCTION` is idempotent — re-running this migration is
-- a no-op against a database that already has the post-00052 function
-- bodies. No data migration runs; pre-existing peak_loads rows are
-- untouched.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- record_set_xp — per-set XP RPC (D1)
--
-- Diff vs 00040: the `INSERT INTO public.exercise_peak_loads ...` at the end
-- of the function (step 9) is now wrapped in `IF v_weight > 0 THEN ... END
-- IF`. Everything else is verbatim.
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
  v_event_attr_each text;
  v_now          timestamptz := now();
  v_primary_muscle text;
BEGIN
  -- 1. Resolve set → exercise, workout, user, weight, reps
  SELECT
    we.exercise_id,
    we.workout_id,
    w.user_id,
    s.weight,
    s.reps,
    s.is_completed,
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

  -- 2. Resolve attribution map
  SELECT xp_attribution, primary_muscle_group::text
  INTO v_attribution, v_primary_muscle
  FROM (
    SELECT xp_attribution, muscle_group AS primary_muscle_group
    FROM public.exercises
    WHERE id = v_exercise_id
  ) src;

  IF v_attribution IS NULL OR v_attribution = 'null'::jsonb OR v_attribution = '{}'::jsonb THEN
    v_attribution := jsonb_build_object(v_primary_muscle, 1.0);
  END IF;

  -- 3. Fetch peak_load
  SELECT peak_weight INTO v_peak
  FROM public.exercise_peak_loads
  WHERE user_id = v_user_id AND exercise_id = v_exercise_id;

  IF v_peak IS NULL THEN
    v_peak := 0;
  END IF;

  -- 4. Compute base + intensity + strength
  v_base := public.rpg_base_xp(v_weight, v_reps);
  v_intensity := public.rpg_intensity_for_reps(v_reps);
  IF v_weight > v_peak THEN
    v_peak := v_weight;
  END IF;
  v_strength := public.rpg_strength_mult(v_weight, v_peak);

  -- 5. Insert xp_events row first
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

  -- 6. For each body part: compute set_xp_for_bp, advance body_part_progress.
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
    v_cap     := CASE WHEN v_weekly_vol >= 20 THEN 0.5 ELSE 1.0 END;

    v_xp_for_bp := v_base * v_intensity * v_strength * v_novelty * v_cap * v_attr_share;
    v_set_xp := v_set_xp + v_xp_for_bp;
    v_event_attribution := v_event_attribution
      || jsonb_build_object(v_attr_key, v_xp_for_bp);

    -- 7. UPSERT body_part_progress
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

  -- 8. Build payload + finalize xp_events row.
  v_event_payload := jsonb_build_object(
    'volume_load',   GREATEST(1.0, COALESCE(v_weight, 0) * v_reps),
    'base_xp',       v_base,
    'intensity_mult', v_intensity,
    'strength_mult', v_strength,
    'set_xp',        v_set_xp
  );

  UPDATE public.xp_events
  SET payload     = v_event_payload,
      attribution = v_event_attribution,
      total_xp    = v_set_xp
  WHERE id = v_event_id;

  -- 9. UPSERT exercise_peak_loads if weight advanced.
  --
  -- 00052 GUARD: the `IF v_weight > 0` wrap around the INSERT is the new
  -- writer-site guard. Bodyweight sets (weight = 0) skip the INSERT
  -- entirely. The 00051 BEFORE-INSERT trigger remains in place as the
  -- architectural backstop, but this writer-site guard makes the function
  -- self-evidently correct on read — anyone scanning the body sees that
  -- zero-weight sets are intentionally not recorded as peaks.
  --
  -- `v_weight` is set in step 1 from `s.weight` and is read-only after
  -- that point (step 4 reads it; step 4 reassigns `v_peak`, NOT
  -- `v_weight`). The guard variable is therefore the same value the
  -- function used throughout — no stale-read risk.
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
-- _rpg_backfill_chunk — historical replay chunk (D2 backfill)
--
-- Diff vs 00040: the `INSERT INTO public.exercise_peak_loads ...` at the
-- bottom of the per-set loop is now wrapped in `IF r_set.weight > 0 THEN
-- ... END IF`. Everything else is verbatim.
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
      ex.xp_attribution
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

    v_base      := public.rpg_base_xp(r_set.weight, r_set.reps);
    v_intensity := public.rpg_intensity_for_reps(r_set.reps);
    v_strength  := public.rpg_strength_mult(r_set.weight, v_peak);

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
      v_cap     := CASE WHEN v_weekly_vol >= 20 THEN 0.5 ELSE 1.0 END;

      v_xp_for_bp := v_base * v_intensity * v_strength * v_novelty * v_cap * v_attr_share;
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
      'volume_load',   GREATEST(1.0, COALESCE(r_set.weight, 0) * r_set.reps),
      'base_xp',       v_base,
      'intensity_mult', v_intensity,
      'strength_mult', v_strength,
      'set_xp',        v_set_xp
    );

    UPDATE public.xp_events
    SET payload     = v_event_payload,
        attribution = v_event_attribution,
        total_xp    = v_set_xp
    WHERE id = v_event_id;

    -- Peak loads
    --
    -- 00052 GUARD: bodyweight sets (weight = 0) skip the peak_loads INSERT
    -- entirely. Same reasoning as the wrap in `record_set_xp` above —
    -- writer-site guard makes the function self-evidently correct on read.
    -- The 00051 BEFORE-INSERT trigger continues to act as the architectural
    -- backstop.
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
-- the wrapper function `backfill_rpg_v1` (which gates on auth + advisory
-- lock + checkpoint bookkeeping) is callable by clients. Mirrors the
-- intentional grant omission in migration 00040; if you re-add `GRANT TO
-- authenticated` here, clients can bypass the wrapper's safety guards.
