-- =============================================================================
-- 00081 — Phase 38f: cardio titles + cardio vitality XP-gate
--
-- ## What this does
--
--   1. **Cardio title award (Workstream A).** Adds the 13 cardio body-part
--      title rungs (`cardio_r<thr>_<name>`) to the body-part VALUES list in
--      BOTH `record_set_xp` + `record_session_xp_batch`, and the
--      `('saga_unending', 172)` character-level rung to the char-level VALUES
--      list in both. Bodies are VERBATIM copies of the 00080 functions with
--      ONLY those two VALUES lists extended (the §8.1 / §8.2 crossing logic is
--      unchanged — cardio is already an active track as of 38e, so its rank
--      crossings flow through the same body-part path the strength tracks use).
--
--   2. **Cross-build evaluator (Workstream A).** Replaces
--      `evaluate_cross_build_titles_for_user` (from 00049): projects a cardio
--      rank (`v_cardio`), tightens `iron_bound` with `AND v_cardio <= 10`, and
--      adds the two new cardio cross-build IF-blocks `the_forged_wind`
--      (all six strength ≥ 60 AND cardio ≥ 60) + `storm_tempered`
--      (cardio ≥ 60 AND all six strength ≥ 30). The predicates are
--      bit-identical (integer arithmetic) to the Dart mirror in
--      `lib/features/rpg/domain/cross_build_title_evaluator.dart`.
--
--      ⚠ **iron_bound tightening is FUTURE-awards-only.** `earned_titles` is
--      append-only. This migration only changes which slugs the evaluator
--      RETURNS for future saves; it NEVER deletes or revokes an already-earned
--      `iron_bound` row. A user who earned `iron_bound` pre-38f keeps it even
--      if they later build cardio past rank 10.
--
--   3. **Cardio vitality XP-gate (Workstream B).** Redefines
--      `record_cardio_session` (from 00079): after computing the per-session
--      `v_xp = base × tdm × mod × 3.5`, multiplies it by a Vitality multiplier
--      `vmult = VITALITY_XP_FLOOR + (1 - VITALITY_XP_FLOOR) × vpct` where
--      `vpct = clamp(cardio vitality_ewma / vitality_peak, 0, 1)` (peak ≤ 0 →
--      vpct = 1.0). VITALITY_XP_FLOOR = 0.40. This mirrors the sim's
--      caller-side gate (`cardio-xp-simulation.py:526` `xp *= vmult`). A
--      lapsed user earns reduced cardio XP that ramps back to full as they
--      rebuild — strength is NOT touched. The gate reads the cardio
--      `body_part_progress` vitality columns (maintained as of 38e); a fresh
--      user with no cardio row has peak = 0 → vmult = 1.0 (full XP), so the
--      gate is a no-op on a first cardio save.
--
-- ## Why the full function bodies are reproduced
--   Postgres `CREATE OR REPLACE FUNCTION` requires the entire body. These are
--   verbatim copies of the 00080 (XP writers) / 00049 (evaluator) / 00079
--   (record_cardio_session) bodies with ONLY the Phase 38f deltas applied.
--
-- ## Grants — re-stated verbatim after each CREATE OR REPLACE.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- PART A — cross-build evaluator (verbatim 00049 + cardio projection,
-- iron_bound tightening, the_forged_wind + storm_tempered)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.evaluate_cross_build_titles_for_user(p_user_id uuid)
RETURNS TABLE (slug text)
LANGUAGE plpgsql
STABLE
PARALLEL SAFE
AS $$
DECLARE
  v_chest      int;
  v_back       int;
  v_legs       int;
  v_shoulders  int;
  v_arms       int;
  v_core       int;
  v_cardio     int;
  v_max_rank   int;
  v_min_rank   int;
  v_spread     numeric;
