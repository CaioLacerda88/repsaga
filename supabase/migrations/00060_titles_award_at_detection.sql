-- =============================================================================
-- 00060 — Phase 26d Task 2: award `earned_titles` rows at XP-detection time
--
-- ## What this does
--
-- CREATE OR REPLACE the two XP-emitting RPCs to ALSO INSERT into
-- `earned_titles` whenever a threshold crossing fires during the same call:
--
--   * `record_set_xp(p_set_id uuid)`               — per-set diagnostic
--   * `record_session_xp_batch(p_workout_id uuid)` — production save_workout
--
-- Three kinds of crossing are detected:
--
--   1. **Body-part rank crossing.** For each body part whose UPSERTed
--      `body_part_progress.rank` advanced past one of the 78 catalog
--      thresholds, INSERT the corresponding slug. The threshold table is
--      inlined as a VALUES list mirroring
--      `lib/features/rpg/data/title_thresholds_table.dart` row-for-row.
--   2. **Character-level crossing.** Character level = `rpg_rank_for_xp` of
--      the SUM of every `body_part_progress.total_xp` row. Compare pre and
--      post; INSERT any of the 7 character-level slugs whose threshold
--      lies in `(pre, post]`.
--   3. **Cross-build distinction.** Reuses
--      `public.evaluate_cross_build_titles_for_user(uuid)` from migration
--      00043 (no duplication of the predicate logic) and INSERTs each slug
--      it emits. `ON CONFLICT DO NOTHING` keeps this idempotent for users
--      that already qualified before this migration.
--
-- Every INSERT uses `ON CONFLICT (user_id, title_id) DO NOTHING` against the
-- PK from migration 00040. `is_active` defaults to FALSE — equipping is a
-- separate user action; the celebration overlay reads the new rows on its
-- next poll.
--
-- ## Why this lives in the XP RPC and not a trigger
--
--   * Detection needs both pre-rank AND post-rank for each body part. A
--     plain `AFTER UPDATE` trigger on `body_part_progress` sees post but not
--     reliably-pre (the function's `OLD` is only available on row-level
--     triggers, which would fire per-row inside the loop — and we already
--     have a clean place to capture pre/post inside the RPC).
--   * The cross-build helper is `STABLE`, so it can't sit in a trigger that
--     also writes. A statement-level AFTER trigger could, but at the cost of
--     a second round-trip we don't need — we already know which user.
--   * Keeping the writes inside the SECURITY DEFINER RPC bypasses RLS
--     cleanly (no new policies needed). The user-side INSERT policy from
--     migration 00041 stays untouched.
--
-- ## Hot-path discipline
--
-- The body-part INSERT runs ONCE per RPC call against a small constant-size
-- VALUES list (78 rows) filtered by a jsonb membership test against the
-- per-user pre/post rank maps. Postgres evaluates this as a hash join —
-- negligible vs the per-set loop cost. The character-level INSERT runs ONCE
-- against a 7-row VALUES list. The cross-build INSERT is a single SELECT
-- against `evaluate_cross_build_titles_for_user`. Three additional INSERTs
-- per save_workout call; each scans ≤ 78 rows; no per-set overhead.
--
-- ## Idempotency
--
-- `CREATE OR REPLACE FUNCTION` is idempotent — re-running this migration is a
-- no-op against a database already on post-00060 function bodies. The
-- INSERTs inside the functions are themselves idempotent via the PK ON
-- CONFLICT clause: re-saving the same workout never produces duplicate
-- earned_titles rows.
--
-- ## What's NOT in this migration
--
--   * `_rpg_backfill_chunk` is intentionally NOT extended. Title backfill
--     for the historical replay path is Task 3 — a separate RPC that scans
--     post-replay state once at the end, not per-chunk. Wiring detection
--     into `_rpg_backfill_chunk` would re-fire the same INSERT thousands of
--     times for a high-rank user (and the ON CONFLICT clause would do all
--     the work for nothing); cleaner to leave it as Task 3's dedicated pass.
--   * No schema changes. `earned_titles` already exists with the right PK
--     and column types (00040).
--   * No new permissions / RLS policy changes. Both RPCs remain
--     `SECURITY DEFINER` with `GRANT EXECUTE TO authenticated`; the INSERT
--     into earned_titles happens in definer context and bypasses RLS.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- record_set_xp — per-set XP RPC (Phase 26d Task 2)
--
-- Diff vs 00057:
--   * New locals: `v_pre_ranks jsonb`, `v_post_ranks jsonb`,
--     `v_pre_total_xp numeric`, `v_post_total_xp numeric`,
--     `v_pre_char_level int`, `v_post_char_level int`.
--   * NEW capture before Step 6 UPSERT loop: SELECT pre-rank map +
--     pre-character-level from `body_part_progress`. Missing rows
--     COALESCE to rank 1.
--   * NEW after Step 6: re-SELECT post-rank map + post-character-level.
--   * NEW Step 8.1: INSERT into `earned_titles` for each body-part
--     threshold in `(pre_rank, post_rank]`. Slugs sourced from
--     `lib/features/rpg/data/title_thresholds_table.dart`.
--   * NEW Step 8.2: INSERT character-level title rows for any threshold
--     in `(pre_char_level, post_char_level]`.
--   * NEW Step 8.3: INSERT cross-build title rows from
--     `evaluate_cross_build_titles_for_user(v_user_id)`.
--
-- All other 00057 behavior preserved verbatim.
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
  v_event_attr_each text;
  v_now          timestamptz := now();
  v_primary_muscle text;
  -- Phase 26d Task 2: title detection state.
  -- Pre-state is captured ONCE before the body-part fan-out loop; post-state
  -- is read from `body_part_progress` after the UPSERTs land. Missing rows
  -- COALESCE to rank 1 (matches the resolver convention used elsewhere).
  v_pre_ranks       jsonb;
  v_post_ranks      jsonb;
  v_pre_total_xp    numeric;
  v_post_total_xp   numeric;
  v_pre_char_level  int;
  v_post_char_level int;
