-- =============================================================================
-- 00061 — Phase 26d: one-shot backfill RPC for earned_titles.
--
-- ## What this does
--
-- For a single [user_id], walks the user's current rank distribution from
-- `body_part_progress` and INSERTs any missing rows in `earned_titles` for
-- every body-part / character-level / cross-build title whose threshold the
-- user has already crossed. Always `ON CONFLICT (user_id, title_id) DO NOTHING`
-- so it cannot overwrite live `is_active` flags or earned_at timestamps —
-- this RPC is purely additive.
--
-- ## Why we walk current ranks rather than xp_events history
--
-- The Phase 18a / 26d detection contract awards a title when the rank
-- AT THE END OF A WORKOUT meets the threshold. The user's current
-- body_part_progress.rank is the post-workout rank from their latest finish;
-- by definition the user has CROSSED every threshold at or below it. Walking
-- xp_events would let us recover the exact earned_at timestamp, but it
-- would also let a mid-event-rollback produce inconsistent crossings.
-- For v1 we use `now()` as the synthetic earned_at — users won't see the
-- artificial timestamps because the Titles screen sorts by catalog kind +
-- threshold, not by earned_at. (If we add a "history" view later, we can
-- backfill with a more accurate timestamp from the latest xp_events row
-- per body_part.)
--
-- ## Idempotency
--
-- Re-running this RPC for the same user yields the same set of rows. The
-- ON CONFLICT clauses make each INSERT a no-op when a row already exists.
-- Re-running NEVER overwrites is_active or earned_at — the active flag is
-- live state owned by the user's equip choice; the backfill is read-only
-- with respect to existing rows.
--
-- ## Bootstrap-hook gating
--
-- This RPC is called from the Dart side ONCE per device per user via a
-- Hive-flag-gated `earnedTitlesBackfillProvider`. The flag prevents repeat
-- calls; users who hit a glitch can clear the flag via the existing
-- "reset local data" affordance (or by reinstalling). See
-- `lib/features/rpg/providers/earned_titles_backfill_provider.dart`.
--
-- ## Predicate shape: half-CLOSED (rank_threshold <= current_rank)
--
-- Unlike 00060's detection path which uses the half-open `(pre, post]`
-- band (only the JUST-crossed thresholds), backfill awards every title
-- at or below the user's current rank — there's no "pre" state because
-- we're catching up after the fact. A user sitting at chest rank 12 should
-- own both R5 and R10 titles after this RPC runs, regardless of whether
-- those thresholds were crossed pre-00060 or post-00060.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.backfill_earned_titles(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := now();
  v_ranks jsonb;
  v_total_xp numeric;
  v_char_level int;
BEGIN
  -- 1. Read current ranks into a jsonb map (parallels 00060's v_pre_ranks
  --    capture pattern). Missing body-part rows COALESCE to rank 1 inside
  --    the threshold filter below — same convention as 00060.
  SELECT COALESCE(jsonb_object_agg(body_part, rank), '{}'::jsonb)
  INTO v_ranks
  FROM public.body_part_progress
  WHERE user_id = p_user_id;

  -- 2. Body-part titles — insert any whose rank_threshold <= current rank.
  --    The VALUES list mirrors lib/features/rpg/data/title_thresholds_table.dart
  --    EXACTLY; the unit test from Task 1 enforces row-for-row parity. The
  --    tuples are copied verbatim from 00060 (where the same list gates the
  --    detection-time INSERT).
  INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
  SELECT p_user_id, v.slug, v_now, FALSE
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
  -- Half-CLOSED: insert every title at or below the user's current rank for
  -- that body part. COALESCE to 1 if the body_part row doesn't exist (user
  -- never trained that part — every threshold > 1 is filtered out).
  WHERE v.rank_threshold <= COALESCE((v_ranks ->> v.body_part)::int, 1)
  ON CONFLICT (user_id, title_id) DO NOTHING;

  -- 3. Character-level titles — derive level from total XP.
  SELECT COALESCE(SUM(total_xp), 0)
  INTO v_total_xp
  FROM public.body_part_progress
  WHERE user_id = p_user_id;
  v_char_level := public.rpg_rank_for_xp(v_total_xp);

  INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
  SELECT p_user_id, v.slug, v_now, FALSE
  FROM (VALUES
    ('wanderer',     10),
    ('path_trodden', 25),
    ('path_sworn',   50),
    ('path_forged',  75),
    ('saga_scribed', 100),
    ('saga_bound',   125),
    ('saga_eternal', 148)
  ) AS v(slug, level_threshold)
  WHERE v.level_threshold <= v_char_level
  ON CONFLICT (user_id, title_id) DO NOTHING;

  -- 4. Cross-build distinction titles. Reuses the STABLE PARALLEL SAFE helper
  --    from migration 00043 — single line vs re-inlining the five predicate
  --    blocks. Same simplification used in 00060 Step 8.3.
  INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
  SELECT p_user_id, cb.slug, v_now, FALSE
  FROM public.evaluate_cross_build_titles_for_user(p_user_id) cb
  ON CONFLICT (user_id, title_id) DO NOTHING;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.backfill_earned_titles(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.backfill_earned_titles(uuid) TO authenticated;
