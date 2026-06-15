-- =============================================================================
-- 00078 — Phase 38b: `cardio_sessions` table + save_workout cardio persistence
--
-- ## What this does
--
--   1. Creates `cardio_sessions` — the dedicated per-entry cardio log
--      (docs/cardio-stat-plan.md §6 shape (ii), the chosen model). Stores the
--      RAW user inputs only: duration (mandatory), distance (optional), RPE
--      (optional). **The earning-formula computed columns (`met`,
--      `met_minutes`, `est_met`) are DEFERRED to Phase 38c** — they belong to
--      the cardio-XP calibration migration, not the logging surface. 38b rows
--      persist and earn nothing.
--   2. RLS: owner-scoped via the PARENT workout (`workouts.user_id =
--      auth.uid()`). The table carries no user_id of its own — ownership is
--      derived through the `workout_id` FK, so a single gate covers all four
--      verbs and cannot drift from the workouts policy.
--   3. Explicit GRANTs to `authenticated` + `service_role` — cluster
--      `supabase-cli-latest-grant-drift`: never rely on implicit default
--      table grants (newer local Supabase images dropped them and produced
--      mass 42501 failures). No sequences exist on this table (uuid PK,
--      client-generated), so no sequence grants are needed.
--   4. Redefines `save_workout` with a new `p_cardio jsonb DEFAULT '[]'`
--      parameter so cardio entries ride THE SAME TRANSACTION as the workout
--      update + sets insert + record_session_xp_batch. A paired client-side
--      insert was rejected: it would leave a gap where the workout committed
--      but the cardio rows didn't (the exact failure mode 00063 closed for
--      the weekly-plan bucket). Adding a defaulted parameter requires
--      DROP + CREATE (CREATE OR REPLACE cannot change a signature), and the
--      DEFAULT keeps every existing 3-argument caller working — PostgREST
--      resolves named-args calls against functions with omitted defaulted
--      params, so old app builds and queued offline payloads from pre-38b
--      versions replay unchanged.
--
-- ## Cardio + XP (what does NOT happen here)
--
-- `record_session_xp_batch` is NOT touched: the 00077 cardio save gate
-- already excludes cardio sets from the strength path, and cardio rows in
-- `cardio_sessions` are invisible to every XP writer. No `xp_events`, no
-- `body_part_progress['cardio']` — the cardio earning function is Phase 38c.
--
-- ## Idempotency
--
--   * Table / index / policies are IF-NOT-EXISTS / DROP-IF-EXISTS guarded.
--   * `save_workout` re-save: cardio rows are DELETE+INSERT keyed by
--     workout_id — same reversal discipline as the `workout_exercises`
--     delete above it. Re-saving the same workout converges.
--
-- ## Function body provenance
--
-- The `save_workout` body below is VERBATIM from 00063 except for:
--   (a) the new `p_cardio` parameter,
--   (b) the "Phase 38b cardio persistence" block (DELETE + INSERT on
--       cardio_sessions, placed with the other child-row writes, BEFORE
--       record_session_xp_batch so the whole workout shape commits or
--       rolls back atomically).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- PART A — cardio_sessions table
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.cardio_sessions (
  id               uuid PRIMARY KEY,
  workout_id       uuid NOT NULL REFERENCES public.workouts (id) ON DELETE CASCADE,
  exercise_id      uuid NOT NULL REFERENCES public.exercises (id),
  duration_seconds integer NOT NULL CHECK (duration_seconds > 0),
  distance_m       numeric NULL CHECK (distance_m >= 0),
  rpe              smallint NULL CHECK (rpe BETWEEN 1 AND 10),
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cardio_sessions_workout_id
  ON public.cardio_sessions (workout_id);

-- Phase 38c will read per-user cardio history through the workout join;
-- an exercise_id index keeps the "last cardio entry for this activity"
-- lookup cheap from day one.
CREATE INDEX IF NOT EXISTS idx_cardio_sessions_exercise_id
  ON public.cardio_sessions (exercise_id);

ALTER TABLE public.cardio_sessions ENABLE ROW LEVEL SECURITY;

-- Owner-scoped via the parent workout. One predicate, four verbs.
DROP POLICY IF EXISTS cardio_sessions_select_own ON public.cardio_sessions;
CREATE POLICY cardio_sessions_select_own ON public.cardio_sessions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.workouts w
      WHERE w.id = workout_id AND w.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS cardio_sessions_insert_own ON public.cardio_sessions;
CREATE POLICY cardio_sessions_insert_own ON public.cardio_sessions
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.workouts w
      WHERE w.id = workout_id AND w.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS cardio_sessions_update_own ON public.cardio_sessions;
CREATE POLICY cardio_sessions_update_own ON public.cardio_sessions
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.workouts w
      WHERE w.id = workout_id AND w.user_id = auth.uid()
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.workouts w
      WHERE w.id = workout_id AND w.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS cardio_sessions_delete_own ON public.cardio_sessions;
CREATE POLICY cardio_sessions_delete_own ON public.cardio_sessions
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.workouts w
      WHERE w.id = workout_id AND w.user_id = auth.uid()
    )
  );

