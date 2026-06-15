-- =============================================================================
-- 00077 — Phase 38a: cardio save gate (close the latent strength
--          mis-attribution bug before the cardio feature ships)
--
-- ## The bug (docs/cardio-stat-plan.md §1)
--
-- All three XP writers (`record_set_xp`, `record_session_xp_batch`,
-- `_rpg_backfill_chunk`) gate sets only on
-- `is_completed AND set_type='working' AND reps >= 1`, then run the
-- weight×reps strength formula over EVERY `xp_attribution` key — including
-- `'cardio'`. The 8 default cardio exercises (treadmill, rowing_machine,
-- sled_push, …) carry `xp_attribution = {"cardio":1.0}` and ARE selectable
-- in the exercise picker today. A cardio set logged with `weight=0,
-- reps>=1` therefore passes the gate, earns the `volume_load =
-- GREATEST(1.0, 0×reps)` floor, and silently writes a real
-- `body_part_progress` row for `cardio` plus `xp_events` rows — invisible
-- in the UI (cardio is excluded from the 6 active body parts) but real in
-- the DB.
--
-- Sealing this gate also structurally closes the reverse direction
-- (§2.6): a run logged with reps can never farm a strength rank, because
-- cardio-attributed sets never enter the weight×reps path at all.
--
-- ## The gate — mechanism choice
--
-- Candidate (a): exclude sets whose exercise `muscle_group = 'cardio'`
-- from the source query feeding the weight×reps accumulation.
-- Candidate (b): skip the `'cardio'` attribution key inside the per-bp
-- distribution loop.
--
-- We pick **(a)** — exclude at the source — because (b) is structurally
-- leaky in this SQL: both batch and backfill INSERT the `xp_events` row
-- (or accumulate the event arrays) BEFORE/OUTSIDE the per-key loop, so
-- skipping only the key would still emit a zero-XP `xp_events` row for
-- every cardio set. That row pollutes the post-session summary, the
-- weekly share re-derivation JOINs of future sessions, and the re-save
-- reversal pattern. Excluding the set at the source query is one line per
-- writer, produces NO xp_events row, NO body_part_progress row, and NO
-- strength peak bookkeeping for cardio sets — "cleanly ignored
-- pre-feature", exactly the contract. The muscle_group gate is complete
-- for current data: every exercise carrying a `'cardio'` attribution key
-- has `muscle_group='cardio'` (8 default cardio slugs, 00040/00055), and
-- user-created cardio exercises get the NULL-attribution fallback
-- `{muscle_group: 1.0}` — also caught by muscle_group.
--
-- ## Writer audit (cluster: check-violation-needs-writer-audit)
--
-- The phase brief named the two RPCs; the writer audit found a THIRD
-- writer of the same invariant — `_rpg_backfill_chunk` (historical
-- replay) — with the identical reps>=1 gate and per-key distribution.
-- Without gating it, any user backfill over a history containing cardio
-- sets would reintroduce the exact bug this migration closes. All three
-- writers are redefined here with the same gate.
--
-- `save_workout` (00005/00063) needs NO change: it persists raw sets
-- (legitimate workout history — the bug is XP mis-attribution, not set
-- persistence) and delegates all XP to `record_session_xp_batch`. Its
-- BUG-RPG-001 reversal pattern is also safe: post-gate, cardio sets
-- produce no xp_events, so there is nothing cardio to reverse; any
-- PRE-gate latent cardio xp_events on a re-saved workout are reversed
-- (floored at 0) and never re-created — re-save self-heals the latent
-- pollution.
--
-- ## What is intentionally NOT touched
--
--   * The `'cardio' -> 7` attribution-index map, the 7-wide vol arrays,
--     and the weekly-cardio prefetch in record_session_xp_batch stay —
--     they are dead-but-harmless under the gate and are the pre-wired
--     slots the full cardio feature (Phase 38+) will light up.
--   * The batch peaks_map prefetch is not filtered: it is a read-only
--     lookup map keyed by exercise_id, and entries for gated sets are
--     simply never consulted by the loop.
--   * Existing latent cardio rows (if any) are not deleted: they are
--     invisible in every UI surface (cardio is outside activeBodyParts,
--     the character_state view, and the title IN-lists) and re-save
--     self-heals them. Cleanup, if wanted, rides the cardio feature
--     migration.
--
-- Function bodies below are verbatim from 00065 except for the gate
-- lines, each marked with "Phase 38a cardio save gate".
-- No new tables/objects are created — function replacement preserves
-- existing ACLs, and the original REVOKE/GRANT pairs are re-stated
-- verbatim (cluster supabase-cli-latest-grant-drift does not apply).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- PART A — record_set_xp (verbatim 00065 PART D + cardio gate)
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
  -- Phase 29 v2 PR 2 reviewer fix — capture novelty/cap as resolved for
  -- the dominant BP so they can be persisted in `xp_events.payload`,
  -- matching SetXpComponents.toJson() (lib/features/rpg/domain/xp_calculator.dart).
  v_dom_novelty     numeric;
  v_dom_cap         numeric;
  -- Phase 26d Task 2 title detection state — restored after Phase 29 v2
  -- PR 2 dropped the title-award block. Mirrors the same captures in
  -- record_session_xp_batch so per-set diagnostic calls also award
  -- titles. See the longer comment in that function.
  v_pre_ranks       jsonb;
  v_post_ranks      jsonb;
  v_pre_total_xp    numeric;
  v_post_total_xp   numeric;
  v_pre_char_level  int;
  v_post_char_level int;
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

  -- Phase 26d Task 2 — capture pre-rank map + pre-character-level ONCE
  -- before the body_part_progress write below. Missing rows COALESCE to
  -- rank 1 inside the threshold-crossing query.
  --
  -- character_level matches the canonical formula in the `character_state`
  -- view (migration 00040 §9): floor((Σ active_ranks − N_active) / 4) + 1,
  -- restricted to the 6 active body parts (cardio excluded). The earlier
  -- `rpg_rank_for_xp(SUM(total_xp))` formula carried over from 00060 was a
  -- bug — `rpg_rank_for_xp` is a PER-body-part XP→rank function, not a
  -- character-level reduction; applied to a sum across body parts it
  -- produced silently-incorrect title-threshold checks.
  SELECT
    COALESCE(jsonb_object_agg(body_part, rank), '{}'::jsonb),
    COALESCE(SUM(total_xp), 0)
  INTO v_pre_ranks, v_pre_total_xp
  FROM public.body_part_progress
  WHERE user_id = v_user_id;
  SELECT GREATEST(1, FLOOR((COALESCE(SUM(rank), 0) - COUNT(*)) / 4.0)::int + 1)
  INTO v_pre_char_level
  FROM public.body_part_progress
  WHERE user_id = v_user_id
    AND body_part IN ('chest','back','legs','shoulders','arms','core');

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

  -- Phase 38a cardio save gate (cluster: check-violation-needs-writer-audit;
  -- docs/cardio-stat-plan.md §1/§2.6). Cardio-attributed sets must never
  -- enter the strength weight×reps path: RETURN before the xp_events
  -- INSERT, the body_part_progress distribution, the peak-load writes, and
  -- the title evaluation. Pre-feature, a cardio set is cleanly ignored;
  -- the cardio feature will route these to its own earning function.
  IF v_primary_muscle = 'cardio' THEN RETURN; END IF;

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
  -- Initialize dominant-BP captures — guards the rare case where every
  -- attribution share is 0 (loop body skips, v_dom_novelty / v_dom_cap
  -- otherwise undefined). Falls back to "no discount, no cap".
  v_dom_novelty := 1.0;
  v_dom_cap     := 1.0;

  FOR v_attr_key, v_attr_share IN
    SELECT key, value::numeric FROM jsonb_each_text(v_attribution)
  LOOP
    IF v_attr_share <= 0 THEN CONTINUE; END IF;

    -- Parity contract — session_vol / weekly_vol are SHARE-COUNT
    -- accumulators (Python sim `novelty_count[bp] += share`), not XP.
    -- Re-derive share by JOINing each prior xp_events row through
    -- sets → workout_exercises → exercises.xp_attribution and reading
    -- the share for v_attr_key. Without this, prior events' XP values
    -- (typically 20–100 each) over-discount novelty by 10–100× vs the
    -- Dart calculator + fixture oracle and trip the weekly cap on a
    -- single working set.
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

    -- Persist the novelty/cap as resolved for the DOMINANT BP into the
    -- payload below — matches the per-set diagnostic contract.
    IF v_attr_key = v_dom_part THEN
      v_dom_novelty := v_novelty;
      v_dom_cap     := v_cap;
    END IF;

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
  -- chain order, mirroring SetXpComponents.toJson() in Dart. The
  -- novelty/cap values reflect the DOMINANT BP for the set; the
  -- per-attribution-key values are not persisted (the per-bp XP in
  -- `xp_events.attribution` already encodes them).
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

  -- Phase 26d Task 2 title detection — restored after Phase 29 v2 PR 2.
  -- Mirrors record_session_xp_batch's title-award block so the per-set
  -- diagnostic entry point also INSERTs earned_titles rows on threshold
  -- crossings. Capture post-state AFTER body_part_progress has been
  -- updated (above) so the character-level reduction sees the new ranks.
  SELECT
    COALESCE(jsonb_object_agg(body_part, rank), '{}'::jsonb),
    COALESCE(SUM(total_xp), 0)
  INTO v_post_ranks, v_post_total_xp
  FROM public.body_part_progress
  WHERE user_id = v_user_id;
  -- See pre-snapshot above for the formula-correctness rationale.
  SELECT GREATEST(1, FLOOR((COALESCE(SUM(rank), 0) - COUNT(*)) / 4.0)::int + 1)
  INTO v_post_char_level
  FROM public.body_part_progress
  WHERE user_id = v_user_id
    AND body_part IN ('chest','back','legs','shoulders','arms','core');

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

  RETURN;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_set_xp(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.record_set_xp(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- PART B — record_session_xp_batch (verbatim 00065 PART E + cardio gate)
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
  -- Phase 29 v2 PR 2 reviewer fix — capture novelty/cap as resolved for
  -- the dominant BP so they can be persisted in `xp_events.payload`,
  -- matching SetXpComponents.toJson() in Dart.
  v_dom_novelty_f    float8;
  v_dom_cap_f        float8;
  -- Phase 26d Task 2 title detection state — restored after 00065 PR 2
  -- accidentally dropped the title-award block when rewriting this
  -- function for the Phase 29 v2 11-multiplier chain. Without these
  -- captures, no `earned_titles` row is INSERTed when a workout crosses
  -- a body-part / character-level title threshold, so the celebration
  -- queue's TitleUnlockEvent fires client-side but `equip_title` finds
  -- no row to flip → silent failure. See Multi-celebration E2E (S2).
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

  -- Pre-fetch profile.
  SELECT bodyweight_kg, gender INTO v_bodyweight_kg, v_gender
  FROM public.profiles WHERE id = v_user_id;
  v_bodyweight_f := COALESCE(v_bodyweight_kg, 0)::float8;

  -- Phase 26d Task 2 — capture pre-rank map + pre-character-level ONCE
  -- before any body_part_progress write happens. Missing rows COALESCE
  -- to rank 1 inside the threshold-crossing query at the bottom.
  --
  -- character_level matches the canonical formula in the `character_state`
  -- view (migration 00040 §9): floor((Σ active_ranks − N_active) / 4) + 1,
  -- restricted to the 6 active body parts. See record_set_xp for the bug
  -- this replaces.
  SELECT
    COALESCE(jsonb_object_agg(body_part, rank), '{}'::jsonb),
    COALESCE(SUM(total_xp), 0)
  INTO v_pre_ranks, v_pre_total_xp
  FROM public.body_part_progress
  WHERE user_id = v_user_id;
  SELECT GREATEST(1, FLOOR((COALESCE(SUM(rank), 0) - COUNT(*)) / 4.0)::int + 1)
  INTO v_pre_char_level
  FROM public.body_part_progress
  WHERE user_id = v_user_id
    AND body_part IN ('chest','back','legs','shoulders','arms','core');

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

  -- Prior weekly SHARE-COUNT per body_part (xp_events outside this
  -- session, in the trailing 7d window). Parity with Python sim
  -- `weekly_count[body_part] += share` — the cap_mult fires at ≥ 15
  -- EFFECTIVE SETS, not 15 XP. We can't read share directly from
  -- xp_events.attribution (which stores XP), so we re-derive it by
  -- JOINing through sets → workout_exercises → exercises.xp_attribution
  -- and summing the share value the original session computed against.
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
      -- Phase 38a cardio save gate (cluster:
      -- check-violation-needs-writer-audit) — cardio sets never enter the
      -- strength weight×reps accumulation. See migration header.
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
    -- Initialize dominant-BP captures — see record_set_xp for rationale.
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

      -- Persist the novelty/cap as resolved for the DOMINANT BP into the
      -- payload below — matches the per-set diagnostic contract.
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

      -- Parity contract — `session_vol` and `weekly_vol` are SHARE-COUNT
      -- accumulators (Python sim `novelty_count[body_part] += share`),
      -- NOT XP-earned. The novelty_denominator (15) and weekly_cap_sets
      -- (15) are calibrated against effective-sets-per-body-part. Storing
      -- XP here over-discounts novelty by 10–100× and would trigger the
      -- weekly cap on a single working set. v_bp_total stays XP because
      -- it's the materialized body_part_progress.total_xp delta.
      v_session_vol[v_bp_idx] := v_session_vol[v_bp_idx] + v_attr_share;
      v_weekly_vol[v_bp_idx]  := v_weekly_vol[v_bp_idx]  + v_attr_share;
      v_bp_total[v_bp_idx]    := v_bp_total[v_bp_idx]    + v_xp_for_bp_f;
    END LOOP;

    -- See record_set_xp for the dominant-BP semantics of novelty/cap.
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

  -- Preserve 00050 bugfix — peak_loads tracks ENTERED weight only.
  -- Phase 38a cardio save gate: exercises JOIN + muscle_group filter added
  -- so cardio sets (e.g. a weighted sled_push) skip strength peak
  -- bookkeeping here, matching record_set_xp's early RETURN.
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
      -- Phase 38a cardio save gate — see per_set CTE above.
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

  -- Phase 26d Task 2 title detection — restored after Phase 29 v2 PR 2.
  -- Runs AFTER body_part_progress + peak writes have landed. Capture
  -- post-state via a single re-SELECT (≤ 6 rows).
  SELECT
    COALESCE(jsonb_object_agg(body_part, rank), '{}'::jsonb),
    COALESCE(SUM(total_xp), 0)
  INTO v_post_ranks, v_post_total_xp
  FROM public.body_part_progress
  WHERE user_id = v_user_id;
  -- See pre-snapshot above for the formula-correctness rationale.
  SELECT GREATEST(1, FLOOR((COALESCE(SUM(rank), 0) - COUNT(*)) / 4.0)::int + 1)
  INTO v_post_char_level
  FROM public.body_part_progress
  WHERE user_id = v_user_id
    AND body_part IN ('chest','back','legs','shoulders','arms','core');

  -- Step 8.1: body-part rank crossings. VALUES list mirrors
  -- lib/features/rpg/data/title_thresholds_table.dart row-for-row; the
  -- Dart-side integrity test fails the suite if the two drift.
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

  -- Step 8.3: cross-build distinction titles. Reuses 00043's helper.
  INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
  SELECT v_user_id, cb.slug, v_now, FALSE
  FROM public.evaluate_cross_build_titles_for_user(v_user_id) cb
  ON CONFLICT (user_id, title_id) DO NOTHING;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_session_xp_batch(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.record_session_xp_batch(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- PART C — _rpg_backfill_chunk (verbatim 00065 PART F + cardio gate)
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
      -- Phase 38a cardio save gate (cluster:
      -- check-violation-needs-writer-audit) — historical replay must not
      -- reintroduce the cardio mis-attribution the live RPCs now gate.
      -- Excluded rows are never selected, so cursor pagination over
      -- (started_at, id) is unaffected.
      AND ex.muscle_group::text <> 'cardio'
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

      -- Parity contract — share-count, not XP. See record_set_xp /
      -- record_session_xp_batch for the longer comment.
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
      WHERE e.user_id = p_user_id
        AND e.session_id = r_set.workout_id
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
      WHERE e.user_id = p_user_id
        AND e.occurred_at > v_now - interval '7 days'
        AND e.occurred_at <= v_now
        AND e.id <> v_event_id
        AND e.set_id IS NOT NULL;

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
