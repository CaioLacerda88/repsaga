-- =============================================================================
-- 00079 — Phase 38c: cardio earning formula + est-VO₂max + strength→cardio
--                     cross-credit
--
-- ## What this does
--
--   1. ALTER `cardio_sessions` ADD computed columns `met`, `met_minutes`,
--      `est_met` (numeric, nullable) — the earning columns deferred by 00078.
--   2. ALTER `profiles` ADD `cardio_vo2max numeric(4,1)`,
--      `cardio_vo2max_updated_at timestamptz`, `date_of_birth date` (all NULL).
--      NO onboarding UI in this PR — the DOB-collection surface + LGPD consent
--      + existing-user backfill are a later task. Formula uses real age when
--      `date_of_birth` is present, AGE_FALLBACK=35 when NULL.
--   3. Pure PL/pgSQL cardio helpers (mirror `cardio-xp-simulation.py` +
--      `lib/features/rpg/domain/cardio_xp_calculator.dart` byte-for-byte; the
--      parity tests assert 1e-4 Dart↔Python and 0.01 SQL live-row↔Dart).
--   4. `record_cardio_session(p_workout_id uuid)` — ports `compute_session_xp`,
--      reusing `rpg_tier_diff_mult` + the rank curve VERBATIM. Cardio base =
--      `capped_met_min ^ 0.60` (NOT `rpg_base_xp` — different input domain).
--      Writes a cardio `xp_events` row per cardio session (distinct conflict
--      key: NO set_id, session_id=workout_id, cardio attribution) + a
--      `body_part_progress['cardio']` upsert at index 7. Recomputes + writes
--      back `profiles.cardio_vo2max` (best-of 42-day window). Estimate-only.
--   5. Cross-credit: derives a per-strength-session `est_met` from work
--      density (corrected §B band fn) and feeds `record_cardio_session` a
--      synthetic `kind='abs'` cardio contribution. STRICTLY one-directional —
--      it never touches the strength formula (00077 gate is structural).
--   6. Wires `record_cardio_session` into `save_workout`, AFTER the existing
--      `record_session_xp_batch` PERFORM, INSIDE the same transaction.
--
-- ## What this DELIBERATELY does NOT touch (that's Phase 38d)
--
-- Cardio stays OUT of `activeBodyParts` / `character_state`. The
-- `character_state` view (00040:312-322) + the per-batch character-level math
-- (00077:730-734) already restrict to the 6 strength body parts, so cardio XP
-- in `body_part_progress['cardio']` is STRUCTURALLY invisible to character
-- level. This migration adds nothing to those surfaces. Cardio XP is earnable
-- + verifiable in the DB, invisible in the UI, validated before the 38d flip.
--
-- ## Reversal / idempotency (BUG-RPG-001)
--
-- The cardio `xp_events` rows carry `session_id = p_workout_id` and a
-- `{"cardio": <xp>}` attribution. `save_workout`'s reversal block (00078:189-
-- 206) sums `xp_events.attribution` over ALL keys for the session and reverts
-- `body_part_progress`, so a cardio re-save reverts cleanly the same way the
-- strength path does. The cardio xp_events conflict key is
-- `(user_id, session_id, event_type='cardio_session', exercise_id)` so a
-- re-save replaces rather than duplicates (save_workout DELETEs the prior
-- cardio xp_events before re-running record_cardio_session; the partial unique
-- index `(user_id, session_id) WHERE set_id IS NULL AND event_type=
-- 'cardio_session'` is the idempotency backstop). Pinned by the integration
-- test.
--
-- ## Grants (cluster: supabase-cli-latest-grant-drift)
--
-- record_cardio_session: REVOKE FROM PUBLIC, anon; GRANT TO authenticated.
-- save_workout grants re-stated verbatim after the DROP+CREATE.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- PART A — schema: cardio_sessions earning columns + profiles VO₂/DOB columns
-- ---------------------------------------------------------------------------

ALTER TABLE public.cardio_sessions
  ADD COLUMN IF NOT EXISTS met         numeric NULL,
  ADD COLUMN IF NOT EXISTS met_minutes numeric NULL,
  ADD COLUMN IF NOT EXISTS est_met     numeric NULL;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS cardio_vo2max            numeric(4,1) NULL,
  ADD COLUMN IF NOT EXISTS cardio_vo2max_updated_at timestamptz  NULL,
  ADD COLUMN IF NOT EXISTS date_of_birth            date         NULL;

