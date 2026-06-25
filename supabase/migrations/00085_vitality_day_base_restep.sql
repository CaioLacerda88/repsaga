-- 00085 — Vitality save-time immediacy via day-base re-step (Phase Vitality-4)
--
-- WHY ----------------------------------------------------------------------
-- The `vitality-nightly` cron runs at 03:00 UTC, steps every active body
-- part, and stamps `last_vitality_date = today` BEFORE the user trains. The
-- in-txn `recompute_vitality_for_user(user, touched)` that `save_workout`
-- fires later that day was then GUARD-BLOCKED — the `targets` CTE filtered out
-- any bp whose `last_vitality_date` already equalled today (the once-per-day
-- guard) and the conflict-row `WHERE last_vitality_date IS DISTINCT FROM
-- EXCLUDED.last_vitality_date` upsert guard suppressed the write. Net effect:
-- the just-finished session stepped ZERO vitality and the post-session
-- "Conditioning charged" beat showed "mantido" with no movement. Save-time
-- immediacy (Vitality-2's whole point) was dead-on-arrival for anyone training
-- after 03:00 UTC — i.e. effectively everyone, and ALWAYS for UTC-3 Brazil
-- where the cron fires at local midnight before the day's first lift.
--
-- THE FIX — day-base re-step ------------------------------------------------
-- Instead of SKIPPING a part already stepped today, RE-STEP it from its stored
-- start-of-day base, using the now-complete trailing-7-day volume window.
--
-- We snapshot three new per-bp "day base" columns at the FIRST step of each
-- vitality day (`vitality_ewma_day_base`, `vitality_peak_day_base`,
-- `vitality_ref_peak_day_base`). The first step of the day computes its base
-- from the live prior value (and stores that base alongside the result). Any
-- LATER same-day recompute reads the stored day-base instead of the compounded
-- current value, and applies the asymmetric α step ONCE from that base. Because
-- α is always applied from the day's snapshotted base — never from a value that
-- already had α applied today — there is NO double-α and NO double-count: a
-- re-step with the same 7-day window reproduces the same result (idempotent),
-- and a re-step after new volume enters the window steps UP from the same base
-- to a fresh value. The session's volume now moves vitality immediately.
--
-- The cron STAYS at 03:00 (we deliberately do NOT reschedule it). Its timing
-- is now irrelevant: the cron simply becomes the day's FIRST step, snapshotting
-- the base; the user's later save RE-STEPS from that base. Whoever steps first
-- sets the base; everyone after re-steps from it. Two concurrent same-day calls
-- both read the same day_base and compute from it, so last-writer-wins is safe
-- (no compounding, no lost α — both land on a value derived from the one base).
--
-- PARITY -------------------------------------------------------------------
-- The pure EWMA step (`α·vol + (1-α)·base`, monotone peak, decaying ref_peak)
-- is UNCHANGED. We change only WHICH base the step reads (the snapshotted
-- day-base on a re-step vs the live prior on a first step), not the step math.
-- The Python sim (`advance_vitality_week`) already ticks once per day from the
-- prior-day base, so it already matches this contract — no sim, fixture,
-- `vitality_calculator.dart`, or edge `stepEwma` change is needed. "α once per
-- day, from the correct base, no double-count" — sim parity preserved.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Day-base columns — the start-of-day snapshot the once-per-day step is
--    computed FROM, so a later same-day save re-steps instead of compounding.
-- ---------------------------------------------------------------------------
--
-- Nullable (NOT NOT-NULL DEFAULT 0): a NULL base means "no step has run today
-- yet" — equivalent to is_first_today. They are populated by the first step of
-- each vitality day and read back by every later same-day re-step. numeric(14,4)
-- in lockstep with the vitality columns they snapshot (BUG-RPG-003 rounding).
ALTER TABLE public.body_part_progress
  ADD COLUMN IF NOT EXISTS vitality_ewma_day_base     numeric(14,4),
  ADD COLUMN IF NOT EXISTS vitality_peak_day_base     numeric(14,4),
  ADD COLUMN IF NOT EXISTS vitality_ref_peak_day_base numeric(14,4);

COMMENT ON COLUMN public.body_part_progress.vitality_ewma_day_base IS
  'value as of the start of the current vitality day (last_vitality_date); the '
  'base the once-per-day EWMA step is computed FROM, so a later same-day save '
  're-steps from it instead of compounding α (Vitality-4 day-base re-step).';
COMMENT ON COLUMN public.body_part_progress.vitality_peak_day_base IS
  'value as of the start of the current vitality day (last_vitality_date); the '
  'base the once-per-day EWMA step is computed FROM, so a later same-day save '
  're-steps from it instead of compounding α (Vitality-4 day-base re-step).';
COMMENT ON COLUMN public.body_part_progress.vitality_ref_peak_day_base IS
  'value as of the start of the current vitality day (last_vitality_date); the '
  'base the once-per-day EWMA step is computed FROM, so a later same-day save '
  're-steps from it instead of compounding α (Vitality-4 day-base re-step).';

-- ---------------------------------------------------------------------------
-- 2. recompute_vitality_for_user — re-step from the day-base instead of
--    skipping an already-stepped part.
-- ---------------------------------------------------------------------------
--
-- Body is the 00083 definition VERBATIM (SECURITY DEFINER, search_path=public,
-- same signature, same constants incl. c_ref_peak_decay) EXCEPT the cadence /
-- base-selection:
--   * the `targets` CTE no longer FILTERS OUT bps already stamped today — it
--     processes every candidate and computes a per-bp `base_*` that is the live
--     prior value on the day's first step, or the stored day-base on a re-step;
--   * the `stepped` CTE steps from `base_ewma/base_peak/base_ref_peak`;
--   * the UPSERT always writes (the conflict-row IS-DISTINCT guard is removed)
--     and additionally persists the three day_base columns.
-- total_xp / rank are UNTOUCHED (vitality cols + base + date only).
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
  c_tau_up           constant numeric := 14.0;
  c_tau_down_str     constant numeric := 42.0;
  c_tau_down_cardio  constant numeric := 21.0;
  c_sample_days      constant numeric := 7.0;
  c_alpha_up         constant numeric := 1 - exp(-c_sample_days / c_tau_up);

  -- Reference-peak per-step (per-day) decay multiplier. Half-life 21 days:
  -- exp(-ln(2)/21) ≈ 0.96748120. See 00083 for the rationale. MUST match TS
  -- REF_PEAK_DECAY in vitality-nightly/index.ts.
  c_ref_peak_decay   constant numeric := exp(-ln(2.0) / 21.0);

  c_active_bps       constant text[] :=
    ARRAY['chest','back','legs','shoulders','arms','core','cardio'];

  v_today            date := (now() AT TIME ZONE 'utc')::date;
  v_window_start     timestamptz := now() - interval '7 days';
BEGIN
  IF p_user IS NULL THEN
    RETURN;
  END IF;

  WITH weekly AS (
    SELECT kv.key AS body_part,
           SUM(kv.value::numeric) AS weekly_volume
    FROM public.xp_events e
    CROSS JOIN LATERAL jsonb_each_text(e.attribution) AS kv(key, value)
    WHERE e.user_id = p_user
      AND e.occurred_at >= v_window_start
    GROUP BY kv.key
  ),
  candidates AS (
    SELECT bp
    FROM unnest(c_active_bps) AS bp
    WHERE (
      p_body_parts IS NULL
      OR array_length(p_body_parts, 1) IS NULL
      OR bp = ANY (p_body_parts)
    )
  ),
  -- Join prior state and choose the step BASE per bp (Vitality-4). We process
  -- EVERY candidate now (no skip filter). `is_first_today` is true when this bp
  -- has not yet been stepped this vitality day — then the base IS the live prior
  -- value (and we snapshot it). On a re-step (already stepped today) the base is
  -- the stored day_base (falling back to the live value if a pre-Vitality-4 row
  -- carries a NULL base — those rows were last stepped before this migration, so
  -- their live value IS their day base). The LEFT JOIN keeps a brand-new day-0
  -- bp (no row) at base 0 with is_first_today true.
  targets AS (
    SELECT
      c.bp AS body_part,
      (bpp.last_vitality_date IS DISTINCT FROM v_today) AS is_first_today,
      CASE
        WHEN bpp.last_vitality_date IS DISTINCT FROM v_today
          THEN COALESCE(bpp.vitality_ewma, 0)
        ELSE COALESCE(bpp.vitality_ewma_day_base, bpp.vitality_ewma, 0)
      END AS base_ewma,
      CASE
        WHEN bpp.last_vitality_date IS DISTINCT FROM v_today
          THEN COALESCE(bpp.vitality_peak, 0)
        ELSE COALESCE(bpp.vitality_peak_day_base, bpp.vitality_peak, 0)
      END AS base_peak,
      CASE
        WHEN bpp.last_vitality_date IS DISTINCT FROM v_today
          THEN COALESCE(bpp.vitality_ref_peak, 0)
        ELSE COALESCE(bpp.vitality_ref_peak_day_base, bpp.vitality_ref_peak, 0)
      END AS base_ref_peak
    FROM candidates c
    LEFT JOIN public.body_part_progress bpp
      ON bpp.user_id = p_user AND bpp.body_part = c.bp
  ),
  -- The asymmetric EWMA step, computed FROM the day base. α-up vs α-down is
  -- chosen by `weekly_volume >= base_ewma` (the base, not a compounded current).
  stepped AS (
    SELECT
      t.body_part,
      t.base_ewma,
      t.base_peak,
      t.base_ref_peak,
      (CASE
        WHEN COALESCE(w.weekly_volume, 0) >= t.base_ewma THEN c_alpha_up
        ELSE 1 - exp(
          -c_sample_days /
          CASE WHEN t.body_part = 'cardio'
               THEN c_tau_down_cardio ELSE c_tau_down_str END
        )
      END) * COALESCE(w.weekly_volume, 0)
      + (1 - (CASE
        WHEN COALESCE(w.weekly_volume, 0) >= t.base_ewma THEN c_alpha_up
        ELSE 1 - exp(
          -c_sample_days /
          CASE WHEN t.body_part = 'cardio'
               THEN c_tau_down_cardio ELSE c_tau_down_str END
        )
      END)) * t.base_ewma                       AS new_ewma
    FROM targets t
    LEFT JOIN weekly w ON w.body_part = t.body_part
  )
  INSERT INTO public.body_part_progress AS bpp (
    user_id, body_part, vitality_ewma, vitality_peak, vitality_ref_peak,
    vitality_ewma_day_base, vitality_peak_day_base, vitality_ref_peak_day_base,
    last_vitality_date, updated_at
  )
  SELECT
    p_user,
    s.body_part,
    s.new_ewma,
    GREATEST(s.base_peak, s.new_ewma),
    -- Decaying reference peak: re-topped by the fresh ewma, else the day-base
    -- reference decayed one day toward the recent ceiling (00083 expression,
    -- now over the day base).
    GREATEST(s.new_ewma, s.base_ref_peak * c_ref_peak_decay),
    -- Persist the day base so a later same-day re-step reads it back. On the
    -- day's first step (and day-0 insert) this is the snapshotted base.
    s.base_ewma,
    s.base_peak,
    s.base_ref_peak,
    v_today,
    now()
  FROM stepped s
  -- Always write (re-step). The conflict-row IS-DISTINCT-FROM guard is GONE:
  -- both first-step and re-step paths land here, and last-writer-wins is safe
  -- because every writer computed from the same snapshotted day base.
  ON CONFLICT (user_id, body_part) DO UPDATE
  SET vitality_ewma              = EXCLUDED.vitality_ewma,
      vitality_peak              = EXCLUDED.vitality_peak,
      vitality_ref_peak          = EXCLUDED.vitality_ref_peak,
      vitality_ewma_day_base     = EXCLUDED.vitality_ewma_day_base,
      vitality_peak_day_base     = EXCLUDED.vitality_peak_day_base,
      vitality_ref_peak_day_base = EXCLUDED.vitality_ref_peak_day_base,
      last_vitality_date         = EXCLUDED.last_vitality_date,
      updated_at                 = EXCLUDED.updated_at;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.recompute_vitality_for_user(uuid, text[])
  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.recompute_vitality_for_user(uuid, text[])
  TO authenticated, service_role;

COMMIT;
