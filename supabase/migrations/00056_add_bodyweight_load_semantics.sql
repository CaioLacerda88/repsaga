-- =============================================================================
-- Phase 24c — Bodyweight-as-load semantics
-- Migration: 00056_add_bodyweight_load_semantics
--
-- Adds the schema surface needed to compute `effective_load = profile.bodyweight_kg
-- + sets.weight` for curated bodyweight strength movements (pull-ups, dips,
-- push-ups, pistol squats, etc. per docs/xp-difficulty-framework.md §4).
--
-- Two columns:
--   1. profiles.bodyweight_kg numeric(5,2) NULL — user-opt-in body mass
--      (range CHECK 25–250 kg, NULL meaning "not set yet"; the SQL RPCs in
--      migration 00057 fall back to COALESCE(bodyweight_kg, 0) so a missing
--      value silently under-counts XP without breaking math).
--   2. exercises.uses_bodyweight_load BOOLEAN NOT NULL DEFAULT FALSE — which
--      exercises participate in the bodyweight-additive load model. FALSE is
--      the safe default for the existing 200 default exercises and any
--      future user-created exercise.
--
-- Forward-only: xp_events.payload snapshots effective_load + bodyweight_used
-- at write time (Phase 24c-4, migration 00057); past xp_events are NOT
-- replayed. Tier multipliers (00053) are orthogonal — both apply.
--
-- See docs/xp-difficulty-framework.md §4 for the rationale (mechanical work
-- proxy: a 70 kg lifter doing pull-ups for 8 reps moves ~70 × 8 = 560 kg-reps
-- of real work; logging weight=0 zeroes out volume_load, which is the bug).
-- See PROJECT.md §3 → Phase 24c for the rollout plan.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. profiles.bodyweight_kg — optional user body mass for load calculation.
--    Range CHECK 25–250 kg covers realistic adult body mass with margin
--    (lightest competitive female ~40 kg, heaviest documented strongman ~200
--    kg; 25/250 widens that for safety without admitting nonsense values).
--    NULL is meaningful and explicit — the user has not yet set their
--    bodyweight. The active workout UI (Phase 24c-8) lazy-prompts on the
--    first qualifying set.
-- ---------------------------------------------------------------------------

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS bodyweight_kg numeric(5,2);

ALTER TABLE public.profiles
  ADD CONSTRAINT valid_profiles_bodyweight_kg
    CHECK (bodyweight_kg IS NULL OR (bodyweight_kg >= 25 AND bodyweight_kg <= 250));

-- ---------------------------------------------------------------------------
-- 2. exercises.uses_bodyweight_load — flags exercises whose effective load
--    includes the lifter's bodyweight. Default FALSE keeps all 200 existing
--    default exercises and any future user-created exercise on the
--    pre-Phase-24c semantics until explicitly curated.
-- ---------------------------------------------------------------------------

ALTER TABLE public.exercises
  ADD COLUMN IF NOT EXISTS uses_bodyweight_load BOOLEAN NOT NULL DEFAULT FALSE;

-- ---------------------------------------------------------------------------
-- 3. Per-slug curation. Each slug is verified against the live default
--    exercise library (200 rows after Phase 24b / migration 00055). Tier
--    alignment shown in the comment is from 00053 (Phase 24a) — bodyweight
--    load semantics here are orthogonal to those tier multipliers; both
--    apply to the same xp_events.payload at write time.
--
--    Curation source: docs/xp-difficulty-framework.md §4 named exercises +
--    same-family additions (24b additions where the family is already
--    bodyweight-loaded by character).
-- ---------------------------------------------------------------------------