-- One cardio xp_events row per (user, session). The strength path keys on
-- (user_id, set_id) — cardio has no set_id, so it needs its own partial unique
-- index to back the ON CONFLICT in record_cardio_session. event_type pinned in
-- the predicate so this index never collides with any future NULL-set_id event
-- type.
CREATE UNIQUE INDEX IF NOT EXISTS xp_events_user_cardio_session_unique
  ON public.xp_events (user_id, session_id)
  WHERE set_id IS NULL AND event_type = 'cardio_session';

-- ---------------------------------------------------------------------------
-- PART B — cardio pure helpers (mirror the Dart/Python pure cores)
--
-- All IMMUTABLE PARALLEL SAFE, like the strength helpers. These are the THIRD
-- implementation of the cardio formula (Python sim = 1st, Dart calculator =
-- 2nd). If you change a constant here, change all three + regenerate the
-- fixture in the same PR.
-- ---------------------------------------------------------------------------

-- Shared piecewise-linear interpolation over (x, y) anchor arrays, clamped at
-- the ends. `p_xs` / `p_ys` are parallel, ascending in x.
CREATE OR REPLACE FUNCTION public.rpg_cardio_interp(
  p_xs numeric[], p_ys numeric[], p_x numeric
) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
AS $$
DECLARE
  n int := array_length(p_xs, 1);
  i int;
  x0 numeric; x1 numeric; y0 numeric; y1 numeric; t numeric;
BEGIN
  IF p_x <= p_xs[1] THEN RETURN p_ys[1]; END IF;
  IF p_x >= p_xs[n] THEN RETURN p_ys[n]; END IF;
  FOR i IN 1 .. n - 1 LOOP
    x0 := p_xs[i]; x1 := p_xs[i + 1];
    IF x0 <= p_x AND p_x <= x1 THEN
      y0 := p_ys[i]; y1 := p_ys[i + 1];
      t := (p_x - x0) / (x1 - x0);
      RETURN y0 + t * (y1 - y0);
    END IF;
  END LOOP;
  RETURN p_ys[n];
END;
$$;

-- intensity_mult(pct_vo2max) — INTENSITY_ANCHORS.
CREATE OR REPLACE FUNCTION public.rpg_cardio_intensity_mult(p_pct numeric)
RETURNS numeric
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
  SELECT public.rpg_cardio_interp(
    ARRAY[0.35, 0.50, 0.70, 0.85, 0.95, 1.05]::numeric[],
    ARRAY[0.05, 0.35, 0.75, 1.05, 1.35, 1.45]::numeric[],
    p_pct);
$$;

-- sustainable_fraction(duration_min) — _SUSTAIN_ANCHORS.
CREATE OR REPLACE FUNCTION public.rpg_cardio_sustainable_fraction(p_dur numeric)
RETURNS numeric
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
  SELECT public.rpg_cardio_interp(
    ARRAY[6, 15, 30, 45, 60, 90, 120, 180]::numeric[],
    ARRAY[1.00, 0.93, 0.88, 0.84, 0.80, 0.76, 0.74, 0.70]::numeric[],
    p_dur);
$$;

-- demonstrated_vo2(abs_met, duration_min), capped at 90.
CREATE OR REPLACE FUNCTION public.rpg_cardio_demonstrated_vo2(
  p_abs_met numeric, p_dur numeric
) RETURNS numeric
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
  SELECT LEAST(90.0,
    (p_abs_met * 3.5) / public.rpg_cardio_sustainable_fraction(p_dur));
$$;

-- modality_mult(modality), default 1.00.
CREATE OR REPLACE FUNCTION public.rpg_cardio_modality_mult(p_modality text)
RETURNS numeric
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
  SELECT CASE p_modality
    WHEN 'run'        THEN 1.00
    WHEN 'treadmill'  THEN 1.00
    WHEN 'row'        THEN 1.00
    WHEN 'swim'       THEN 1.00
    WHEN 'elliptical' THEN 0.97
    WHEN 'bike'       THEN 0.95
    WHEN 'walk'       THEN 0.95
    WHEN 'hiit'       THEN 1.05
    WHEN 'strength'   THEN 0.80
    WHEN 'circuit'    THEN 0.90
    ELSE 1.00
  END::numeric;
$$;