BEGIN
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

  SELECT bodyweight_kg INTO v_bodyweight_kg
  FROM public.profiles
  WHERE id = v_user_id;

  SELECT xp_attribution, primary_muscle_group::text,
         COALESCE(difficulty_mult, 1.0),
         COALESCE(uses_bodyweight_load, FALSE)
  INTO v_attribution, v_primary_muscle, v_difficulty_mult,
       v_uses_bodyweight_load
  FROM (
    SELECT
      xp_attribution,
      muscle_group AS primary_muscle_group,
      difficulty_mult,
      uses_bodyweight_load
    FROM public.exercises
    WHERE id = v_exercise_id
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

  v_base := public.rpg_base_xp(v_effective_weight, v_reps);
  v_intensity := public.rpg_intensity_for_reps(v_reps);
  IF v_weight > v_peak THEN
    v_peak := v_weight;
  END IF;
  v_strength := public.rpg_strength_mult(v_effective_weight, v_peak);

  -- Phase 26d Task 2: capture pre-rank map + pre-character-level BEFORE the
  -- per-bp UPSERT loop. Missing body_part_progress rows default to rank 1.
  SELECT
    COALESCE(jsonb_object_agg(body_part, rank), '{}'::jsonb),
    COALESCE(SUM(total_xp), 0)
  INTO v_pre_ranks, v_pre_total_xp
  FROM public.body_part_progress
  WHERE user_id = v_user_id;
  v_pre_char_level := public.rpg_rank_for_xp(v_pre_total_xp);

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
    v_cap     := CASE WHEN v_weekly_vol >= 20 THEN 0.5 ELSE 1.0 END;

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

  -- Phase 26d Task 2: title detection — run AFTER body_part_progress UPSERT
  -- so the post-rank map reflects the just-applied XP. Re-SELECT is
  -- intentional: it's one fixed-size scan of ≤6 rows; restructuring the
  -- inner loop to carry post-rank state would be churn-only.
  SELECT
    COALESCE(jsonb_object_agg(body_part, rank), '{}'::jsonb),
    COALESCE(SUM(total_xp), 0)
  INTO v_post_ranks, v_post_total_xp
  FROM public.body_part_progress
  WHERE user_id = v_user_id;
  v_post_char_level := public.rpg_rank_for_xp(v_post_total_xp);

  -- Step 8.1: body-part rank crossings. The VALUES list mirrors
  -- lib/features/rpg/data/title_thresholds_table.dart row-for-row; the
  -- integrity test on the Dart side fails the suite if the two drift.
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
  -- COALESCE to 1 on both sides:
  --   * pre missing → no prior body_part_progress row → user was at rank 1
  --   * post missing → this RPC didn't write to that body part (no XP earned
  --     for it this call), so the threshold > 1 filter blocks every row and
  --     no spurious INSERTs fire.
  WHERE v.rank_threshold > COALESCE((v_pre_ranks  ->> v.body_part)::int, 1)
    AND v.rank_threshold <= COALESCE((v_post_ranks ->> v.body_part)::int, 1)
  ON CONFLICT (user_id, title_id) DO NOTHING;

  -- Step 8.2: character-level crossings.
  IF v_post_char_level > v_pre_char_level THEN
    INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
    SELECT v_user_id, v.slug, v_now, FALSE
    FROM (VALUES
      ('wanderer',     10),
      ('path_trodden', 25),
      ('path_sworn',   50),
      ('path_forged',  75),
      ('saga_scribed', 100),
      ('saga_bound',   125),
      ('saga_eternal', 148)
    ) AS v(slug, level_threshold)
    WHERE v.level_threshold >  v_pre_char_level
      AND v.level_threshold <= v_post_char_level
    ON CONFLICT (user_id, title_id) DO NOTHING;
  END IF;

  -- Step 8.3: cross-build distinction titles. Reuses 00043's helper —
  -- the helper does the rank-distribution scan + predicate logic once.
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
-- record_session_xp_batch — production save_workout hot-path RPC (Phase 26d Task 2)
--
-- Diff vs 00057: same three blocks as record_set_xp (body-part / character-
-- level / cross-build INSERTs) appended after the Step 7 peak_loads UPSERT.
-- Pre-state captured ONCE before Step 6; post-state re-SELECTed once after
-- Step 6 lands. No restructuring of the per-set inner loop — the new state
-- is captured at the workout level, not per-set, so it has zero per-set cost.
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
  -- Phase 26d Task 2: title detection state.
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

  SELECT bodyweight_kg INTO v_bodyweight_kg
  FROM public.profiles
  WHERE id = v_user_id;
  v_bodyweight_f := COALESCE(v_bodyweight_kg, 0)::float8;

  -- Phase 26d Task 2: capture pre-rank map + pre-character-level ONCE
  -- before any work happens. Missing rows COALESCE to rank 1 inside the
  -- threshold-crossing query below.
  SELECT
    COALESCE(jsonb_object_agg(body_part, rank), '{}'::jsonb),
    COALESCE(SUM(total_xp), 0)
  INTO v_pre_ranks, v_pre_total_xp
  FROM public.body_part_progress
  WHERE user_id = v_user_id;
  v_pre_char_level := public.rpg_rank_for_xp(v_pre_total_xp);

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
      v_cap_f     := CASE WHEN v_weekly_vol[v_bp_idx] >= 20 THEN 0.5 ELSE 1.0 END;

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

  -- Phase 26d Task 2: title detection — runs AFTER body_part_progress + peak
  -- writes have landed. Capture post-state via a single re-SELECT (≤ 6 rows).
  SELECT
    COALESCE(jsonb_object_agg(body_part, rank), '{}'::jsonb),
    COALESCE(SUM(total_xp), 0)
  INTO v_post_ranks, v_post_total_xp
  FROM public.body_part_progress
  WHERE user_id = v_user_id;
  v_post_char_level := public.rpg_rank_for_xp(v_post_total_xp);

  -- Step 8.1: body-part rank crossings. VALUES list mirrors
  -- lib/features/rpg/data/title_thresholds_table.dart row-for-row.
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
  -- COALESCE to 1 on both sides:
  --   * pre missing → no prior body_part_progress row → user was at rank 1
  --   * post missing → this RPC didn't write to that body part (no XP earned
  --     for it this call), so the threshold > 1 filter blocks every row and
  --     no spurious INSERTs fire.
  WHERE v.rank_threshold > COALESCE((v_pre_ranks  ->> v.body_part)::int, 1)
    AND v.rank_threshold <= COALESCE((v_post_ranks ->> v.body_part)::int, 1)
  ON CONFLICT (user_id, title_id) DO NOTHING;

  -- Step 8.2: character-level crossings.
  IF v_post_char_level > v_pre_char_level THEN
    INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
    SELECT v_user_id, v.slug, v_now, FALSE
    FROM (VALUES
      ('wanderer',     10),
      ('path_trodden', 25),
      ('path_sworn',   50),
      ('path_forged',  75),
      ('saga_scribed', 100),
      ('saga_bound',   125),
      ('saga_eternal', 148)
    ) AS v(slug, level_threshold)
    WHERE v.level_threshold >  v_pre_char_level
      AND v.level_threshold <= v_post_char_level
    ON CONFLICT (user_id, title_id) DO NOTHING;
  END IF;

  -- Step 8.3: cross-build distinction titles via 00043's helper.
  INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
  SELECT v_user_id, cb.slug, v_now, FALSE
  FROM public.evaluate_cross_build_titles_for_user(v_user_id) cb
  ON CONFLICT (user_id, title_id) DO NOTHING;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_session_xp_batch(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.record_session_xp_batch(uuid) TO authenticated;
