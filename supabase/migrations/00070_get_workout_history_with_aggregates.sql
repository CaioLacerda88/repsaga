-- =============================================================================
-- 00070 — Phase 32 PR 32f: get_workout_history_with_aggregates +
--                          get_workout_xp helper RPCs
--
-- ## What this does
--
-- Two new STABLE SQL functions powering the redesigned History screen:
--
--   1. `get_workout_history_with_aggregates(p_user_id, p_limit, p_offset)`
--      returns one row per finished workout (paginated, most-recent first)
--      with the existing workout shape PLUS:
--        * `total_xp INT`  — SUM(xp_events.total_xp) attributed to the session
--        * `pr_count INT`  — COUNT(personal_records) joined via the session's
--                            sets
--        * `workout_exercises JSONB` — the same `(order, exercise_id)` payload
--          the previous client-side `select('*, workout_exercises(...)')`
--          query produced, so the existing two-query merge for localized
--          exercise names keeps working unchanged.
--
--   2. `get_workout_xp(p_workout_id)` returns one row `(total_xp INT,
--      pr_count INT)` for a single workout. Powers the new 48dp summary
--      strip on the workout detail screen without forcing the detail
--      fetch to round-trip the history aggregate function.
--
-- ## Why a SQL function, not a client-side JOIN
--
-- The previous history query was a single Supabase `select(...)` with a
-- nested `workout_exercises(...)` relation. Pulling XP + PR counts client-
-- side would have required either (a) an N+1 lookup per workout — bad — or
-- (b) two extra `inFilter` queries against `xp_events` / `personal_records`
-- then a client-side join. (b) works but bloats the wire payload and
-- doubles the round-trip count for every history page. A single RPC keeps
-- the page load to two queries (history + batched localized exercise names)
-- regardless of aggregate complexity.
--
-- ## Aggregate semantics
--
-- * `total_xp` — `COALESCE(SUM(xp_events.total_xp), 0)` over rows where
--   `xp_events.session_id = workouts.id`. Zero when the workout earned no
--   XP (early termination, zero-load free workout). Type INT — the same
--   numeric register the celebration / summary screens use.
--
-- * `pr_count` — `COUNT(personal_records.*)` over rows where
--   `personal_records.set_id` joins through `sets → workout_exercises →
--   workouts.id`. Zero when the session produced no PRs. Type INT.
--
-- LEFT JOINs with COALESCE so zero-aggregate workouts still appear in the
-- result (matching the previous query shape).
--
-- ## Window / ordering / pagination
--
-- Same predicates as the previous client query:
--   * `workouts.user_id = p_user_id`
--   * `workouts.is_active = false`
--   * `workouts.finished_at IS NOT NULL`
--
-- Ordering: `workouts.finished_at DESC` (most recent first).
--
-- Pagination: `LIMIT p_limit OFFSET p_offset`. Defaults of 20/0 match the
-- existing `getWorkoutHistory` page size.
--
-- ## Security
--
-- `SECURITY INVOKER` — relies on RLS on `workouts` / `xp_events` /
-- `personal_records` / `sets` to enforce that callers can only read their
-- own data. `p_user_id` is a caller-side convenience; a malicious caller
-- passing another user's id still gets nothing because the JOIN filters
-- on `workouts.user_id` and RLS short-circuits at the SELECT layer.
--
-- ## Performance
--
-- Single SQL statement, no PL/pgSQL. For a power user with ~50 sessions on
-- a single page, each session contributing ~5 exercises × ~3 sets =
-- ~750 PR-join probes + ~50 XP-event SUMs. With the existing indexes on
-- `xp_events(session_id)`, `personal_records(set_id)`,
-- `sets(workout_exercise_id)`, and `workout_exercises(workout_id)`, the
-- planner uses index nested loops → <100ms target.
--
-- ## Idempotency
--
-- Pure read functions. Calling either any number of times returns
-- identical results for identical inputs as long as the underlying data
-- hasn't changed.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_workout_history_with_aggregates(
  p_user_id uuid,
  p_limit int DEFAULT 20,
  p_offset int DEFAULT 0
)
RETURNS TABLE(
  id uuid,
  user_id uuid,
  name text,
  started_at timestamptz,
  finished_at timestamptz,
  duration_seconds int,
  is_active boolean,
  notes text,
  created_at timestamptz,
  total_xp int,
  pr_count int,
  workout_exercises jsonb
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  WITH page AS (
    SELECT w.*
    FROM workouts w
    WHERE w.user_id = p_user_id
      AND w.is_active = false
      AND w.finished_at IS NOT NULL
    ORDER BY w.finished_at DESC
    LIMIT p_limit
    OFFSET p_offset
  ),
  xp_per_session AS (
    SELECT
      page.id AS workout_id,
      COALESCE(SUM(xe.total_xp), 0)::int AS total_xp
    FROM page
    LEFT JOIN xp_events xe ON xe.session_id = page.id
    GROUP BY page.id
  ),
  pr_per_session AS (
    SELECT
      page.id AS workout_id,
      COUNT(pr.*)::int AS pr_count
    FROM page
    LEFT JOIN workout_exercises we ON we.workout_id = page.id
    LEFT JOIN sets s                ON s.workout_exercise_id = we.id
    LEFT JOIN personal_records pr   ON pr.set_id = s.id
    GROUP BY page.id
  ),
  wes_per_session AS (
    SELECT
      page.id AS workout_id,
      COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'order', we.order,
            'exercise_id', we.exercise_id
          )
        ) FILTER (WHERE we.id IS NOT NULL),
        '[]'::jsonb
      ) AS workout_exercises
    FROM page
    LEFT JOIN workout_exercises we ON we.workout_id = page.id
    GROUP BY page.id
  )
  SELECT
    p.id,
    p.user_id,
    p.name,
    p.started_at,
    p.finished_at,
    p.duration_seconds,
    p.is_active,
    p.notes,
    p.created_at,
    COALESCE(xp.total_xp, 0)  AS total_xp,
    COALESCE(pr.pr_count, 0)  AS pr_count,
    COALESCE(wes.workout_exercises, '[]'::jsonb) AS workout_exercises
  FROM page p
  LEFT JOIN xp_per_session  xp  ON xp.workout_id  = p.id
  LEFT JOIN pr_per_session  pr  ON pr.workout_id  = p.id
  LEFT JOIN wes_per_session wes ON wes.workout_id = p.id
  ORDER BY p.finished_at DESC;
$$;

GRANT EXECUTE ON FUNCTION public.get_workout_history_with_aggregates(uuid, int, int) TO authenticated;

-- ---------------------------------------------------------------------------
-- get_workout_xp — single-workout aggregates for the detail screen header.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_workout_xp(
  p_workout_id uuid
)
RETURNS TABLE(
  total_xp int,
  pr_count int
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT
    COALESCE((
      SELECT SUM(xe.total_xp)::int
      FROM xp_events xe
      WHERE xe.session_id = p_workout_id
    ), 0) AS total_xp,
    COALESCE((
      SELECT COUNT(pr.*)::int
      FROM personal_records pr
      JOIN sets s              ON s.id = pr.set_id
      JOIN workout_exercises we ON we.id = s.workout_exercise_id
      WHERE we.workout_id = p_workout_id
    ), 0) AS pr_count;
$$;

GRANT EXECUTE ON FUNCTION public.get_workout_xp(uuid) TO authenticated;