-- VO₂max → sex/age percentile. p_sex ∈ {'M','F'}. Mirrors vo2_to_percentile.
CREATE OR REPLACE FUNCTION public.rpg_cardio_vo2_to_percentile(
  p_vo2 numeric, p_age int, p_female boolean
) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
AS $$
DECLARE
  v_sex   text := CASE WHEN p_female THEN 'F' ELSE 'M' END;
  v_band  int  := GREATEST(20, LEAST(70, (p_age / 10) * 10));
  v_norms numeric[];
  v_xs    numeric[];
  v_ys    numeric[];
BEGIN
  v_norms := CASE v_sex || ':' || v_band
    WHEN 'M:20' THEN ARRAY[29.0,40.1,48.0,55.2,61.8,66.3]
    WHEN 'M:30' THEN ARRAY[27.2,35.9,42.4,49.2,56.5,59.8]
    WHEN 'M:40' THEN ARRAY[24.2,31.9,37.8,45.0,52.1,55.6]
    WHEN 'M:50' THEN ARRAY[20.9,27.1,32.6,39.7,45.6,50.7]
    WHEN 'M:60' THEN ARRAY[17.4,23.7,28.2,34.5,40.3,43.0]
    WHEN 'M:70' THEN ARRAY[16.3,20.4,24.4,30.4,36.6,39.7]
    WHEN 'F:20' THEN ARRAY[21.7,30.5,37.6,44.7,51.3,56.0]
    WHEN 'F:30' THEN ARRAY[19.0,25.3,30.2,36.1,41.4,45.8]
    WHEN 'F:40' THEN ARRAY[17.0,22.1,26.7,32.4,38.4,41.7]
    WHEN 'F:50' THEN ARRAY[16.0,19.9,23.4,27.6,32.0,35.9]
    WHEN 'F:60' THEN ARRAY[13.4,17.2,20.0,23.8,27.0,29.4]
    WHEN 'F:70' THEN ARRAY[13.1,15.6,18.3,20.8,23.1,24.1]
  END::numeric[];
  -- (0,0) + (vo2, pct) ascending + (90, 100).
  v_xs := ARRAY[0.0] || v_norms || ARRAY[90.0];
  v_ys := ARRAY[0.0, 5.0, 25.0, 50.0, 75.0, 90.0, 95.0, 100.0];
  RETURN public.rpg_cardio_interp(v_xs, v_ys, p_vo2);
END;
$$;

-- implied_cardio_tier(vo2, age, female) — percentile → tier [0,70].
CREATE OR REPLACE FUNCTION public.rpg_cardio_implied_tier(
  p_vo2 numeric, p_age int, p_female boolean
) RETURNS numeric
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
  SELECT public.rpg_cardio_interp(
    ARRAY[0, 5, 25, 50, 75, 90, 95, 99, 100]::numeric[],
    ARRAY[0, 5, 18, 25, 37, 50, 60, 68, 70]::numeric[],
    public.rpg_cardio_vo2_to_percentile(p_vo2, p_age, p_female));
$$;

-- nonexercise_seed_vo2(age, female) — p25 anchor of the (sex, band) norm.
CREATE OR REPLACE FUNCTION public.rpg_cardio_seed_vo2(
  p_age int, p_female boolean
) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
AS $$
DECLARE
  v_sex  text := CASE WHEN p_female THEN 'F' ELSE 'M' END;
  v_band int  := GREATEST(20, LEAST(70, (COALESCE(p_age, 35) / 10) * 10));
BEGIN
  RETURN CASE v_sex || ':' || v_band
    WHEN 'M:20' THEN 40.1 WHEN 'M:30' THEN 35.9 WHEN 'M:40' THEN 31.9
    WHEN 'M:50' THEN 27.1 WHEN 'M:60' THEN 23.7 WHEN 'M:70' THEN 20.4
    WHEN 'F:20' THEN 30.5 WHEN 'F:30' THEN 25.3 WHEN 'F:40' THEN 22.1
    WHEN 'F:50' THEN 19.9 WHEN 'F:60' THEN 17.2 WHEN 'F:70' THEN 15.6
  END::numeric;
END;
$$;

-- session_met_from_cardio_log(modality, distance_m, duration_s) → absolute MET.
CREATE OR REPLACE FUNCTION public.rpg_cardio_session_met(
  p_modality text, p_distance_m numeric, p_duration_s numeric
) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
AS $$
DECLARE
  v_v_per_min numeric;
  v_acsm      numeric;