UPDATE public.exercises SET uses_bodyweight_load = TRUE
WHERE slug IN (
  -- Pull family (T2: §4 named pull-up + chin-up; same-family wide-grip).
  'pull_up',                -- §4 named, T2 (00053: 1.19)
  'chin_up',                -- §4 named (variant of pull-up), T2 (00053: 1.19)
  'wide_grip_pull_up',      -- 24b family addition; same family as pull_up (T2)
  -- Dip family (T2: §4 strict dip; same-family ring + muscle-up).
  'dips',                   -- §4 named "strict dip", T2 (00053: 1.19)
  'ring_dip',               -- 24b family addition; same family as dips (T2)
  'muscle_up',              -- 24b family addition; full-bodyweight pull + push (T2 family)
  -- Push-up family (T3: §4 push-up + archer push-up; same-family variants).
  'push_up',                -- §4 named, T3 (00053: 1.11)
  'wide_push_up',           -- 24b family addition; push-up variant (T3, 00053: 1.11)
  'incline_push_up',        -- 24b family addition; push-up variant (T3, 00053: 1.11)
  'decline_push_up',        -- 24b family addition; push-up variant (T3, 00053: 1.11)
  'diamond_push_up',        -- 24b family addition; push-up variant (T3, 00053: 1.11)
  'close_grip_push_up',     -- 24b family addition; push-up variant (T3, 00053: 1.11)
  'archer_push_up',         -- §4 named (single-arm assisted), T2 (push-up family)
  -- Squat family (T2/T3: §4 bodyweight squat + pistol squat).
  'bodyweight_squat',       -- §4 named, T3 (00053: 1.07)
  'pistol_squat',           -- §4 named, T2 (single-leg full bodyweight squat)
  -- Lunge (T3: §4 walking lunge, bodyweight variant when no DBs are loaded).
  'walking_lunges',         -- §4 named, T3 (00053: 1.07)
  -- Hanging (T3: §4 named hanging leg raise — bodyweight against grip + core).
  'hanging_leg_raise',      -- §4 named, T3 (00053: 1.09)
  -- Olympic gymnastics (T2 family: full bodyweight overhead).
  'handstand_push_up',      -- 24b addition; full-bodyweight overhead press (T2 family)
  -- Body pull (T3: bodyweight horizontal pull, 00053: 1.09).
  'inverted_row',           -- 24b addition; bodyweight horizontal pull (T3, 00053: 1.09)
  -- Eccentric bodyweight (judgment call — flagged for telemetry post-launch
  -- per WIP curation list; the lifter's mass is the primary resistance
  -- during the eccentric, even if pure-volume_load measurement is noisier
  -- than concentric movements).
  'nordic_curl'             -- 24b addition; eccentric-bodyweight hamstring (T5 family, 00053: 0.87)
);

-- ---------------------------------------------------------------------------
-- 4. Sanity assert: the count of marked default rows must equal the literal
--    number of slugs in the IN list above. Mirrors 00053's miss-sentinel
--    pattern — a typo'd slug silently no-ops the UPDATE, so the only way to
--    catch it is to compare the post-UPDATE count against the explicit
--    expectation. v_expected MUST be hand-edited if the IN list changes.
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  v_marked_count int;
  v_expected     int := 20;  -- Hand-counted to match the IN list above.
  v_marked_slugs text;
BEGIN
  SELECT count(*), string_agg(slug, ', ' ORDER BY slug)
    INTO v_marked_count, v_marked_slugs
  FROM public.exercises
  WHERE is_default = true AND uses_bodyweight_load = TRUE;

  IF v_marked_count <> v_expected THEN
    RAISE EXCEPTION
      'Phase 24c curation gap: expected % bodyweight-load default exercises, got %. Marked slugs: [%]. Likely cause: a slug in the UPDATE WHERE clause does not exist in the exercises table (typo) or a curated slug is not is_default = true.',
      v_expected, v_marked_count, COALESCE(v_marked_slugs, '<none>');
  END IF;
END
$$;

COMMIT;

-- Reload PostgREST schema cache so the new columns become visible to the
-- API layer immediately. Dart consumption lands in Phase 24c-2 / 24c-3.
NOTIFY pgrst, 'reload schema';
