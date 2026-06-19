-- 00082 — Vitality immediacy: save-time EWMA recompute (formula relocation)
--
-- WHY ----------------------------------------------------------------------
-- Until now, body-part Vitality (the asymmetric EWMA of weekly volume) was
-- recomputed ONLY by the `vitality-nightly` Edge Function at ~03:00 UTC. The
-- workout SAVE path never touched it, so the Vitality runes lagged a full day
-- behind XP and rank — you'd finish a session, see XP/rank update instantly,
-- but the conditioning rune wouldn't move until the next morning. That breaks
-- the RPG thesis ("the layer surfaces the real lift") at the exact moment the
-- lift just happened.
--
-- This migration makes Vitality recompute AT SAVE TIME for the body parts the
-- session touched, inside the same atomic transaction as XP/rank/cardio. It
-- does so by RELOCATING the EWMA math (previously inline in the Edge Function's
-- `processUser`) into a single SQL RPC that BOTH the save path and the nightly
-- cron call. This collapses the 3 vitality-compute producers to 2:
--   * REMOVED: the Edge Function's inline EWMA+UPSERT (now a thin RPC caller).
--   * KEPT:    `recompute_vitality_for_user` SQL RPC (this file) — the writer.
--   * KEPT:    Dart `VitalityCalculator` — read-only parity helper / display.
--
-- The formula is RELOCATED, NOT RE-TUNED. Every constant (τ_up=14d, τ_down
-- strength=42d / cardio=21d, 7-day window, the α derivations, peak-monotonic-
-- forward) is byte-for-byte the same as the Edge Function and the Dart
-- `VitalityCalculator`. The PG/Dart/fixture parity is pinned to 1e-4 by the
-- integration suite.
--
-- DOUBLE-COUNT GUARD -------------------------------------------------------
-- Both producers can now fire for the same user on the same UTC day (you save
-- a workout at 14:00, then the nightly cron runs at 03:00 the next day — but
-- also: two saves on the same day, or a save followed by a manual cron
-- invocation). The EWMA step must apply AT MOST ONCE per body part per UTC
-- day, or the rune double-decays/double-rebuilds.
--
-- The guard is a NEW per-body-part column `last_vitality_date`. Whoever steps
-- a body part first that day stamps the date; any later caller for the same
-- (user, body_part, day) is a no-op (`last_vitality_date IS DISTINCT FROM
-- today` is false). First-writer-wins. This SUPERSEDES the old per-user
-- `vitality_runs (user_id, run_date)` PK as the dedup authority — the per-bp
-- column is strictly finer-grained (the save path touches only SOME body
-- parts; the nightly job must still process the user's OTHER, untouched parts
-- that day). `vitality_runs` survives as an advisory audit log only.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Guard column — per-body-part, first-writer-wins double-count guard.
-- ---------------------------------------------------------------------------
--
-- Nullable: a body part that has never been stepped (day-0 user) has NULL,
-- which `IS DISTINCT FROM today` treats as "needs stepping" — correct. The
-- date is the UTC calendar day, matching the 7-day window's `now() at utc`
-- frame and the `vitality_runs.run_date` audit column.
ALTER TABLE public.body_part_progress
  ADD COLUMN IF NOT EXISTS last_vitality_date date;

COMMENT ON COLUMN public.body_part_progress.last_vitality_date IS
  'UTC date this body part''s vitality_ewma/peak was last stepped. '
  'Per-bp, first-writer-wins double-count guard shared by save_workout '
  '(save-time recompute) and the vitality-nightly cron. Supersedes '
  'vitality_runs as the dedup authority (00082).';