BEGIN
  IF p_modality IN ('run', 'treadmill')
     AND p_distance_m IS NOT NULL AND p_distance_m > 0
     AND p_duration_s IS NOT NULL AND p_duration_s > 0 THEN
    v_v_per_min := p_distance_m / (p_duration_s / 60.0);
    v_acsm := 0.2 * v_v_per_min + 3.5;
    RETURN v_acsm / 3.5;
  END IF;
  RETURN CASE p_modality
    WHEN 'run'        THEN 9.8 WHEN 'treadmill'  THEN 9.8
    WHEN 'bike'       THEN 7.0 WHEN 'row'        THEN 8.5
    WHEN 'swim'       THEN 8.0 WHEN 'elliptical' THEN 7.0
    WHEN 'walk'       THEN 3.8 WHEN 'hiit'       THEN 11.0
    ELSE 3.5
  END::numeric;
END;
$$;

-- best_effort_vo2_from_pace(distance_m, duration_s, modality) → est-VO₂ or NULL.
CREATE OR REPLACE FUNCTION public.rpg_cardio_best_effort_vo2(
  p_distance_m numeric, p_duration_s numeric, p_modality text
) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
AS $$
DECLARE
  v_dur_min   numeric;
  v_v_per_min numeric;
  v_acsm      numeric;
BEGIN
  IF p_modality NOT IN ('run', 'treadmill') THEN RETURN NULL; END IF;
  IF p_distance_m IS NULL OR p_duration_s IS NULL
     OR p_distance_m <= 0 OR p_duration_s <= 0 THEN
    RETURN NULL;
  END IF;
  v_dur_min := p_duration_s / 60.0;
  v_v_per_min := p_distance_m / v_dur_min;
  v_acsm := 0.2 * v_v_per_min + 3.5;
  RETURN LEAST(90.0,
    v_acsm / public.rpg_cardio_sustainable_fraction(v_dur_min));
END;
$$;

-- slug → sim modality (the 5 default cardio slugs; user slugs → 'run' default
-- since the default-MET path then keys on it harmlessly via session_met).
CREATE OR REPLACE FUNCTION public.rpg_cardio_slug_to_modality(p_slug text)
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
  SELECT CASE p_slug
    WHEN 'treadmill'       THEN 'treadmill'
    WHEN 'rowing_machine'  THEN 'row'
    WHEN 'stationary_bike' THEN 'bike'
    WHEN 'jump_rope'       THEN 'hiit'
    WHEN 'elliptical'      THEN 'elliptical'
    ELSE 'run'
  END;
$$;

-- est_met_from_density(completed_sets, session_seconds, avg_rest) → MET band.
CREATE OR REPLACE FUNCTION public.rpg_cardio_est_met_from_density(
  p_completed_sets int, p_session_seconds numeric, p_avg_rest numeric
) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
AS $$
DECLARE
  v_spm numeric;
BEGIN
  IF p_completed_sets <= 0 OR p_session_seconds <= 0 THEN RETURN 3.5; END IF;
  v_spm := p_completed_sets / (p_session_seconds / 60.0);
  IF p_avg_rest <= 35 AND v_spm >= 0.50 THEN RETURN 8.0; END IF;
  IF p_avg_rest <= 75 AND v_spm >= 0.40 THEN RETURN 6.0; END IF;
  IF p_avg_rest <= 120 THEN RETURN 5.0; END IF;
  RETURN 3.5;
END;
$$;