-- Explicit grants — cluster `supabase-cli-latest-grant-drift`.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.cardio_sessions TO authenticated;
GRANT ALL ON public.cardio_sessions TO service_role;

-- ---------------------------------------------------------------------------
-- PART B — save_workout(p_workout, p_exercises, p_sets, p_cardio DEFAULT '[]')
--
-- DROP + CREATE: a defaulted parameter changes the signature, and CREATE OR
-- REPLACE on the old 3-arg signature would leave TWO save_workout overloads
-- visible to PostgREST (ambiguous resolution risk). The DEFAULT preserves
-- backward compatibility for every 3-argument named-params caller.
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.save_workout(jsonb, jsonb, jsonb);

CREATE FUNCTION public.save_workout(
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

  -- Bucket update locals.
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

  -- ===========================================================================
  -- BUG-RPG-001 fix — REVERSAL PATTERN (unchanged from 00040)
  -- ===========================================================================
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

  DELETE FROM workout_exercises WHERE workout_id = v_workout_id;

  -- Phase 38b cardio persistence — same reversal discipline as the
  -- workout_exercises DELETE above: re-saving a workout replaces its cardio
  -- rows wholesale, so the RPC stays idempotent under retries / offline
  -- replays.
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

  -- Phase 38b cardio persistence — raw inputs only; the workout_id in each
  -- element is trusted only after re-pinning it to v_workout_id (a payload
  -- pointing a cardio row at someone else's workout would otherwise ride
  -- the SECURITY DEFINER context past RLS). No XP call for cardio rows —
  -- earning is Phase 38c; the 00077 gate already excludes cardio from
  -- record_session_xp_batch below.
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

  -- ===========================================================================
  -- Phase 26e Task 3: bucket find-or-create on weekly_plans.
  --
  -- Server-authoritative week boundary: use v_now (server NOW()) to derive
  -- the current week's Monday. The client's `finished_at` is for display +
  -- sorting only; trusting it for bucket membership would let a backdated
  -- finished_at silently corrupt a past or future week's plan. The user's
  -- "week" for bucket purposes is "when save_workout actually ran".
  -- ===========================================================================
  v_week_start := (date_trunc('week', v_now)::date);

  SELECT id, routines
  INTO v_plan_id, v_plan_routines
  FROM weekly_plans
  WHERE user_id = v_user_id AND week_start = v_week_start
  FOR UPDATE;  -- lock the row to avoid concurrent writers racing append

  -- If no plan exists for this week, the user hasn't planned anything —
  -- skip the bucket update entirely. The notifier's separate upsertPlan
  -- call is what creates the row in the first place.
  IF v_plan_id IS NULL THEN
    SELECT to_jsonb(w) INTO v_result FROM workouts w WHERE w.id = v_workout_id;
    RETURN v_result;
  END IF;

  -- If this workout has already been applied to the bucket (idempotent
  -- re-save), short-circuit: any entry whose completed_workout_id matches
  -- means the previous save_workout call already handled it.
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(v_plan_routines) AS r
    WHERE (r ->> 'completed_workout_id') = v_workout_id::text
  ) THEN
    SELECT to_jsonb(w) INTO v_result FROM workouts w WHERE w.id = v_workout_id;
    RETURN v_result;
  END IF;

  -- First-completion-wins: find the FIRST uncompleted entry (by the user's
  -- chosen `order` field, ASC) whose routine_id matches. v_match_idx is the
  -- PHYSICAL JSONB array index — that's what jsonb_set requires; using
  -- rank-by-order instead would diverge whenever the stored array isn't
  -- already sorted by order. If routine_id is NULL on the workout (free
  -- workout, no source routine), skip the match step and go straight to
  -- spontaneous-append.
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
    -- Planned hit: fill the matched entry in place.
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
    -- No match → append spontaneous entry. v_routine_id may be NULL for
    -- a free workout; we still record it so the user sees the workout in
    -- their bucket. NULL serializes as the JSON null literal — the Dart
    -- side's `String? routineId` accepts it.
    SELECT COALESCE(MAX((r ->> 'order')::int), 0)
    INTO v_max_order
    FROM jsonb_array_elements(v_plan_routines) AS r;

    -- to_jsonb(NULL::text) → JSON null; valid uuid → JSON string. No CASE needed.
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
