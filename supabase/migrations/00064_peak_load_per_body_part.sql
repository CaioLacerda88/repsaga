-- =============================================================================
-- 00064 — Phase 27 L10: peak_load_per_body_part RPC
--
-- ## What this does
--
-- New STABLE SQL function `peak_load_per_body_part(user_id, days, end_date)`
-- returns one row per body-part-with-attribution containing the heaviest single
-- set weight (`MAX(sets.weight)`) the user lifted within the window
-- `(end_date - days, end_date]`.
--
-- Used by the Phase 27 L10 fix to replace the EWMA-rendered-as-kg
-- mislabel in `VolumePeakBlock` on the stats deep-dive screen. The widget
-- previously showed peak Vitality EWMA (dimensionless 0..100) labeled "Carga
-- pico ... kg" — meaningless to users. This RPC powers the real heaviest-
-- weight readout.
--
-- ## Window semantics
--
-- Half-open: `(end_date - days, end_date]`. A workout finished exactly at
-- `end_date - days` is OUT, one finished exactly at `end_date` is IN. This
-- matches "the last 7 days" intuition — today and the 6 prior days.
--
-- ## Attribution rule
--
-- A set "counts toward body part X" iff the parent exercise's
-- `xp_attribution -> X` is strictly positive. This matches the existing
-- `setsLast7d` semantics in `assembleStatsState` (any non-zero attribution
-- counts; PRIMARY-share-only would be a different formula and is not what
-- the volume column does). If a future "strictly primary" variant is wanted,
-- it becomes a sibling RPC, not a tweak to this one.
--
-- ## Exercises without xp_attribution
--
-- User-created exercises ship with `xp_attribution = NULL`. Those sets are
-- NOT reflected here — the same way the existing weekly-volume calculation
-- in `assembleStatsState` excludes them (it reads `e.attribution[bp]` from
-- xp_events.attribution; events for null-attribution exercises emit empty
-- attribution maps per `record_set_xp`). The fallback to muscle_group lives
-- at the exercise edit/save layer; until that ships, these sets are
-- attribution-less by design.
--
-- ## Window timestamp source
--
-- We filter on `COALESCE(w.started_at, w.finished_at)` — preferring
-- `started_at` over `finished_at`. Two reasons:
--
--   1. `xp_events.occurred_at` (the timestamp the volume column reads via
--      `assembleStatsState`) is itself sourced from `w.started_at` in the
--      `record_session_xp_batch` chain. Using `started_at` here keeps the
--      Carga pico window in lock-step with the Volume window on the same
--      row — the two columns reference the same moment in time.
--   2. `started_at` is the workout's real-world anchor; a workout that
--      runs across midnight has `finished_at` after the day boundary,
--      which would shift its sets into the "today" bucket even though the
--      lifter would say "I trained yesterday".
--
-- The COALESCE fallback to `finished_at` is defensive — a workout with
-- a NULL `started_at` is data corruption, but we don't want the function
-- to throw on it.
--
-- ## Security
--
-- `SECURITY INVOKER` with `p_user_id` filter — relies on RLS on `workouts`
-- (`SELECT WHERE user_id = auth.uid()`) to enforce that callers can only
-- read their own data. The function does not need DEFINER privileges; it
-- reads through the user's own RLS context. The `p_user_id` parameter is a
-- caller-provided convenience for clarity; a malicious caller passing
-- another user's id still gets nothing back because the JOIN filters by
-- workouts.user_id and RLS short-circuits at the SELECT layer.
--
-- ## Performance
--
-- Single SQL statement, no PL/pgSQL. Reads from sets → workout_exercises →
-- workouts → exercises, JSONB-unpacks attribution per matching set. For a
-- power user with 7 sessions × 30 sets in 7 days, that's ~210 sets × ~3
-- body parts/set = ~630 (body_part, weight) tuples → 6-row group-by. <10ms.
--
-- ## Idempotency
--
-- Pure read function. Calling it any number of times returns identical
-- results for identical (user, days, end_date) inputs as long as the
-- underlying data hasn't changed.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.peak_load_per_body_part(
  p_user_id uuid,
  p_days int,
  p_end_date timestamptz DEFAULT now()
)
RETURNS TABLE(body_part text, peak_load_kg numeric)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  WITH attr_per_set AS (
    SELECT
      s.weight,
      (kv).key   AS body_part,
      (kv).value AS share_text
    FROM sets s
    JOIN workout_exercises we ON we.id = s.workout_exercise_id
    JOIN workouts w           ON w.id  = we.workout_id
    JOIN exercises e          ON e.id  = we.exercise_id
    CROSS JOIN LATERAL jsonb_each_text(COALESCE(e.xp_attribution, '{}'::jsonb)) AS kv
    WHERE w.user_id = p_user_id
      AND COALESCE(w.started_at, w.finished_at) >  p_end_date - (p_days || ' days')::interval
      AND COALESCE(w.started_at, w.finished_at) <= p_end_date
      AND s.weight IS NOT NULL
      AND s.weight > 0
  )
  SELECT
    body_part::text,
    MAX(weight)::numeric AS peak_load_kg
  FROM attr_per_set
  WHERE share_text::numeric > 0
  GROUP BY body_part;
$$;

GRANT EXECUTE ON FUNCTION public.peak_load_per_body_part(uuid, int, timestamptz) TO authenticated;
