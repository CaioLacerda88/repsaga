-- =============================================================================
-- 00057 — Phase 24c Phase C: wire bodyweight-as-load semantics into the XP RPCs
--
-- ## What this does
--
-- CREATE OR REPLACE FUNCTION for the three XP-computation RPCs to compute
-- `effective_weight = COALESCE(profiles.bodyweight_kg, 0) + sets.weight` for
-- exercises flagged `uses_bodyweight_load = TRUE` (per migration 00056), and
-- pass that effective weight into BOTH the `volume_load` and `strength_mult`
-- computations. The previous bare `sets.weight` reads still apply for any
-- exercise where `uses_bodyweight_load = FALSE` (the safe default for all 200
-- default exercises and any future user-created exercise — only the curated 20
-- bodyweight slugs from 00056 see new behavior).
--
-- Snapshots TWO new keys into `xp_events.payload` per set so the audit trail
-- carries the exact load that produced the XP — even if the user later edits
-- their bodyweight or the exercise flag flips:
--
--   * `effective_load`  — numeric, the value used for volume_load + strength_mult
--   * `bodyweight_used` — boolean, was the exercise's flag TRUE for this set
--
-- Distinct semantics: `bodyweight_used = TRUE` while bodyweight_kg is still
-- NULL means the flag was on but the COALESCE fallback kept the math defined.
-- The Phase 24c-8 active-workout UI prompt nudges the user to set their
-- bodyweight in that case; meanwhile XP is correctly under-counted (effective
-- load == entered weight) without breaking the formula.
--
-- The same three RPCs Phase 24a (00054) updated:
--
--   * `record_set_xp(p_set_id uuid)`              — per-set diagnostic /
--                                                   regression entry point.
--                                                   Source: 00054.
--   * `record_session_xp_batch(p_workout_id uuid)` — production save_workout
--                                                   hot path. Source: 00054.
--   * `_rpg_backfill_chunk(p_user_id uuid, p_chunk_size int)` — historical
--                                                   replay chunk used by
--                                                   `backfill_rpg_v1`. Source:
--                                                   00054.
--
-- The wrapper `backfill_rpg_v1(uuid, int)` is NOT replaced here for the same
-- reason as 00054: it manages the cursor + checkpoint and delegates ALL XP
-- math to `_rpg_backfill_chunk`.
--
-- ## Formula chain (mirrors lib/features/rpg/domain/xp_calculator.dart)
--
-- The chain itself is UNCHANGED from 00054:
--
--   set_xp = base × intensity × strength × novelty × cap × difficulty_mult
--
-- What changes is what FEEDS `base` and `strength`:
--
--   volume_load  = max(1.0, effective_weight × reps)        -- was: sets.weight × reps
--   base         = volume_load ^ 0.65
--   strength     = clamp(effective_weight / peak, 0.4, 1.0) -- was: sets.weight / peak
--
-- Where:
--
--   effective_weight = CASE WHEN uses_bodyweight_load
--                           THEN COALESCE(sets.weight, 0) + COALESCE(profile.bodyweight_kg, 0)
--                           ELSE COALESCE(sets.weight, 0)
--                      END
--
-- ## Hot-path discipline (record_session_xp_batch)
--
-- Same discipline as Phase 24a difficulty_mult:
--
--   * `profiles.bodyweight_kg` is fetched ONCE per RPC call (single row read
--     before the per-set loop), then carried as a local numeric. NULL is
--     acceptable — the CASE expression's COALESCE makes that the same as a
--     0 kg bodyweight (graceful fallback to entered-weight semantics).
--   * `exercises.uses_bodyweight_load` rides the driving SELECT as a column
--     on the already-existing `JOIN exercises ex` (single boolean projection,
--     no per-iteration sub-select). For `record_session_xp_batch`, that
--     means it lives on `v_set_record` alongside `difficulty_mult`.
--   * `v_effective_weight_f` is computed ONCE per set in the inner loop
--     (matches the cast-to-float8-once discipline of the rest of the
--     constants).
--
-- ## Source defensiveness
--
-- All three RPCs use `COALESCE(ex.uses_bodyweight_load, FALSE)` even though
-- the column is `NOT NULL DEFAULT FALSE` per migration 00056. The COALESCE is
-- defensive against future schema changes (e.g. a hypothetical migration that
-- drops the NOT NULL constraint). Same rationale as 00054's
-- `COALESCE(difficulty_mult, 1.0)` — zero cost, real safety margin.
--
-- The `effective_weight` CASE itself wraps both `sets.weight` and
-- `bodyweight_kg` in COALESCE(..., 0) so a NULL on either side degrades to
-- "missing data treated as 0 kg" rather than NULL-poisoning the multiplication
-- chain. This is the documented graceful fallback for the "bodyweight not yet
-- set" edge case.
--
-- ## What's NOT in this migration
--
--   * No schema changes (the columns were added in 00056).
--   * No new permissions / RLS policy changes — all functions retain the same
--     SECURITY DEFINER + GRANT EXECUTE TO authenticated set in 00040 / 00054.
--   * No retroactive XP replay. `xp_events` rows written before this
--     migration's deploy do NOT get re-evaluated — Phase 24c is forward-only.
--   * No change to `backfill_rpg_v1` (the cursor wrapper). All math lives in
--     `_rpg_backfill_chunk` which IS replaced.
--   * No change to the helper functions (`rpg_intensity_for_reps`,
--     `rpg_base_xp`, `rpg_strength_mult`, `rpg_cumulative_xp_for_rank`,
--     `rpg_rank_for_xp`). They stay identical to 00040 — bodyweight-as-load
--     is applied in the calling RPC because both inputs (`sets.weight` and
--     `profiles.bodyweight_kg`) live outside any helper.
--   * No change to 00050's `AND s.weight > 0` per_set CTE filter or 00052's
--     writer-site `IF v_weight > 0` peak_loads guards. Both stay intact —
--     `exercise_peak_loads` continues to track ENTERED weight, not effective
--     weight (peak_loads is a per-exercise PR tracker; the user's bodyweight
--     fluctuates and shouldn't reshape historical PRs). The strength
--     multiplier reads peak_weight as-is, but its numerator is the new
--     `v_effective_weight` — see the per-RPC notes for why this is correct.
--
-- ## Strength-mult semantics with bodyweight loading
--
-- `strength_mult = clamp(weight / peak, 0.4, 1.0)`. With bodyweight loading,
-- the numerator becomes `effective_weight` (= bodyweight + entered) while
-- `peak` continues to be `exercise_peak_loads.peak_weight` (entered-only).
-- For pure-bodyweight exercises (entered = 0), peak_weight stays 0 forever
-- (writer-site guard), so `peakLoad <= 0` short-circuits in
-- `rpg_strength_mult` to return 1.0 — same as pre-24c behavior. For
-- weighted-bodyweight (entered > 0, e.g. dip with belt), peak gets recorded
-- against entered weight (writer-site guard fires), strength_mult ratio is
-- (effective / peak_entered) — slightly favorable, but consistent with the
-- "we measure progress against your own history" spirit of strength_mult.
-- Per docs/xp-difficulty-framework.md §4 acceptance, this is intended.
--
-- ## Idempotency
--
-- `CREATE OR REPLACE FUNCTION` is idempotent — re-running this migration is a
-- no-op against a database that already has the post-00057 function bodies.
-- No data migration runs; pre-existing xp_events rows are untouched.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- record_set_xp — per-set XP RPC (Phase 24c-4)
--
-- Diff vs 00054:
--   * New locals: `v_bodyweight_kg numeric(5,2)`, `v_uses_bodyweight_load
--     boolean`, `v_effective_weight numeric`.
--   * New SELECT before the existing exercise-meta SELECT: pulls
--     `profiles.bodyweight_kg` once for the resolved user. NULL is fine and
--     handled by COALESCE in the effective_weight CASE.
--   * Step 2 SELECT additionally returns `COALESCE(uses_bodyweight_load,
--     FALSE)` from the exercises table.
--   * NEW Step 3.5: compute `v_effective_weight` BEFORE base/strength.
--   * Step 4 `volume_load` (via `rpg_base_xp`) and `strength_mult` now read
--     `v_effective_weight` instead of `v_weight`.
--   * Step 8 payload jsonb adds `effective_load` and `bodyweight_used` keys
--     between `cap_mult` (implied — not denormalized to top level) and
--     `set_xp`. Same chain-order discipline as Phase 24a's `difficulty_mult`.
--   * Step 9 peak_loads still reads `v_weight` (entered-only) — see header
--     "Strength-mult semantics with bodyweight loading".
--
-- Mirrors lib/features/rpg/domain/xp_calculator.dart::computeSetXp +
-- tasks/rpg-xp-simulation.py — change all four sites in lockstep.
-- Phase 24c (PR #TBD) added effective_weight + bodyweight_used.
-- Phase 24a (PR #222) added difficulty_mult.
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
  -- Phase 24c bodyweight-as-load locals.
  v_bodyweight_kg        numeric(5,2);  -- user's body mass; NULL allowed
  v_uses_bodyweight_load boolean;       -- TRUE for curated 20 slugs (00056)
  v_effective_weight     numeric;       -- entered + bodyweight (or entered)
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

  -- 1.5. Phase 24c: pre-fetch user bodyweight once. NULL is acceptable —
  --      the v_effective_weight CASE below uses COALESCE(..., 0) so a
  --      missing bodyweight degrades to "use entered weight only" without
  --      poisoning the multiplication chain. This is the graceful-fallback
  --      path for the "user hasn't set their bodyweight yet" edge case;
  --      the active-workout UI (Phase 24c-8) lazy-prompts at that point.
  SELECT bodyweight_kg INTO v_bodyweight_kg
  FROM public.profiles
  WHERE id = v_user_id;

  -- 2. Resolve attribution map + difficulty_mult + uses_bodyweight_load.
  --    Phase 24c extends the 24a Step 2 fetch with the new boolean column
  --    on the same single-row exercise lookup — no extra round-trip.
  --    COALESCE on uses_bodyweight_load is defensive (column is NOT NULL
  --    DEFAULT FALSE per 00056); same rationale as the difficulty_mult
  --    COALESCE.
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

  -- 3. Fetch peak_load (entered-weight only — see header note on
  --    "Strength-mult semantics with bodyweight loading").
  SELECT peak_weight INTO v_peak
  FROM public.exercise_peak_loads
  WHERE user_id = v_user_id AND exercise_id = v_exercise_id;

  IF v_peak IS NULL THEN
    v_peak := 0;
  END IF;

  -- 3.5. Phase 24c: compute effective_weight BEFORE base/strength so both
  --      formulas see the bodyweight-aware value. Both sides of the CASE
  --      COALESCE to 0 to handle (a) entered-weight NULL (legacy data) and
  --      (b) bodyweight NULL (user hasn't set it yet — graceful fallback
  --      to entered-only semantics, matching pre-24c behavior).
  v_effective_weight := CASE
    WHEN v_uses_bodyweight_load THEN
      COALESCE(v_weight, 0) + COALESCE(v_bodyweight_kg, 0)
    ELSE
      COALESCE(v_weight, 0)
  END;

  -- 4. Compute base + intensity + strength using EFFECTIVE weight.
  --    Phase 24c: rpg_base_xp internally computes
  --    `volume_load = max(1.0, weight × reps)` then `base = volume_load^0.65`.
  --    Passing v_effective_weight here means a 70-kg lifter doing pull-ups
  --    for 8 reps gets base ≈ (70×8)^0.65 ≈ 60.5 instead of 1.0^0.65 = 1.0.
  --    Same applies to rpg_strength_mult — the numerator is now the
  --    bodyweight-aware load.
  v_base := public.rpg_base_xp(v_effective_weight, v_reps);
  v_intensity := public.rpg_intensity_for_reps(v_reps);
  IF v_weight > v_peak THEN
    v_peak := v_weight;
  END IF;
  v_strength := public.rpg_strength_mult(v_effective_weight, v_peak);

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
  --    Chain unchanged from 24a — the difference is upstream
  --    (v_base / v_strength now consume v_effective_weight).
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
  --    Phase 24c: `effective_load` and `bodyweight_used` keys added in
  --    chain order between cap_mult position (per-bp, intentionally
  --    omitted from top level) and `set_xp`. Snake-case keys match
  --    Dart's XpEvent.fromJson promotion (lib/features/rpg/models/
  --    xp_event.dart promotes payload.effective_load + payload.bodyweight_used
  --    to top-level fields). Volume_load itself is also re-derived here from
  --    v_effective_weight so the snapshot reflects the bodyweight-aware
  --    base — same value the formula consumed.
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

  -- 9. UPSERT exercise_peak_loads if weight advanced.
  --    Preserves the 00052 writer-site guard (`IF v_weight > 0`) — bodyweight
  --    sets skip the INSERT entirely. The peak tracks ENTERED weight (not
  --    effective), so a pure-bodyweight pull-up never inserts a peak row;
  --    weighted bodyweight (e.g. weighted dip) does, against entered weight.
  --    See header note on "Strength-mult semantics with bodyweight loading".
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
-- record_session_xp_batch — production save_workout hot-path RPC (Phase 24c-4)
--
-- Diff vs 00054:
--   * New local `v_bodyweight_kg numeric(5,2)` declared; pre-fetched ONCE
--     at the top of the function (after `v_user_id` resolution, before the
--     pre-fetch peaks step). NULL is fine — COALESCE in the per-set
--     effective_weight CASE handles it.
--   * Driving SELECT additionally projects `COALESCE(ex.uses_bodyweight_load,
--     FALSE)` (one new boolean column on the existing JOIN exercises ex —
--     no per-iteration sub-select, same hot-path discipline as 24a's
--     difficulty_mult column).
--   * New `v_effective_weight_f float8` declared; computed ONCE per set
--     in the inner loop alongside the rest of the per-set constant casts.
--   * `v_base_f` and `v_strength_f` now consume `v_effective_weight_f`
--     (passed to rpg_base_xp / rpg_strength_mult) instead of
--     `v_set_record.weight`.
--   * Per-set payload jsonb adds `effective_load` and `bodyweight_used`
--     keys (rounded to numeric(14,4) at the storage boundary, same
--     discipline as the other components). Volume_load also re-derived
--     from v_effective_weight_f so the snapshot reflects what the
--     formula actually consumed.
--
-- All other 00054 behavior preserved verbatim, including:
--   * Step 7's `AND s.weight > 0` per_set CTE filter (00050 bodyweight
--     bugfix). Continues to read entered weight — peak_loads remains an
--     entered-weight tracker; bodyweight is not a PR.
--   * Float8 hot-path discipline (PERF NOTE 00040 §11b).
--   * Pre-fetched peaks map / weekly_vol arrays.
--   * Bulk INSERT via UNNEST.
--   * difficulty_mult per-set carry on the driving SELECT.
--
-- Mirrors lib/features/rpg/domain/xp_calculator.dart::computeSetXp +
-- tasks/rpg-xp-simulation.py — change all four sites in lockstep.
-- Phase 24c (PR #TBD) added effective_weight + bodyweight_used.
-- Phase 24a (PR #222) added difficulty_mult.
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
  v_difficulty_mult_f float8;
  -- Phase 24c bodyweight-as-load: bodyweight is fetched ONCE per RPC call
  -- (see Step 1.5 below); effective_weight is computed ONCE per set in the
  -- inner loop. Both as float8 to match the rest of the hot-path discipline.
  v_bodyweight_kg     numeric(5,2);  -- NULL allowed; COALESCE handles it
  v_bodyweight_f      float8;        -- cast once, reused per set
  v_effective_weight_f float8;
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

  -- ── Step 1.5: Phase 24c — pre-fetch user bodyweight once. NULL is
  --    acceptable; the per-set effective_weight CASE COALESCEs to 0,
  --    degrading to "entered weight only" semantics for that user until
  --    they set their bodyweight (Phase 24c-8 active-workout prompt).
  --    Cast to float8 once for hot-path reuse — matches the discipline of
  --    the rest of the per-set constants.
  SELECT bodyweight_kg INTO v_bodyweight_kg
  FROM public.profiles
  WHERE id = v_user_id;
  v_bodyweight_f := COALESCE(v_bodyweight_kg, 0)::float8;

  -- ── Step 2: pre-fetch peaks for every distinct exercise in this session.
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

  -- ── Step 4: iterate sets in (we.order, s.set_number) order. For each set,
  --   compute per-bp XP and accumulate into the bulk INSERT arrays plus the
  --   per-bp running totals.
  --
  -- Phase 24c: the driving SELECT below additionally carries
  -- `COALESCE(ex.uses_bodyweight_load, FALSE)` (one new boolean column on
  -- the existing JOIN exercises ex — no extra round-trip). Same hot-path
  -- discipline as 24a's difficulty_mult: per-set value rides the driving
  -- query, gets used directly in the inner loop, no per-iteration sub-select.
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
    -- Resolve attribution map (NULL → primary muscle group at 1.0 share)
    v_attribution := v_set_record.xp_attribution;
    IF v_attribution IS NULL
       OR v_attribution = 'null'::jsonb
       OR v_attribution = '{}'::jsonb THEN
      v_attribution := jsonb_build_object(v_set_record.primary_muscle, 1.0);
    END IF;

    -- Look up current peak for this exercise from the running map.
    -- Peak tracks ENTERED weight (not effective); see header note on
    -- "Strength-mult semantics with bodyweight loading".
    v_peak := COALESCE(
                (v_peaks_map ->> v_set_record.exercise_id::text)::numeric,
                0
              );
    -- Advance peak BEFORE strength_mult — matches record_set_xp behavior.
    -- Compares against entered weight, not effective.
    IF v_set_record.weight > v_peak THEN
      v_peak := v_set_record.weight;
      v_peaks_map := v_peaks_map
        || jsonb_build_object(v_set_record.exercise_id::text, v_peak);
    END IF;

    -- Phase 24c: compute effective weight ONCE per set (matches the
    -- cast-to-float8-once discipline of the rest of the constants). The
    -- COALESCE on the entered weight handles legacy NULL data; the
    -- bodyweight COALESCE happened at the v_bodyweight_f assignment above.
    v_effective_weight_f := CASE
      WHEN v_set_record.uses_bodyweight_load THEN
        COALESCE(v_set_record.weight, 0)::float8 + v_bodyweight_f
      ELSE
        COALESCE(v_set_record.weight, 0)::float8
    END;

    -- Phase 24c: rpg_base_xp + rpg_strength_mult now consume the effective
    -- weight. The helper signatures are unchanged — we just feed them a
    -- bodyweight-aware numerator. See migration header for chain diagram.
    v_base_f      := public.rpg_base_xp(v_effective_weight_f::numeric, v_set_record.reps)::float8;
    v_intensity_f := public.rpg_intensity_for_reps(v_set_record.reps)::float8;
    v_strength_f  := public.rpg_strength_mult(v_effective_weight_f::numeric, v_peak)::float8;
    -- Phase 24a: per-set difficulty_mult cast to float8 once, then carried
    -- through the inner per-bp loop with the rest of the constants. The
    -- value lives on `v_set_record` (joined in the driving SELECT above)
    -- — no per-iteration re-query, no jsonb lookup.
    v_difficulty_mult_f := v_set_record.difficulty_mult::float8;

    v_set_xp_f := 0;
    v_event_attribution := '{}'::jsonb;

    -- Per-body-part fan-out. Chain unchanged from 24a — what changed is
    -- upstream (v_base_f / v_strength_f now consume v_effective_weight_f).
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

    -- Phase 24c: effective_load + bodyweight_used keys added in chain
    -- order between the (intentionally-omitted) cap_mult position and
    -- set_xp. Snake-case keys match Dart's XpEvent.fromJson promotion
    -- (lib/features/rpg/models/xp_event.dart). volume_load is also
    -- re-derived here from v_effective_weight_f so the snapshot reflects
    -- the bodyweight-aware base — same value the formula consumed.
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

  -- ── Step 5: bulk INSERT xp_events.
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

  -- ── Step 6: UPSERT body_part_progress per body part.
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

  -- ── Step 7: UPSERT exercise_peak_loads per advanced exercise.
  --    Preserves the 00050 `AND s.weight > 0` per_set CTE filter — peak
  --    tracks ENTERED weight only. See header note on "Strength-mult
  --    semantics with bodyweight loading".
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
      AND s.weight > 0  -- 00050 bugfix: exclude bodyweight from peak_loads
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
-- _rpg_backfill_chunk — historical replay chunk (Phase 24c-4 backfill)
--
-- Diff vs 00054:
--   * New local `v_bodyweight_kg numeric(5,2)` declared; pre-fetched ONCE
--     before the chunk loop (matches record_session_xp_batch discipline).
--   * Driving SELECT additionally projects `COALESCE(ex.uses_bodyweight_load,
--     FALSE)` (one new column on the existing JOIN exercises ex).
--   * New `v_effective_weight numeric` declared; computed ONCE per set
--     in the chunk loop.
--   * `rpg_base_xp` and `rpg_strength_mult` now consume `v_effective_weight`
--     instead of `r_set.weight`.
--   * Payload jsonb adds `effective_load` and `bodyweight_used` keys in
--     chain order between `cap_mult` (omitted) and `set_xp`. Volume_load
--     also re-derived from v_effective_weight.
--
-- All 00054 behavior preserved verbatim, including the writer-site
-- `IF r_set.weight > 0` peak_loads guard (peak tracks entered, not effective).
--
-- Mirrors lib/features/rpg/domain/xp_calculator.dart::computeSetXp +
-- tasks/rpg-xp-simulation.py — change all four sites in lockstep.
-- Phase 24c (PR #TBD) added effective_weight + bodyweight_used.
-- Phase 24a (PR #222) added difficulty_mult.
--
-- Note: the wrapper `backfill_rpg_v1(uuid, int)` is intentionally NOT replaced
-- in this migration. It manages the cursor, advisory lock, and checkpoint —
-- ALL XP math lives in this `_rpg_backfill_chunk` function. Replacing the
-- wrapper would be churn-only.
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
  -- Phase 24c bodyweight-as-load locals. v_bodyweight_kg fetched ONCE
  -- before the chunk loop (single profile read). v_effective_weight
  -- computed per set inside the loop.
  v_bodyweight_kg    numeric(5,2);  -- NULL allowed; COALESCE handles it
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

  -- Phase 24c: pre-fetch user bodyweight once for the entire chunk. NULL
  -- is fine — the per-set effective_weight CASE COALESCEs to 0, which
  -- matches pre-24c "entered-weight only" semantics. Backfill replays
  -- against the user's CURRENT bodyweight (not historical) — this matches
  -- the documented forward-only semantics: we don't have historical
  -- bodyweight values, and re-using the current one is the best
  -- approximation while keeping backfill deterministic. Documented in
  -- docs/xp-difficulty-framework.md §4 (acceptance: "backfill uses current
  -- bodyweight; users who lost/gained mass will see slight skew that
  -- self-corrects as new sets accumulate").
  SELECT bodyweight_kg INTO v_bodyweight_kg
  FROM public.profiles
  WHERE id = p_user_id;

  -- Phase 24c: driving SELECT projects `ex.uses_bodyweight_load` (one new
  -- column on the existing JOIN exercises ex). COALESCE-defended at FALSE
  -- even though 00056 makes the column NOT NULL DEFAULT FALSE.
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

    -- Peak tracks ENTERED weight (not effective); see header note.
    SELECT peak_weight INTO v_peak
    FROM public.exercise_peak_loads
    WHERE user_id = p_user_id AND exercise_id = r_set.exercise_id;
    IF v_peak IS NULL THEN v_peak := 0; END IF;
    IF r_set.weight > v_peak THEN v_peak := r_set.weight; END IF;

    -- Phase 24c: compute effective weight once per set. Both sides of the
    -- CASE COALESCE to 0 to handle NULL entered weight (legacy data) and
    -- NULL bodyweight (user hasn't set it yet).
    v_effective_weight := CASE
      WHEN r_set.uses_bodyweight_load THEN
        COALESCE(r_set.weight, 0) + COALESCE(v_bodyweight_kg, 0)
      ELSE
        COALESCE(r_set.weight, 0)
    END;

    -- Phase 24c: rpg_base_xp + rpg_strength_mult consume effective weight.
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
      v_cap     := CASE WHEN v_weekly_vol >= 20 THEN 0.5 ELSE 1.0 END;

      -- Chain unchanged from 24a — what changed is upstream
      -- (v_base / v_strength now consume v_effective_weight).
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

    -- Phase 24c: effective_load + bodyweight_used keys added in chain
    -- order between cap_mult position (omitted) and set_xp. Snake-case
    -- keys match Dart's XpEvent.fromJson promotion. volume_load
    -- re-derived from v_effective_weight.
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

    -- Peak loads — preserves 00052 writer-site `IF r_set.weight > 0` guard.
    -- Continues to track ENTERED weight (not effective); see header note.
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
-- the wrapper function `backfill_rpg_v1` is callable by clients. Mirrors the
-- intentional grant omission in 00040 / 00052 / 00054.
