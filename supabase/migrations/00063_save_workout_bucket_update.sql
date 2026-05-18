-- =============================================================================
-- 00063 — Phase 26e Task 3: save_workout extends to update weekly_plans bucket
--
-- ## What this does
--
-- CREATE OR REPLACE `save_workout(p_workout, p_exercises, p_sets)` to ALSO
-- update the current-week `weekly_plans` row using first-completion-wins
-- find-or-create logic:
--
--   1. Compute the current week's Monday (UTC date_trunc + adjust for ISO
--      week start = Monday). The plan row is keyed by (user_id, week_start).
--   2. If no plan row exists for this week, no-op the bucket update — the
--      user simply hasn't planned this week. (We do NOT auto-create here;
--      the notifier owns plan creation via upsertPlan.)
--   3. Walk the plan's `routines` JSONB array:
--        - If we find an entry with `routine_id == workout.routine_id` AND
--          `completed_workout_id IS NULL`, fill it: set completed_workout_id
--          + completed_at. Done — write back and return.
--        - Otherwise append a new entry: `routine_id = workout.routine_id`,
--          `order = max(existing order) + 1`, `completed_workout_id = workout.id`,
--          `completed_at = now()`, `is_spontaneous = true`.
--   4. The walk fills the FIRST uncompleted match by `order` ASC — this is
--      "first-completion-wins" (spec line 473). A duplicate spontaneous
--      cannot pre-empt a still-uncompleted planned entry of the same routine.
--
-- ## Why this lives in save_workout and not a separate RPC
--
-- We want the bucket update to ride the same transaction as the workout
-- insert + XP roll-up. If the transaction rolls back (validation, FK error,
-- record_session_xp_batch raise), the bucket stays untouched. A separate RPC
-- call from the notifier would leave a gap where the workout was saved but
-- the bucket update failed.
--
-- ## Hot-path discipline
--
-- The bucket update is bounded by the plan row size (rare to exceed 10
-- routines; spec recommends <= training_frequency_per_week, typically 3-5).
-- The JSONB walk is a single SQL statement (no PL/pgSQL loop). One UPDATE
-- against weekly_plans by id at the end. < 1 ms vs the existing ~30-50 ms
-- save_workout body.
--
-- ## Idempotency
--
-- Re-saving the same workout (workout.id already present in the plan as a
-- `completed_workout_id`) is a no-op: the find step skips entries whose
-- `completed_workout_id == workout.id` (already-applied). The CREATE OR
-- REPLACE function body is itself idempotent.
--
-- ## What's NOT in this migration
--
--   * No schema changes. `weekly_plans.routines` is already JSONB; the new
--     `is_spontaneous` key is just an extra string-keyed entry inside each
--     array element.
--   * No new RLS policy changes. save_workout remains SECURITY DEFINER; the
--     UPDATE against weekly_plans happens in definer context and bypasses
--     RLS (matching how 00040's UPDATE on workouts already works).
--   * No change to record_session_xp_batch or any XP-side RPC. The bucket
--     update is independent of XP — it could even short-circuit if the user
--     has no plan for the week.
-- =============================================================================

CREATE OR REPLACE FUNCTION save_workout(
  p_workout jsonb,
  p_exercises jsonb,
  p_sets jsonb
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

GRANT EXECUTE ON FUNCTION save_workout(jsonb, jsonb, jsonb) TO authenticated;