BEGIN
  -- Ownership check (BUG-030, preserved from 00045).
  IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'unauthorized: caller does not own p_user_id'
      USING ERRCODE = '42501';
  END IF;

  -- Project rank by body part. COALESCE to 1 for missing rows. Phase 38f adds
  -- the cardio projection for the cardio cross-build conditions.
  SELECT
    COALESCE(MAX(CASE WHEN body_part = 'chest'     THEN rank END), 1),
    COALESCE(MAX(CASE WHEN body_part = 'back'      THEN rank END), 1),
    COALESCE(MAX(CASE WHEN body_part = 'legs'      THEN rank END), 1),
    COALESCE(MAX(CASE WHEN body_part = 'shoulders' THEN rank END), 1),
    COALESCE(MAX(CASE WHEN body_part = 'arms'      THEN rank END), 1),
    COALESCE(MAX(CASE WHEN body_part = 'core'      THEN rank END), 1),
    COALESCE(MAX(CASE WHEN body_part = 'cardio'    THEN rank END), 1)
  INTO v_chest, v_back, v_legs, v_shoulders, v_arms, v_core, v_cardio
  FROM public.body_part_progress
  WHERE user_id = p_user_id
    AND body_part IN ('chest', 'back', 'legs', 'shoulders', 'arms', 'core', 'cardio');

  -- pillar_walker: legs >= 40 AND legs >= 2 * arms
  IF v_legs >= 40 AND v_legs >= 2 * v_arms THEN
    slug := 'pillar_walker'; RETURN NEXT;
  END IF;

  -- broad_shouldered (BUG-015 rebalance):
  --   chest+back+shoulders >= 1.6 * (legs+core)
  --   AND chest >= 30 AND back >= 30 AND shoulders >= 30
  --
  -- Integer arithmetic (`upper * 10 >= lower * 16`) mirrors the Dart
  -- predicate exactly to avoid float-drift mismatches at the boundary.
  IF v_chest >= 30
     AND v_back >= 30
     AND v_shoulders >= 30
     AND (v_chest + v_back + v_shoulders) * 10 >= (v_legs + v_core) * 16 THEN
    slug := 'broad_shouldered'; RETURN NEXT;
  END IF;

  -- even_handed: every track >= 30 AND (max - min) / max <= 0.30
  IF v_chest >= 30
     AND v_back >= 30
     AND v_legs >= 30
     AND v_shoulders >= 30
     AND v_arms >= 30
     AND v_core >= 30 THEN
    v_max_rank := GREATEST(v_chest, v_back, v_legs, v_shoulders, v_arms, v_core);
    v_min_rank := LEAST(v_chest, v_back, v_legs, v_shoulders, v_arms, v_core);
    v_spread := (v_max_rank - v_min_rank)::numeric / v_max_rank::numeric;
    IF v_spread <= 0.30 THEN
      slug := 'even_handed'; RETURN NEXT;
    END IF;
  END IF;

  -- iron_bound (Phase 38f): chest >= 60 AND back >= 60 AND legs >= 60
  --   AND cardio <= 10. The low-cardio condition is the strength-pure
  --   powerlifter distinction. FUTURE-awards-only — already-earned iron_bound
  --   rows are never revoked (earned_titles append-only; this evaluator only
  --   gates future INSERTs via the writers' ON CONFLICT DO NOTHING).
  IF v_chest >= 60 AND v_back >= 60 AND v_legs >= 60 AND v_cardio <= 10 THEN
    slug := 'iron_bound'; RETURN NEXT;
  END IF;

  -- saga_forged: every active strength track >= 60
  IF v_chest >= 60
     AND v_back >= 60
     AND v_legs >= 60
     AND v_shoulders >= 60
     AND v_arms >= 60
     AND v_core >= 60 THEN
    slug := 'saga_forged'; RETURN NEXT;
  END IF;

  -- the_forged_wind (Phase 38f): all six strength tracks >= 60 AND cardio >= 60.
  -- The complete-athlete apex (saga_forged + a fully-forged cardio engine).
  IF v_chest >= 60
     AND v_back >= 60
     AND v_legs >= 60
     AND v_shoulders >= 60
     AND v_arms >= 60
     AND v_core >= 60
     AND v_cardio >= 60 THEN
    slug := 'the_forged_wind'; RETURN NEXT;
  END IF;

  -- storm_tempered (Phase 38f): cardio >= 60 AND all six strength tracks >= 30.
  -- The cardio-led counterpart to iron_bound ("tempered, not narrowed").
  IF v_cardio >= 60
     AND v_chest >= 30
     AND v_back >= 30
     AND v_legs >= 30
     AND v_shoulders >= 30
     AND v_arms >= 30
     AND v_core >= 30 THEN
    slug := 'storm_tempered'; RETURN NEXT;
  END IF;

  RETURN;
END;
$$;

GRANT EXECUTE ON FUNCTION public.evaluate_cross_build_titles_for_user(uuid)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- PART B — record_set_xp (verbatim 00080 + 13 cardio body-part VALUES rows +
-- saga_unending char-level VALUES row)
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
  v_dom_novelty     numeric;
  v_dom_cap         numeric;
  v_pre_ranks       jsonb;
  v_post_ranks      jsonb;
  v_pre_total_xp    numeric;
  v_post_total_xp   numeric;
  v_pre_char_level  int;
  v_post_char_level int;
BEGIN
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

  -- Phase 38e — pre-rank map (all parts) + pre-character-level over the SEVEN
  -- active tracks (six strength + cardio).
  SELECT
    COALESCE(jsonb_object_agg(body_part, rank), '{}'::jsonb),
    COALESCE(SUM(total_xp), 0)
  INTO v_pre_ranks, v_pre_total_xp
  FROM public.body_part_progress
  WHERE user_id = v_user_id;
  v_pre_char_level := public.rpg_active_body_part_level(v_user_id);

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

  -- Phase 38a cardio save gate — cardio-attributed sets never enter the
  -- strength weight×reps path (cardio earns via record_cardio_session, 00079).
  IF v_primary_muscle = 'cardio' THEN RETURN; END IF;

  IF v_attribution IS NULL OR v_attribution = 'null'::jsonb OR v_attribution = '{}'::jsonb THEN
    v_attribution := jsonb_build_object(v_primary_muscle, 1.0);
  END IF;

  SELECT peak_weight INTO v_peak
  FROM public.exercise_peak_loads
  WHERE user_id = v_user_id AND exercise_id = v_exercise_id;
  IF v_peak IS NULL THEN v_peak := 0; END IF;

  v_effective_weight := CASE
    WHEN v_uses_bodyweight_load THEN
      COALESCE(v_weight, 0) + COALESCE(v_bodyweight_kg, 0) * v_bw_load_ratio
    ELSE
      COALESCE(v_weight, 0)
  END;

  SELECT k, (v::numeric) INTO v_dom_part, v_dom_share
  FROM jsonb_each_text(v_attribution) AS t(k, v)
  ORDER BY (v::numeric) DESC, k ASC
  LIMIT 1;
  IF v_dom_part IS NULL THEN v_dom_part := v_primary_muscle; END IF;

  SELECT bpp.rank INTO v_current_rank
  FROM public.body_part_progress bpp
  WHERE bpp.user_id = v_user_id AND bpp.body_part = v_dom_part;
  IF v_current_rank IS NULL THEN v_current_rank := 1; END IF;

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
  v_dom_novelty := 1.0;
  v_dom_cap     := 1.0;

  FOR v_attr_key, v_attr_share IN
    SELECT key, value::numeric FROM jsonb_each_text(v_attribution)
  LOOP
    IF v_attr_share <= 0 THEN CONTINUE; END IF;

    SELECT COALESCE(SUM(
      ((COALESCE(NULLIF(ex.xp_attribution, 'null'::jsonb),
                 jsonb_build_object(ex.muscle_group::text, 1.0))
        ->> v_attr_key))::numeric
    ), 0)
    INTO v_session_vol
    FROM public.xp_events e
    JOIN public.sets s               ON s.id = e.set_id
    JOIN public.workout_exercises we ON we.id = s.workout_exercise_id
    JOIN public.exercises ex          ON ex.id = we.exercise_id
    WHERE e.user_id = v_user_id
      AND e.session_id = v_workout_id
      AND e.id <> v_event_id
      AND e.set_id IS NOT NULL;

    SELECT COALESCE(SUM(
      ((COALESCE(NULLIF(ex.xp_attribution, 'null'::jsonb),
                 jsonb_build_object(ex.muscle_group::text, 1.0))
        ->> v_attr_key))::numeric
    ), 0)
    INTO v_weekly_vol
    FROM public.xp_events e
    JOIN public.sets s               ON s.id = e.set_id
    JOIN public.workout_exercises we ON we.id = s.workout_exercise_id
    JOIN public.exercises ex          ON ex.id = we.exercise_id
    WHERE e.user_id = v_user_id
      AND e.occurred_at > v_now - interval '7 days'
      AND e.id <> v_event_id
      AND e.set_id IS NOT NULL;

    v_novelty := exp(- v_session_vol / 15.0);
    v_cap     := CASE WHEN v_weekly_vol >= 15 THEN 0.3 ELSE 1.0 END;

    IF v_attr_key = v_dom_part THEN
      v_dom_novelty := v_novelty;
      v_dom_cap     := v_cap;
    END IF;

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

  v_event_payload := jsonb_build_object(
    'volume_load',         GREATEST(1.0, COALESCE(v_effective_weight, 0) * v_reps),
    'base_xp',             v_base,
    'intensity_mult',      v_intensity,
    'strength_mult',       v_strength,
    'novelty_mult',        v_dom_novelty,
    'cap_mult',            v_dom_cap,
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

  -- Phase 38e — post-character-level over the SEVEN active tracks.
  SELECT
    COALESCE(jsonb_object_agg(body_part, rank), '{}'::jsonb),
    COALESCE(SUM(total_xp), 0)
  INTO v_post_ranks, v_post_total_xp
  FROM public.body_part_progress
  WHERE user_id = v_user_id;
  v_post_char_level := public.rpg_active_body_part_level(v_user_id);

  -- Step 8.1: body-part rank crossings. VALUES list mirrors
  -- lib/features/rpg/data/title_thresholds_table.dart row-for-row. Phase 38f
  -- adds the 13 cardio rungs (cardio is an active track since 38e, so its
  -- crossings flow through the same path).
  INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
  SELECT v_user_id, v.slug, v_now, FALSE
  FROM (VALUES
    ('arms_r5_vein_stirrer',       'arms',       5),
    ('arms_r10_iron_fingered',     'arms',      10),
    ('arms_r15_sinew_drawn',       'arms',      15),
    ('arms_r20_marrow_cleaver',    'arms',      20),
    ('arms_r25_steel_sleeved',     'arms',      25),
    ('arms_r30_sinew_sworn',       'arms',      30),
    ('arms_r40_iron_knuckled',     'arms',      40),
    ('arms_r50_steel_forged',      'arms',      50),
    ('arms_r60_sinew_bound',       'arms',      60),
    ('arms_r70_iron_sleeved',      'arms',      70),
    ('arms_r80_sinew_of_storms',   'arms',      80),
    ('arms_r90_iron_untouched',    'arms',      90),
    ('arms_r99_the_sinew',         'arms',      99),
    ('back_r5_lattice_touched',    'back',       5),
    ('back_r10_wing_marked',       'back',      10),
    ('back_r15_rope_hauler',       'back',      15),
    ('back_r20_lat_crowned',       'back',      20),
    ('back_r25_talon_backed',      'back',      25),
    ('back_r30_wing_spread',       'back',      30),
    ('back_r40_lattice_hauled',    'back',      40),
    ('back_r50_wing_crowned',      'back',      50),
    ('back_r60_lattice_spread',    'back',      60),
    ('back_r70_wing_storm',        'back',      70),
    ('back_r80_wing_of_storms',    'back',      80),
    ('back_r90_sky_lattice',       'back',      90),
    ('back_r99_the_lattice',       'back',      99),
    ('cardio_r5_first_stride',     'cardio',     5),
    ('cardio_r10_breath_found',    'cardio',    10),
    ('cardio_r15_wind_touched',    'cardio',    15),
    ('cardio_r20_pace_keeper',     'cardio',    20),
    ('cardio_r25_long_strider',    'cardio',    25),
    ('cardio_r30_wind_drawn',      'cardio',    30),
    ('cardio_r40_tempo_sworn',     'cardio',    40),
    ('cardio_r50_wind_crowned',    'cardio',    50),
    ('cardio_r60_breath_forged',   'cardio',    60),
    ('cardio_r70_wind_runner',     'cardio',    70),
    ('cardio_r80_stride_of_storms','cardio',    80),
    ('cardio_r90_wind_untouched',  'cardio',    90),
    ('cardio_r99_the_stride',      'cardio',    99),
    ('chest_r5_initiate_of_the_forge', 'chest',  5),
    ('chest_r10_plate_bearer',     'chest',     10),
    ('chest_r15_forge_marked',     'chest',     15),
    ('chest_r20_iron_chested',     'chest',     20),
    ('chest_r25_anvil_heart',      'chest',     25),
    ('chest_r30_forge_born',       'chest',     30),
    ('chest_r40_bulwark_chested',  'chest',     40),
    ('chest_r50_forge_plated',     'chest',     50),
    ('chest_r60_anvil_forged',     'chest',     60),
    ('chest_r70_forge_heart',      'chest',     70),
    ('chest_r80_heart_of_forge',   'chest',     80),
    ('chest_r90_forge_untouched',  'chest',     90),
    ('chest_r99_the_anvil',        'chest',     99),
    ('core_r5_spine_tested',       'core',       5),
    ('core_r10_core_forged',       'core',      10),
    ('core_r15_pillar_spined',     'core',      15),
    ('core_r20_iron_belted',       'core',      20),
    ('core_r25_stonewall',         'core',      25),
    ('core_r30_diamond_spine',     'core',      30),
    ('core_r40_anchor_belted',     'core',      40),
    ('core_r50_stone_cored',       'core',      50),
    ('core_r60_marrow_carved',     'core',      60),
    ('core_r70_stone_spined',      'core',      70),
    ('core_r80_spine_of_storms',   'core',      80),
    ('core_r90_marrow_untouched',  'core',      90),
    ('core_r99_the_spine',         'core',      99),
    ('legs_r5_ground_walker',      'legs',       5),
    ('legs_r10_stone_stepper',     'legs',      10),
    ('legs_r15_pillar_apprentice', 'legs',      15),
    ('legs_r20_pillar_walker',     'legs',      20),
    ('legs_r25_quarry_strider',    'legs',      25),
    ('legs_r30_mountain_strider',  'legs',      30),
    ('legs_r40_stone_strider',     'legs',      40),
    ('legs_r50_mountain_footed',   'legs',      50),
    ('legs_r60_mountain_rooted',   'legs',      60),
    ('legs_r70_pillar_footed',     'legs',      70),
    ('legs_r80_pillar_of_storms',  'legs',      80),
    ('legs_r90_mountain_untouched','legs',      90),
    ('legs_r99_the_pillar',        'legs',      99),
    ('shoulders_r5_burden_tester',     'shoulders', 5),
    ('shoulders_r10_yoke_apprentice',  'shoulders', 10),
    ('shoulders_r15_sky_reach',        'shoulders', 15),
    ('shoulders_r20_atlas_touched',    'shoulders', 20),
    ('shoulders_r25_sky_vaulter',      'shoulders', 25),
    ('shoulders_r30_yoke_crowned',     'shoulders', 30),
    ('shoulders_r40_atlas_carried',    'shoulders', 40),
    ('shoulders_r50_sky_yoked',        'shoulders', 50),
    ('shoulders_r60_sky_vaulted',      'shoulders', 60),
    ('shoulders_r70_sky_held',         'shoulders', 70),
    ('shoulders_r80_sky_sundered',     'shoulders', 80),
    ('shoulders_r90_sky_untouched',    'shoulders', 90),
    ('shoulders_r99_the_atlas',        'shoulders', 99)
  ) AS v(slug, body_part, rank_threshold)
  WHERE v.rank_threshold > COALESCE((v_pre_ranks  ->> v.body_part)::int, 1)
    AND v.rank_threshold <= COALESCE((v_post_ranks ->> v.body_part)::int, 1)
  ON CONFLICT (user_id, title_id) DO NOTHING;

  -- Step 8.2: character-level crossings. Phase 38f adds saga_unending@172
  -- (the cardio-inclusive level cap — max computed level is now 172).
  IF v_post_char_level > v_pre_char_level THEN
    INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
    SELECT v_user_id, v.slug, v_now, FALSE
    FROM (VALUES
      ('wanderer',      10),
      ('path_trodden',  25),
      ('path_sworn',    50),
      ('path_forged',   75),
      ('saga_scribed',  100),
      ('saga_bound',    125),
      ('saga_eternal',  148),
      ('saga_unending', 172)
    ) AS v(slug, level_threshold)
    WHERE v.level_threshold >  v_pre_char_level
      AND v.level_threshold <= v_post_char_level
    ON CONFLICT (user_id, title_id) DO NOTHING;
  END IF;

  -- Step 8.3: cross-build distinction titles via the 00081 helper (now cardio-
  -- aware: iron_bound tightened, the_forged_wind + storm_tempered added).
  INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
  SELECT v_user_id, cb.slug, v_now, FALSE
  FROM public.evaluate_cross_build_titles_for_user(v_user_id) cb
  ON CONFLICT (user_id, title_id) DO NOTHING;

  RETURN;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_set_xp(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.record_set_xp(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- PART C — record_session_xp_batch (verbatim 00080 + 13 cardio body-part
-- VALUES rows + saga_unending char-level VALUES row)
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
  v_dom_novelty_f    float8;
  v_dom_cap_f        float8;
  v_pre_ranks       jsonb;
  v_post_ranks      jsonb;
  v_pre_total_xp    numeric;
  v_post_total_xp   numeric;
  v_pre_char_level  int;
  v_post_char_level int;
BEGIN
  SELECT user_id INTO v_user_id FROM public.workouts WHERE id = p_workout_id;
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'record_session_xp_batch: workout % not found', p_workout_id
      USING ERRCODE = 'P0002';
  END IF;

  SELECT bodyweight_kg, gender INTO v_bodyweight_kg, v_gender
  FROM public.profiles WHERE id = v_user_id;
  v_bodyweight_f := COALESCE(v_bodyweight_kg, 0)::float8;

  -- Phase 38e — pre-rank map (all parts) + pre-character-level over the SEVEN
  -- active tracks (six strength + cardio). Denominator stays 4.
  SELECT
    COALESCE(jsonb_object_agg(body_part, rank), '{}'::jsonb),
    COALESCE(SUM(total_xp), 0)
  INTO v_pre_ranks, v_pre_total_xp
  FROM public.body_part_progress
  WHERE user_id = v_user_id;
  v_pre_char_level := public.rpg_active_body_part_level(v_user_id);

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
      kv.key                    AS bp_key,
      SUM((kv.value)::float8)   AS bp_share
    FROM public.xp_events e
    JOIN public.sets s              ON s.id = e.set_id
    JOIN public.workout_exercises we ON we.id = s.workout_exercise_id
    JOIN public.exercises ex         ON ex.id = we.exercise_id
    CROSS JOIN LATERAL jsonb_each_text(
      COALESCE(NULLIF(ex.xp_attribution, 'null'::jsonb),
               jsonb_build_object(ex.muscle_group::text, 1.0))
    ) AS kv(key, value)
    WHERE e.user_id = v_user_id
      AND e.occurred_at > v_now - interval '7 days'
      AND (e.session_id IS DISTINCT FROM p_workout_id)
      AND e.set_id IS NOT NULL
    GROUP BY kv.key
  )
  SELECT
    COALESCE(MAX(bp_share) FILTER (WHERE bp_key = 'chest'),     0)::float8,
    COALESCE(MAX(bp_share) FILTER (WHERE bp_key = 'back'),      0)::float8,
    COALESCE(MAX(bp_share) FILTER (WHERE bp_key = 'legs'),      0)::float8,
    COALESCE(MAX(bp_share) FILTER (WHERE bp_key = 'shoulders'), 0)::float8,
    COALESCE(MAX(bp_share) FILTER (WHERE bp_key = 'arms'),      0)::float8,
    COALESCE(MAX(bp_share) FILTER (WHERE bp_key = 'core'),      0)::float8,
    COALESCE(MAX(bp_share) FILTER (WHERE bp_key = 'cardio'),    0)::float8
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
      AND ex.muscle_group::text <> 'cardio'
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

    v_effective_weight_f := CASE
      WHEN v_set_record.uses_bodyweight_load THEN
        COALESCE(v_set_record.weight, 0)::float8
        + v_bodyweight_f * v_set_record.bodyweight_load_ratio::float8
      ELSE
        COALESCE(v_set_record.weight, 0)::float8
    END;

    SELECT k INTO v_dom_part
    FROM jsonb_each_text(v_attribution) AS t(k, v)
    ORDER BY (v::numeric) DESC, k ASC
    LIMIT 1;
    IF v_dom_part IS NULL THEN
      v_dom_part := v_set_record.primary_muscle;
    END IF;

    SELECT bpp.rank INTO v_current_rank_n
    FROM public.body_part_progress bpp
    WHERE bpp.user_id = v_user_id AND bpp.body_part = v_dom_part;
    IF v_current_rank_n IS NULL THEN v_current_rank_n := 1; END IF;

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
    v_dom_novelty_f := 1.0;
    v_dom_cap_f     := 1.0;

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

      IF v_attr_key = v_dom_part THEN
        v_dom_novelty_f := v_novelty_f;
        v_dom_cap_f     := v_cap_f;
      END IF;

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

      v_session_vol[v_bp_idx] := v_session_vol[v_bp_idx] + v_attr_share;
      v_weekly_vol[v_bp_idx]  := v_weekly_vol[v_bp_idx]  + v_attr_share;
      v_bp_total[v_bp_idx]    := v_bp_total[v_bp_idx]    + v_xp_for_bp_f;
    END LOOP;

    v_event_payload := jsonb_build_object(
      'volume_load',         GREATEST(1.0, v_effective_weight_f * v_set_record.reps),
      'base_xp',             round(v_base_f::numeric, 4),
      'intensity_mult',      round(v_intensity_f::numeric, 4),
      'strength_mult',       round(v_strength_f::numeric, 4),
      'novelty_mult',        round(v_dom_novelty_f::numeric, 4),
      'cap_mult',            round(v_dom_cap_f::numeric, 4),
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

  WITH per_set AS (
    SELECT we.exercise_id, s.weight, s.reps
    FROM public.sets s
    JOIN public.workout_exercises we ON we.id = s.workout_exercise_id
    JOIN public.exercises ex          ON ex.id = we.exercise_id
    WHERE we.workout_id = p_workout_id
      AND s.is_completed = TRUE
      AND COALESCE(s.set_type, 'working') = 'working'
      AND s.reps IS NOT NULL AND s.reps >= 1
      AND s.weight > 0
      AND ex.muscle_group::text <> 'cardio'
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
      AND ex.muscle_group::text <> 'cardio'
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

  -- Phase 38e — post-character-level over the SEVEN active tracks.
  SELECT
    COALESCE(jsonb_object_agg(body_part, rank), '{}'::jsonb),
    COALESCE(SUM(total_xp), 0)
  INTO v_post_ranks, v_post_total_xp
  FROM public.body_part_progress
  WHERE user_id = v_user_id;
  v_post_char_level := public.rpg_active_body_part_level(v_user_id);

  -- Step 8.1: body-part rank crossings. Phase 38f adds the 13 cardio rungs.
  INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
  SELECT v_user_id, v.slug, v_now, FALSE
  FROM (VALUES
    ('arms_r5_vein_stirrer',       'arms',       5),
    ('arms_r10_iron_fingered',     'arms',      10),
    ('arms_r15_sinew_drawn',       'arms',      15),
    ('arms_r20_marrow_cleaver',    'arms',      20),
    ('arms_r25_steel_sleeved',     'arms',      25),
    ('arms_r30_sinew_sworn',       'arms',      30),
    ('arms_r40_iron_knuckled',     'arms',      40),
    ('arms_r50_steel_forged',      'arms',      50),
    ('arms_r60_sinew_bound',       'arms',      60),
    ('arms_r70_iron_sleeved',      'arms',      70),
    ('arms_r80_sinew_of_storms',   'arms',      80),
    ('arms_r90_iron_untouched',    'arms',      90),
    ('arms_r99_the_sinew',         'arms',      99),
    ('back_r5_lattice_touched',    'back',       5),
    ('back_r10_wing_marked',       'back',      10),
    ('back_r15_rope_hauler',       'back',      15),
    ('back_r20_lat_crowned',       'back',      20),
    ('back_r25_talon_backed',      'back',      25),
    ('back_r30_wing_spread',       'back',      30),
    ('back_r40_lattice_hauled',    'back',      40),
    ('back_r50_wing_crowned',      'back',      50),
    ('back_r60_lattice_spread',    'back',      60),
    ('back_r70_wing_storm',        'back',      70),
    ('back_r80_wing_of_storms',    'back',      80),
    ('back_r90_sky_lattice',       'back',      90),
    ('back_r99_the_lattice',       'back',      99),
    ('cardio_r5_first_stride',     'cardio',     5),
    ('cardio_r10_breath_found',    'cardio',    10),
    ('cardio_r15_wind_touched',    'cardio',    15),
    ('cardio_r20_pace_keeper',     'cardio',    20),
    ('cardio_r25_long_strider',    'cardio',    25),
    ('cardio_r30_wind_drawn',      'cardio',    30),
    ('cardio_r40_tempo_sworn',     'cardio',    40),
    ('cardio_r50_wind_crowned',    'cardio',    50),
    ('cardio_r60_breath_forged',   'cardio',    60),
    ('cardio_r70_wind_runner',     'cardio',    70),
    ('cardio_r80_stride_of_storms','cardio',    80),
    ('cardio_r90_wind_untouched',  'cardio',    90),
    ('cardio_r99_the_stride',      'cardio',    99),
    ('chest_r5_initiate_of_the_forge', 'chest',  5),
    ('chest_r10_plate_bearer',     'chest',     10),
    ('chest_r15_forge_marked',     'chest',     15),
    ('chest_r20_iron_chested',     'chest',     20),
    ('chest_r25_anvil_heart',      'chest',     25),
    ('chest_r30_forge_born',       'chest',     30),
    ('chest_r40_bulwark_chested',  'chest',     40),
    ('chest_r50_forge_plated',     'chest',     50),
    ('chest_r60_anvil_forged',     'chest',     60),
    ('chest_r70_forge_heart',      'chest',     70),
    ('chest_r80_heart_of_forge',   'chest',     80),
    ('chest_r90_forge_untouched',  'chest',     90),
    ('chest_r99_the_anvil',        'chest',     99),
    ('core_r5_spine_tested',       'core',       5),
    ('core_r10_core_forged',       'core',      10),
    ('core_r15_pillar_spined',     'core',      15),
    ('core_r20_iron_belted',       'core',      20),
    ('core_r25_stonewall',         'core',      25),
    ('core_r30_diamond_spine',     'core',      30),
    ('core_r40_anchor_belted',     'core',      40),
    ('core_r50_stone_cored',       'core',      50),
    ('core_r60_marrow_carved',     'core',      60),
    ('core_r70_stone_spined',      'core',      70),
    ('core_r80_spine_of_storms',   'core',      80),
    ('core_r90_marrow_untouched',  'core',      90),
    ('core_r99_the_spine',         'core',      99),
    ('legs_r5_ground_walker',      'legs',       5),
    ('legs_r10_stone_stepper',     'legs',      10),
    ('legs_r15_pillar_apprentice', 'legs',      15),
    ('legs_r20_pillar_walker',     'legs',      20),
    ('legs_r25_quarry_strider',    'legs',      25),
    ('legs_r30_mountain_strider',  'legs',      30),
    ('legs_r40_stone_strider',     'legs',      40),
    ('legs_r50_mountain_footed',   'legs',      50),
    ('legs_r60_mountain_rooted',   'legs',      60),
    ('legs_r70_pillar_footed',     'legs',      70),
    ('legs_r80_pillar_of_storms',  'legs',      80),
    ('legs_r90_mountain_untouched','legs',      90),
    ('legs_r99_the_pillar',        'legs',      99),
    ('shoulders_r5_burden_tester',     'shoulders', 5),
    ('shoulders_r10_yoke_apprentice',  'shoulders', 10),
    ('shoulders_r15_sky_reach',        'shoulders', 15),
    ('shoulders_r20_atlas_touched',    'shoulders', 20),
    ('shoulders_r25_sky_vaulter',      'shoulders', 25),
    ('shoulders_r30_yoke_crowned',     'shoulders', 30),
    ('shoulders_r40_atlas_carried',    'shoulders', 40),
    ('shoulders_r50_sky_yoked',        'shoulders', 50),
    ('shoulders_r60_sky_vaulted',      'shoulders', 60),
    ('shoulders_r70_sky_held',         'shoulders', 70),
    ('shoulders_r80_sky_sundered',     'shoulders', 80),
    ('shoulders_r90_sky_untouched',    'shoulders', 90),
    ('shoulders_r99_the_atlas',        'shoulders', 99)
  ) AS v(slug, body_part, rank_threshold)
  WHERE v.rank_threshold > COALESCE((v_pre_ranks  ->> v.body_part)::int, 1)
    AND v.rank_threshold <= COALESCE((v_post_ranks ->> v.body_part)::int, 1)
  ON CONFLICT (user_id, title_id) DO NOTHING;

  -- Step 8.2: character-level crossings. Phase 38f adds saga_unending@172.
  IF v_post_char_level > v_pre_char_level THEN
    INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
    SELECT v_user_id, v.slug, v_now, FALSE
    FROM (VALUES
      ('wanderer',      10),
      ('path_trodden',  25),
      ('path_sworn',    50),
      ('path_forged',   75),
      ('saga_scribed',  100),
      ('saga_bound',    125),
      ('saga_eternal',  148),
      ('saga_unending', 172)
    ) AS v(slug, level_threshold)
    WHERE v.level_threshold >  v_pre_char_level
      AND v.level_threshold <= v_post_char_level
    ON CONFLICT (user_id, title_id) DO NOTHING;
  END IF;

  -- Step 8.3: cross-build distinction titles (now cardio-aware).
  INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
  SELECT v_user_id, cb.slug, v_now, FALSE
  FROM public.evaluate_cross_build_titles_for_user(v_user_id) cb
  ON CONFLICT (user_id, title_id) DO NOTHING;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_session_xp_batch(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.record_session_xp_batch(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- PART D — record_cardio_session (verbatim 00079 PART C + Workstream B
-- vitality XP-gate)
--
-- Delta vs 00079: after computing per-entry v_xp = base × tdm × mod × 3.5,
-- multiply by the cardio Vitality multiplier
--   vmult = VITALITY_XP_FLOOR + (1 - VITALITY_XP_FLOOR) × vpct
--   vpct  = clamp(cardio vitality_ewma / vitality_peak, 0, 1)   (peak ≤ 0 → 1.0)
-- VITALITY_XP_FLOOR = 0.40. Read from this user's cardio body_part_progress
-- row (vitality columns maintained as of 38e). Computed ONCE per save before
-- the entry loop (mirrors the sim computing vmult from start-of-week
-- conditioning, applied to every session that week). A fresh user with no
-- cardio row → peak = 0 → vmult = 1.0, so the gate is a no-op on the first
-- cardio save. Strength is NOT touched.
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
  v_week_used  numeric := 0;   -- intensity-weighted MET-min already used this week
  v_week_start timestamptz;    -- ISO (Monday) week boundary for the cap window
  v_session_eff_met_min numeric := 0;  -- this session's eff_met_min (for payload)

  -- Phase 38f — cardio Vitality XP-gate (Workstream B).
  v_vit_ewma   numeric := 0;
  v_vit_peak   numeric := 0;
  v_vpct       numeric;
  v_vmult      numeric;

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
  -- Phase 38f Vitality XP-gate. Read the user's CARDIO conditioning
  -- (body_part_progress['cardio'] vitality_ewma/peak, maintained as of 38e).
  -- vmult mirrors the sim's caller-side gate (cardio-xp-simulation.py:526):
  --   vpct  = clamp(ewma/peak, 0, 1) (peak ≤ 0 → 1.0, the un-conditioned prior)
  --   vmult = 0.40 + (1 - 0.40) × vpct
  -- Applied to every per-entry v_xp BEFORE accumulating v_total_cardio_xp, so
  -- the live cardio XP matches the gated sim output. A fresh user (no cardio
  -- row) has peak 0 → vmult 1.0 → full XP (gate is a no-op first save).
  -- ===========================================================================
  SELECT COALESCE(vitality_ewma, 0), COALESCE(vitality_peak, 0)
  INTO v_vit_ewma, v_vit_peak
  FROM public.body_part_progress
  WHERE user_id = v_user_id AND body_part = 'cardio';
  v_vit_ewma := COALESCE(v_vit_ewma, 0);
  v_vit_peak := COALESCE(v_vit_peak, 0);
  IF v_vit_peak <= 0 THEN
    v_vpct := 1.0;
  ELSE
    v_vpct := GREATEST(0.0, LEAST(1.0, v_vit_ewma / v_vit_peak));
  END IF;
  v_vmult := 0.40 + (1.0 - 0.40) * v_vpct;

  -- ===========================================================================
  -- Seed v_week_used from this user's prior cardio eff_met_min EARNED THIS ISO
  -- WEEK (carries the weekly diminishing-returns cap across saves, matching
  -- compute_session_xp). ISO week = Monday-based date_trunc('week', ...).
  -- ===========================================================================
  v_week_start := date_trunc('week', v_now);
  SELECT COALESCE(SUM((e.payload ->> 'eff_met_min')::numeric), 0)
  INTO v_week_used
  FROM public.xp_events e
  WHERE e.user_id = v_user_id
    AND e.event_type = 'cardio_session'
    AND e.set_id IS NULL
    AND e.occurred_at >= v_week_start
    AND (e.session_id IS DISTINCT FROM p_workout_id);

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
    v_session_eff_met_min := v_session_eff_met_min + v_eff;

    v_base := power(v_capped, 0.60);
    v_dvo2 := public.rpg_cardio_demonstrated_vo2(v_abs_met, v_dur_min);
    v_tier := public.rpg_cardio_implied_tier(v_dvo2, v_age, v_female);
    v_tdm  := public.rpg_tier_diff_mult(v_tier, v_rank::numeric);
    v_mod  := public.rpg_cardio_modality_mult(v_modality);
    -- Phase 38f — apply the Vitality XP-gate as the final factor (mirrors the
    -- sim's `xp *= vmult` after compute_session_xp).
    v_xp   := v_base * v_tdm * v_mod * 3.5 * v_vmult;

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
    v_session_eff_met_min := v_session_eff_met_min + v_eff;

    v_base := power(v_capped, 0.60);
    v_dvo2 := public.rpg_cardio_demonstrated_vo2(v_abs_met, v_dur_min);
    v_tier := public.rpg_cardio_implied_tier(v_dvo2, v_age, v_female);
    v_tdm  := public.rpg_tier_diff_mult(v_tier, v_rank::numeric);
    v_mod  := public.rpg_cardio_modality_mult(v_modality);
    -- Phase 38f — the Vitality gate applies to the cross-credit entry too (it
    -- is part of the same session's cardio earning).
    v_xp   := v_base * v_tdm * v_mod * 3.5 * v_vmult;

    v_total_cardio_xp := v_total_cardio_xp + v_xp;
    v_rank := public.rpg_rank_for_xp(v_total_xp + v_total_cardio_xp);
  END IF;

  -- ===========================================================================
  -- Write the cardio xp_events row + body_part_progress upsert.
  -- ===========================================================================
  IF v_total_cardio_xp > 0 THEN
    v_attribution := jsonb_build_object(
      'cardio', round(v_total_cardio_xp, 4));
    v_payload := jsonb_build_object(
      'cardio_xp', round(v_total_cardio_xp, 4),
      'eff_met_min', round(v_session_eff_met_min, 4),
      'week_used_before', round(v_week_used - v_session_eff_met_min, 4),
      'standing_vo2max', round(v_vo2max, 1),
      'vitality_mult', round(v_vmult, 4),
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