-- ---------------------------------------------------------------------------
-- PART C — record_cardio_session(p_workout_id uuid)
--
-- Ports compute_session_xp. Reuses rpg_tier_diff_mult + the rank curve
-- verbatim. Cardio base = capped_met_min ^ 0.60.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.record_cardio_session(p_workout_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id    uuid;
  v_now        timestamptz := now();
  v_age        int;
  v_female     boolean;
  v_seed_vo2   numeric;
  v_vo2max     numeric;        -- standing estimate used for THIS session
  v_rank       int;
  v_total_xp   numeric;
  v_week_used  numeric := 0;   -- intensity-weighted MET-min this week

  -- per-entry locals
  v_rec          record;
  v_modality     text;
  v_abs_met      numeric;
  v_rel          numeric;
  v_met_min      numeric;
  v_imult        numeric;
  v_eff          numeric;
  v_remaining    numeric;
  v_under        numeric;
  v_over         numeric;
  v_capped       numeric;
  v_base         numeric;
  v_dvo2         numeric;
  v_tier         numeric;
  v_tdm          numeric;
  v_mod          numeric;
  v_xp           numeric;
  v_dur_min      numeric;

  -- cross-credit locals
  v_completed    int;
  v_session_secs numeric;
  v_avg_rest     numeric;
  v_cc_met       numeric;

  -- aggregate over the workout
  v_total_cardio_xp numeric := 0;
  v_event_id        uuid;
  v_payload         jsonb;
  v_attribution     jsonb;

  -- rolling estimate
  v_new_vo2max   numeric;
BEGIN
  SELECT user_id INTO v_user_id FROM public.workouts WHERE id = p_workout_id;
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'record_cardio_session: workout % not found', p_workout_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Profile: age (DOB→age, fallback 35), gender (NULL→male), standing VO₂max.
  SELECT
    CASE WHEN date_of_birth IS NULL THEN 35
         ELSE GREATEST(0,
           date_part('year', age(v_now::date, date_of_birth))::int) END,
    (gender = 'female'),
    cardio_vo2max
  INTO v_age, v_female, v_vo2max
  FROM public.profiles WHERE id = v_user_id;

  v_age    := COALESCE(v_age, 35);
  v_female := COALESCE(v_female, false);
  v_seed_vo2 := public.rpg_cardio_seed_vo2(v_age, v_female);
  -- A5: NULL standing estimate → use the cold-start seed for this session.
  v_vo2max := COALESCE(v_vo2max, v_seed_vo2);

  v_total_xp := COALESCE(
    (SELECT total_xp FROM public.body_part_progress
     WHERE user_id = v_user_id AND body_part = 'cardio'), 0);
  v_rank := public.rpg_rank_for_xp(v_total_xp);

  -- ===========================================================================
  -- Per logged cardio entry (kind='abs', session-resolved MET).
  -- ===========================================================================
  FOR v_rec IN
    SELECT cs.id,
           cs.duration_seconds,
           cs.distance_m,
           ex.slug AS slug
    FROM public.cardio_sessions cs
    JOIN public.exercises ex ON ex.id = cs.exercise_id
    WHERE cs.workout_id = p_workout_id
    ORDER BY cs.created_at, cs.id
  LOOP
    v_modality := public.rpg_cardio_slug_to_modality(v_rec.slug);
    v_dur_min  := v_rec.duration_seconds / 60.0;
    v_abs_met  := public.rpg_cardio_session_met(
                    v_modality, v_rec.distance_m, v_rec.duration_seconds);
    -- kind='abs': rel = MET×3.5/VO₂max, clamped ≤ 1.20.
    v_rel := LEAST(1.20, (v_abs_met * 3.5) / v_vo2max);
    v_met_min := v_abs_met * v_dur_min;
    v_imult := public.rpg_cardio_intensity_mult(v_rel);
    v_eff := v_met_min * v_imult;

    v_remaining := GREATEST(0.0, 2500.0 - v_week_used);
    v_under := LEAST(v_eff, v_remaining);
    v_over  := v_eff - v_under;
    v_capped := v_under + v_over * 0.30;
    v_week_used := v_week_used + v_eff;

    v_base := power(v_capped, 0.60);
    v_dvo2 := public.rpg_cardio_demonstrated_vo2(v_abs_met, v_dur_min);
    v_tier := public.rpg_cardio_implied_tier(v_dvo2, v_age, v_female);
    v_tdm  := public.rpg_tier_diff_mult(v_tier, v_rank::numeric);
    v_mod  := public.rpg_cardio_modality_mult(v_modality);
    v_xp   := v_base * v_tdm * v_mod * 3.5;

    -- Persist the computed columns on the cardio row.
    UPDATE public.cardio_sessions
    SET met = round(v_abs_met, 4),
        met_minutes = round(v_met_min, 4)
    WHERE id = v_rec.id;

    v_total_cardio_xp := v_total_cardio_xp + v_xp;
    -- Rank ticks up as cardio XP accrues within the session.
    v_rank := public.rpg_rank_for_xp(v_total_xp + v_total_cardio_xp);
  END LOOP;

  -- ===========================================================================
  -- Cross-credit (strength → cardio): one synthetic kind='abs' entry derived
  -- from the session's work density. One-directional; never touches strength.
  -- Only fires when the workout has completed working strength sets.
  -- ===========================================================================
  SELECT
    COUNT(*) FILTER (WHERE s.is_completed
                       AND COALESCE(s.set_type, 'working') = 'working'),
    COALESCE(
      SUM(COALESCE(we.rest_seconds, 90))
        FILTER (WHERE s.is_completed
                   AND COALESCE(s.set_type, 'working') = 'working'), 0)
  INTO v_completed, v_avg_rest
  FROM public.sets s
  JOIN public.workout_exercises we ON we.id = s.workout_exercise_id
  JOIN public.exercises ex          ON ex.id = we.exercise_id
  WHERE we.workout_id = p_workout_id
    AND ex.muscle_group::text <> 'cardio';

  IF v_completed > 0 THEN
    -- avg_rest = total planned rest / completed sets.
    v_avg_rest := v_avg_rest / v_completed;
    -- session_seconds = GREATEST(wall clock, work_est + rest_est) per §B.
    SELECT GREATEST(
      COALESCE(w.duration_seconds, 0),
      v_completed * 30 + v_completed * v_avg_rest)
    INTO v_session_secs
    FROM public.workouts w WHERE w.id = p_workout_id;

    v_cc_met := public.rpg_cardio_est_met_from_density(
                  v_completed, v_session_secs, v_avg_rest);

    -- Strength session modality = 'strength'; duration = wall-clock minutes.
    v_modality := 'strength';
    v_dur_min  := v_session_secs / 60.0;
    v_abs_met  := v_cc_met;
    v_rel := LEAST(1.20, (v_abs_met * 3.5) / v_vo2max);
    v_met_min := v_abs_met * v_dur_min;
    v_imult := public.rpg_cardio_intensity_mult(v_rel);
    v_eff := v_met_min * v_imult;

    v_remaining := GREATEST(0.0, 2500.0 - v_week_used);
    v_under := LEAST(v_eff, v_remaining);
    v_over  := v_eff - v_under;
    v_capped := v_under + v_over * 0.30;
    v_week_used := v_week_used + v_eff;

    v_base := power(v_capped, 0.60);
    v_dvo2 := public.rpg_cardio_demonstrated_vo2(v_abs_met, v_dur_min);
    v_tier := public.rpg_cardio_implied_tier(v_dvo2, v_age, v_female);
    v_tdm  := public.rpg_tier_diff_mult(v_tier, v_rank::numeric);
    v_mod  := public.rpg_cardio_modality_mult(v_modality);
    v_xp   := v_base * v_tdm * v_mod * 3.5;

    v_total_cardio_xp := v_total_cardio_xp + v_xp;
    v_rank := public.rpg_rank_for_xp(v_total_xp + v_total_cardio_xp);
  END IF;

  -- ===========================================================================
  -- Write the cardio xp_events row + body_part_progress upsert.
  -- Distinct conflict key: event_type='cardio_session', set_id NULL,
  -- session_id = workout_id. The reversal in save_workout reverts cleanly via
  -- the {"cardio": xp} attribution. Skip when nothing earned.
  -- ===========================================================================
  IF v_total_cardio_xp > 0 THEN
    v_attribution := jsonb_build_object(
      'cardio', round(v_total_cardio_xp, 4));
    v_payload := jsonb_build_object(
      'cardio_xp', round(v_total_cardio_xp, 4),
      'standing_vo2max', round(v_vo2max, 1),
      'age', v_age,
      'female', v_female);
    v_event_id := gen_random_uuid();

    INSERT INTO public.xp_events (
      id, user_id, event_type, set_id, session_id,
      occurred_at, payload, attribution, total_xp, created_at
    )
    VALUES (
      v_event_id, v_user_id, 'cardio_session', NULL, p_workout_id,
      v_now, v_payload, v_attribution, round(v_total_cardio_xp, 4), v_now
    )
    ON CONFLICT (user_id, session_id)
      WHERE set_id IS NULL AND event_type = 'cardio_session'
      DO NOTHING;

    INSERT INTO public.body_part_progress AS bpp (
      user_id, body_part, total_xp, rank,
      vitality_ewma, vitality_peak, last_event_at, updated_at
    )
    VALUES (
      v_user_id, 'cardio', round(v_total_cardio_xp, 4),
      public.rpg_rank_for_xp(round(v_total_cardio_xp, 4)),
      0, 0, v_now, v_now
    )
    ON CONFLICT (user_id, body_part) DO UPDATE SET
      total_xp      = bpp.total_xp + EXCLUDED.total_xp,
      rank          = public.rpg_rank_for_xp(bpp.total_xp + EXCLUDED.total_xp),
      last_event_at = v_now,
      updated_at    = v_now;
  END IF;

  -- ===========================================================================
  -- A4: recompute the rolling standing estimate (best-of 42-day window,
  -- floored at the non-exercise seed) + write back to profiles.
  -- ===========================================================================
  SELECT GREATEST(
    v_seed_vo2,
    COALESCE(MAX(
      public.rpg_cardio_best_effort_vo2(
        cs.distance_m, cs.duration_seconds,
        public.rpg_cardio_slug_to_modality(ex.slug))), v_seed_vo2))
  INTO v_new_vo2max
  FROM public.cardio_sessions cs
  JOIN public.workouts w   ON w.id = cs.workout_id
  JOIN public.exercises ex ON ex.id = cs.exercise_id
  WHERE w.user_id = v_user_id
    AND cs.created_at > v_now - (42 || ' days')::interval;

  UPDATE public.profiles
  SET cardio_vo2max = round(COALESCE(v_new_vo2max, v_seed_vo2), 1),
      cardio_vo2max_updated_at = v_now
  WHERE id = v_user_id;

  RETURN;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_cardio_session(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.record_cardio_session(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- PART D — wire record_cardio_session into save_workout (after the strength
-- batch PERFORM, inside the same transaction). Body VERBATIM from 00078 except
-- the one new PERFORM line. DROP+CREATE not needed (signature unchanged) →
-- CREATE OR REPLACE.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.save_workout(
  p_workout jsonb,
  p_exercises jsonb,
  p_sets jsonb,
  p_cardio jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_workout_id  uuid;
  v_user_id     uuid;
  v_routine_id  uuid;
  v_finished_at timestamptz;
  v_result      jsonb;

  v_plan_id        uuid;
  v_plan_routines  jsonb;
  v_week_start     date;
  v_now            timestamptz := now();
  v_found_idx      int;
  v_match_idx      int;
  v_routine_entry  jsonb;
  v_max_order      int;
  v_new_routines   jsonb;
BEGIN
  v_workout_id  := (p_workout ->> 'id')::uuid;
  v_user_id     := (p_workout ->> 'user_id')::uuid;
  v_routine_id  := NULLIF(p_workout ->> 'routine_id', '')::uuid;
  v_finished_at := (p_workout ->> 'finished_at')::timestamptz;

  IF v_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: workout user_id does not match authenticated user'
      USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM workouts WHERE id = v_workout_id AND user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Workout not found or does not belong to user'
      USING ERRCODE = 'P0002';
  END IF;

  -- BUG-RPG-001 reversal — reverts strength AND cardio body_part_progress by
  -- summing this session's xp_events.attribution over all keys (including the
  -- cardio key). Re-save converges.
  WITH session_contrib AS (
    SELECT
      e.user_id,
      kv.key                    AS body_part,
      SUM(kv.value::numeric)    AS xp_to_revert
    FROM xp_events e
    CROSS JOIN LATERAL jsonb_each_text(e.attribution) AS kv(key, value)
    WHERE e.user_id = v_user_id
      AND e.session_id = v_workout_id
    GROUP BY e.user_id, kv.key
  )
  UPDATE body_part_progress bpp
  SET total_xp = GREATEST(0, bpp.total_xp - sc.xp_to_revert),
      rank     = public.rpg_rank_for_xp(GREATEST(0, bpp.total_xp - sc.xp_to_revert)),
      updated_at = now()
  FROM session_contrib sc
  WHERE bpp.user_id   = sc.user_id
    AND bpp.body_part = sc.body_part;

  -- Re-save must also clear the prior cardio xp_events so record_cardio_session
  -- re-inserts from scratch (its ON CONFLICT DO NOTHING would otherwise keep
  -- the stale row after the reversal already decremented its XP).
  DELETE FROM xp_events
  WHERE user_id = v_user_id
    AND session_id = v_workout_id
    AND event_type = 'cardio_session';

  DELETE FROM workout_exercises WHERE workout_id = v_workout_id;
  DELETE FROM cardio_sessions WHERE workout_id = v_workout_id;

  UPDATE workouts
  SET
    name             = COALESCE(p_workout ->> 'name', name),
    finished_at      = v_finished_at,
    duration_seconds = (p_workout ->> 'duration_seconds')::integer,
    notes            = p_workout ->> 'notes',
    is_active        = false
  WHERE id = v_workout_id AND user_id = v_user_id;

  INSERT INTO workout_exercises (id, workout_id, exercise_id, "order", rest_seconds)
  SELECT
    (e ->> 'id')::uuid,
    (e ->> 'workout_id')::uuid,
    (e ->> 'exercise_id')::uuid,
    (e ->> 'order')::integer,
    (e ->> 'rest_seconds')::integer
  FROM jsonb_array_elements(p_exercises) AS e;

  INSERT INTO sets (id, workout_exercise_id, set_number, reps, weight, rpe, set_type, notes, is_completed)
  SELECT
    (s ->> 'id')::uuid,
    (s ->> 'workout_exercise_id')::uuid,
    (s ->> 'set_number')::integer,
    (s ->> 'reps')::integer,
    (s ->> 'weight')::numeric,
    (s ->> 'rpe')::integer,
    COALESCE(s ->> 'set_type', 'working'),
    s ->> 'notes',
    COALESCE((s ->> 'is_completed')::boolean, false)
  FROM jsonb_array_elements(p_sets) AS s;

  INSERT INTO cardio_sessions (
    id, workout_id, exercise_id, duration_seconds, distance_m, rpe, created_at
  )
  SELECT
    (c ->> 'id')::uuid,
    v_workout_id,
    (c ->> 'exercise_id')::uuid,
    (c ->> 'duration_seconds')::integer,
    (c ->> 'distance_m')::numeric,
    (c ->> 'rpe')::smallint,
    COALESCE((c ->> 'created_at')::timestamptz, v_now)
  FROM jsonb_array_elements(COALESCE(p_cardio, '[]'::jsonb)) AS c;

  PERFORM public.record_session_xp_batch(v_workout_id);

  -- Phase 38c — cardio earning. Runs AFTER the strength batch, INSIDE the same
  -- transaction. Earns cardio body_part_progress + writes back cardio_vo2max.
  -- Cardio stays out of character_state (38d). Reverted on re-save above.
  PERFORM public.record_cardio_session(v_workout_id);

  v_week_start := (date_trunc('week', v_now)::date);

  SELECT id, routines
  INTO v_plan_id, v_plan_routines
  FROM weekly_plans
  WHERE user_id = v_user_id AND week_start = v_week_start
  FOR UPDATE;

  IF v_plan_id IS NULL THEN
    SELECT to_jsonb(w) INTO v_result FROM workouts w WHERE w.id = v_workout_id;
    RETURN v_result;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(v_plan_routines) AS r
    WHERE (r ->> 'completed_workout_id') = v_workout_id::text
  ) THEN
    SELECT to_jsonb(w) INTO v_result FROM workouts w WHERE w.id = v_workout_id;
    RETURN v_result;
  END IF;

  v_match_idx := NULL;
  IF v_routine_id IS NOT NULL THEN
    SELECT (ord - 1)::int
    INTO v_match_idx
    FROM jsonb_array_elements(v_plan_routines) WITH ORDINALITY AS arr(r, ord)
    WHERE (r ->> 'routine_id') = v_routine_id::text
      AND (r ->> 'completed_workout_id') IS NULL
    ORDER BY (r ->> 'order')::int ASC
    LIMIT 1;
  END IF;

  IF v_match_idx IS NOT NULL THEN
    v_new_routines := jsonb_set(
      v_plan_routines,
      ARRAY[v_match_idx::text],
      (v_plan_routines -> v_match_idx)
        || jsonb_build_object(
             'completed_workout_id', v_workout_id::text,
             'completed_at',         to_jsonb(v_now)
           )
    );
  ELSE
    SELECT COALESCE(MAX((r ->> 'order')::int), 0)
    INTO v_max_order
    FROM jsonb_array_elements(v_plan_routines) AS r;

    v_routine_entry := jsonb_build_object(
      'routine_id',           to_jsonb(v_routine_id::text),
      'order',                v_max_order + 1,
      'completed_workout_id', v_workout_id::text,
      'completed_at',         to_jsonb(v_now),
      'is_spontaneous',       true
    );
    v_new_routines := v_plan_routines || jsonb_build_array(v_routine_entry);
  END IF;

  UPDATE weekly_plans
  SET routines   = v_new_routines,
      updated_at = v_now
  WHERE id = v_plan_id;

  SELECT to_jsonb(w) INTO v_result FROM workouts w WHERE w.id = v_workout_id;
  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.save_workout(jsonb, jsonb, jsonb, jsonb) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.save_workout(jsonb, jsonb, jsonb, jsonb) TO authenticated;