-- ---------------------------------------------------------------------------
-- 2. recompute_vitality_for_user — the single EWMA writer (relocated math).
-- ---------------------------------------------------------------------------
--
-- Ports the Edge Function `processUser` EWMA VERBATIM:
--   * weekly_volume[bp] = SUM((attribution ->> bp)::numeric) over the user's
--     xp_events in the past 7 days (the `now() at utc - 7d` window).
--   * α_up   = 1 - exp(-7/14)              ≈ 0.39346934   (rebuild fast)
--   * α_down = 1 - exp(-7/τ_down(bp))      strength τ_down=42d ≈ 0.15351828
--                                          cardio   τ_down=21d ≈ 0.28346869
--     (two-speed decay: cardio detrains ~2× faster — Phase 38e).
--   * α      = α_up when weekly_volume >= prior_ewma, else α_down.
--   * new_ewma = α × weekly_volume + (1-α) × prior_ewma
--   * new_peak = GREATEST(prior_peak, new_ewma)   (peak monotone-forward)
--
-- Target body parts:
--   * p_body_parts non-empty → intersect with the user's body_part_progress
--     rows (the SAVE path: only the parts this session attributed).
--   * p_body_parts NULL or empty → ALL the user's body_part_progress rows
--     (the NIGHTLY path: every active bp under the same per-bp guard).
--
-- Idempotency / double-count guard: a body part is stepped ONLY IF
-- `last_vitality_date IS DISTINCT FROM (now() at utc)::date`. After stepping,
-- `last_vitality_date` is stamped to today. A second call the same day for an
-- already-stamped bp short-circuits (the WHERE clause excludes it) — the EWMA
-- does NOT advance twice. This is the anti-double-count contract.
--
-- total_xp and rank are NEVER touched here — those are owned by
-- record_set_xp / record_session_xp_batch / record_cardio_session.
--
-- SECURITY DEFINER + search_path pinned, mirroring the other rpg RPCs. The
-- save path PERFORMs this as the authenticated user (whose own row it is); the
-- nightly cron invokes it service-role per candidate user. The function body
-- only ever touches the passed p_user's rows.
CREATE OR REPLACE FUNCTION public.recompute_vitality_for_user(
  p_user        uuid,
  p_body_parts  text[] DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  -- Constants — VERBATIM from vitality-nightly/index.ts + VitalityCalculator.
  -- τ in days; α derived per-step (cardio uses its own τ_down). Inlined as
  -- literals rather than a config table so the formula is auditable in one
  -- place and matches the Dart/Edge sources line-for-line.
  c_tau_up           constant numeric := 14.0;
  c_tau_down_str     constant numeric := 42.0;
  c_tau_down_cardio  constant numeric := 21.0;
  c_sample_days      constant numeric := 7.0;
  c_alpha_up         constant numeric := 1 - exp(-c_sample_days / c_tau_up);

  -- The active body-part universe — mirrors ACTIVE_BODY_PARTS in the Edge
  -- Function and Dart `activeBodyParts`. cardio last (strength order
  -- preserved). The nightly (NULL) path processes this whole set so a body
  -- part that earned its FIRST volume this window gets a freshly-inserted row
  -- (the old `processUser` did this via upsert — an UPDATE-only port would
  -- silently skip a brand-new chest row and freeze a day-0 user at zero).
  c_active_bps       constant text[] :=
    ARRAY['chest','back','legs','shoulders','arms','core','cardio'];

  v_today            date := (now() AT TIME ZONE 'utc')::date;
  v_window_start     timestamptz := now() - interval '7 days';
BEGIN
  IF p_user IS NULL THEN
    RETURN;
  END IF;

  -- Weekly volume per body part: sum each attribution key over the user's
  -- xp_events in the 7-day window. jsonb_each_text expands the attribution
  -- object's keys (body-part tokens, including 'cardio') so the aggregate is
  -- naturally per-bp without enumerating the body-part list. Empty/absent →
  -- no row → treated as weekly_volume 0 via the LEFT JOIN below.
  WITH weekly AS (
    SELECT kv.key AS body_part,
           SUM(kv.value::numeric) AS weekly_volume
    FROM public.xp_events e
    CROSS JOIN LATERAL jsonb_each_text(e.attribution) AS kv(key, value)
    WHERE e.user_id = p_user
      AND e.occurred_at >= v_window_start
    GROUP BY kv.key
  ),
  -- Candidate body parts to step:
  --   * save path (p_body_parts non-empty): exactly the parts this session
  --     attributed (filtered to the active universe — never step a stray
  --     attribution key that isn't a real body part).
  --   * nightly path (p_body_parts NULL/empty): the FULL active universe, so a
  --     part with its first-ever volume this window gets an inserted row, AND
  --     any existing row with prior conditioning decays even at zero volume.
  -- This is the faithful port of the old per-bp upsert fan-out.
  candidates AS (
    SELECT bp
    FROM unnest(c_active_bps) AS bp
    WHERE (
      p_body_parts IS NULL
      OR array_length(p_body_parts, 1) IS NULL
      OR bp = ANY (p_body_parts)
    )
  ),
  -- Join prior state (LEFT JOIN — a brand-new body part has no row yet → prior
  -- ewma/peak 0 / last_vitality_date NULL, the day-0 path). The per-bp guard:
  -- skip a candidate already stepped today (last_vitality_date = v_today).
  -- NULL last_vitality_date IS DISTINCT FROM today → true → needs stepping.
  targets AS (
    SELECT
      c.bp                                    AS body_part,
      COALESCE(bpp.vitality_ewma, 0)          AS prior_ewma,
      COALESCE(bpp.vitality_peak, 0)          AS prior_peak
    FROM candidates c
    LEFT JOIN public.body_part_progress bpp
      ON bpp.user_id = p_user AND bpp.body_part = c.bp
    WHERE bpp.last_vitality_date IS DISTINCT FROM v_today
  ),
  -- One EWMA step per target. weekly_volume defaults to 0 for a target with no
  -- events in the window (deload decay). τ_down is per-bp (cardio vs strength)
  -- → α_down derived inline; α_up is the shared rebuild rate. No round() here:
  -- the numeric(14,4) column applies the SAME scale-4 rounding on store that
  -- the old Edge Function relied on (it wrote full-precision JS doubles; PG
  -- rounded at the column). Peak compares the UNROUNDED new ewma, exactly like
  -- `stepEwma` (`newEwma > priorPeak ? newEwma : priorPeak`) — keeps Dart/SQL
  -- parity at 1e-4 without an extra rounding seam.
  stepped AS (
    SELECT
      t.body_part,
      (CASE
        WHEN COALESCE(w.weekly_volume, 0) >= t.prior_ewma THEN c_alpha_up
        ELSE 1 - exp(
          -c_sample_days /
          CASE WHEN t.body_part = 'cardio'
               THEN c_tau_down_cardio ELSE c_tau_down_str END
        )
      END) * COALESCE(w.weekly_volume, 0)
      + (1 - (CASE
        WHEN COALESCE(w.weekly_volume, 0) >= t.prior_ewma THEN c_alpha_up
        ELSE 1 - exp(
          -c_sample_days /
          CASE WHEN t.body_part = 'cardio'
               THEN c_tau_down_cardio ELSE c_tau_down_str END
        )
      END)) * t.prior_ewma                    AS new_ewma,
      t.prior_peak
    FROM targets t
    LEFT JOIN weekly w ON w.body_part = t.body_part
  )
  -- Upsert: insert-on-missing (day-0 first volume) OR update existing. Mirrors
  -- the old `processUser` upsert(onConflict='user_id,body_part'). total_xp/rank
  -- take their column DEFAULTs (0 / 1) on insert and are LEFT UNTOUCHED on
  -- conflict — only the vitality columns + guard date are written.
  INSERT INTO public.body_part_progress AS bpp (
    user_id, body_part, vitality_ewma, vitality_peak,
    last_vitality_date, updated_at
  )
  SELECT
    p_user,
    s.body_part,
    s.new_ewma,
    GREATEST(s.prior_peak, s.new_ewma),
    v_today,
    now()
  FROM stepped s
  ON CONFLICT (user_id, body_part) DO UPDATE
  SET vitality_ewma      = EXCLUDED.vitality_ewma,
      vitality_peak      = EXCLUDED.vitality_peak,
      last_vitality_date = EXCLUDED.last_vitality_date,
      updated_at         = EXCLUDED.updated_at;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.recompute_vitality_for_user(uuid, text[])
  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.recompute_vitality_for_user(uuid, text[])
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. save_workout — hook the save-time recompute in.
-- ---------------------------------------------------------------------------
--
-- Body VERBATIM from 00079 (the latest definition) except ONE new PERFORM
-- block added immediately after `record_cardio_session`. Ordering is
-- load-bearing: the recompute MUST run AFTER record_session_xp_batch AND
-- record_cardio_session, because the cardio XP-gate inside record_session_xp_batch
-- (00081) READS body_part_progress['cardio'] vitality_ewma/peak to compute
-- `vmult`, and that gate must keep reading the PRIOR-day vitality (the value
-- as of start-of-session). Stepping vitality first would let this session's
-- own conditioning leak into its own XP gate — a feedback loop. So: earn XP
-- (reads prior vitality) → THEN step vitality (for next time + immediate UI).
--
-- The touched body parts are derived from THIS session's xp_events.attribution
-- — the same set the reversal CTE at the top enumerates. We pass that array to
-- recompute_vitality_for_user so only the parts this workout actually trained
-- are stepped at save time; the rest wait for the nightly decay pass (still
-- guarded by last_vitality_date so they're not double-stepped).
--
-- RETURN shape UNCHANGED: still `to_jsonb(workouts row)`. The PR-2 debrief UI
-- reads before/after vitality from providers, not from this RPC.
--
-- CREATE OR REPLACE (signature unchanged from 00079).
CREATE OR REPLACE FUNCTION public.save_workout(
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

  v_plan_id        uuid;
  v_plan_routines  jsonb;
  v_week_start     date;
  v_now            timestamptz := now();
  v_found_idx      int;
  v_match_idx      int;
  v_routine_entry  jsonb;
  v_max_order      int;
  v_new_routines   jsonb;

  -- Vitality immediacy (00082): the body parts THIS session attributed XP to,
  -- gathered from xp_events.attribution after the XP batch + cardio earn have
  -- written their events. Drives the save-time vitality recompute.
  v_touched_bps    text[];
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

  -- BUG-RPG-001 reversal — reverts strength AND cardio body_part_progress by
  -- summing this session's xp_events.attribution over all keys (including the
  -- cardio key). Re-save converges.
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

  -- Re-save must also clear the prior cardio xp_events so record_cardio_session
  -- re-inserts from scratch (its ON CONFLICT DO NOTHING would otherwise keep
  -- the stale row after the reversal already decremented its XP).
  DELETE FROM xp_events
  WHERE user_id = v_user_id
    AND session_id = v_workout_id
    AND event_type = 'cardio_session';

  DELETE FROM workout_exercises WHERE workout_id = v_workout_id;
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

  -- Phase 38c — cardio earning. Runs AFTER the strength batch, INSIDE the same
  -- transaction. Earns cardio body_part_progress + writes back cardio_vo2max.
  -- Cardio stays out of character_state (38d). Reverted on re-save above.
  PERFORM public.record_cardio_session(v_workout_id);

  -- Vitality immediacy (00082) — step the EWMA NOW for the body parts this
  -- session touched, inside the same transaction, AFTER the XP batch + cardio
  -- earn so the cardio XP-gate kept reading prior-day vitality. Touched bps =
  -- the attribution keys on THIS session's xp_events (same set the reversal
  -- CTE above enumerates). Per-bp last_vitality_date guards against the nightly
  -- job double-stepping these same parts later today (first-writer-wins).
  SELECT array_agg(DISTINCT kv.key)
  INTO v_touched_bps
  FROM xp_events e
  CROSS JOIN LATERAL jsonb_each_text(e.attribution) AS kv(key, value)
  WHERE e.user_id = v_user_id
    AND e.session_id = v_workout_id;

  IF v_touched_bps IS NOT NULL AND array_length(v_touched_bps, 1) > 0 THEN
    PERFORM public.recompute_vitality_for_user(v_user_id, v_touched_bps);
  END IF;

  v_week_start := (date_trunc('week', v_now)::date);

  SELECT id, routines
  INTO v_plan_id, v_plan_routines
  FROM weekly_plans
  WHERE user_id = v_user_id AND week_start = v_week_start
  FOR UPDATE;

  IF v_plan_id IS NULL THEN
    SELECT to_jsonb(w) INTO v_result FROM workouts w WHERE w.id = v_workout_id;
    RETURN v_result;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(v_plan_routines) AS r
    WHERE (r ->> 'completed_workout_id') = v_workout_id::text
  ) THEN
    SELECT to_jsonb(w) INTO v_result FROM workouts w WHERE w.id = v_workout_id;
    RETURN v_result;
  END IF;

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
    SELECT COALESCE(MAX((r ->> 'order')::int), 0)
    INTO v_max_order
    FROM jsonb_array_elements(v_plan_routines) AS r;

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

COMMIT;
