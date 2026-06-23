-- 00083 — Vitality decaying reference-peak denominator (vitality_ref_peak)
--
-- WHY ----------------------------------------------------------------------
-- The post-session "Conditioning charged" beat reads a charge fraction
-- `vitality_ewma / denominator`. Until now the denominator was the stored
-- `vitality_peak` — the MONOTONIC all-time max (career best, set forward by
-- the 18d nightly job and never decreased). That denominator is wrong for the
-- charge fraction: a detrained user (low current ewma, high old all-time peak)
-- reads ~2–7% FOREVER and never recovers visibly, because the denominator can
-- never come back down toward where they actually are now. A comeback session
-- should read meaningfully, not stay pinned at a fraction of a peak they hit
-- two years ago.
--
-- This migration adds a SECOND peak column, `vitality_ref_peak`, that DECAYS
-- toward the recent ceiling over weeks. It is the denominator for the charge
-- fraction ONLY. `vitality_peak` is UNTOUCHED — it keeps its "career best"
-- meaning and the Saga screen keeps reading it. The two peaks diverge by
-- design: vitality_peak is monotone-forward; vitality_ref_peak forgets.
--
-- DECAY DESIGN -------------------------------------------------------------
-- The EWMA step runs ~once per UTC day per body part (gated by
-- `last_vitality_date`, first-writer-wins between the save path and the
-- nightly cron). So the per-step multiplier IS a per-day multiplier.
--
--   vitality_ref_peak = GREATEST(new_ewma, prior_ref_peak * REF_PEAK_DECAY)
--
-- REF_PEAK_DECAY = exp(-ln(2) / 21) ≈ 0.96748120 per daily step → a HALF-LIFE
-- of 21 days (3 weeks) for a stale, un-refreshed reference peak.
--
-- WHY a 21-day half-life:
--   * An ACTIVELY-TRAINING user re-tops the GREATEST() with a fresh new_ewma
--     every step, so their ref_peak tracks their true recent ceiling — the
--     decay term is dominated and never bites. They read a healthy fraction.
--   * A DETRAINED user stops feeding new_ewma; their ref_peak halves every
--     3 weeks. After ~3 weeks off, a comeback session's ewma is measured
--     against a denominator that has already fallen ~halfway back toward it,
--     so the charge fraction reads as a real, visible rebuild instead of a
--     rounding-to-zero sliver.
--   * 21 days mirrors the cardio τ_down (the fastest detrain clock in the
--     system) — the reference peak forgets on roughly the same timescale the
--     underlying conditioning actually fades, which is the physiologically
--     honest pairing. It is deliberately SLOWER than the ewma's own α_down
--     rebuild so the denominator is a stable "recent ceiling," not a second
--     copy of the ewma (which would make every fraction ≈ 100% and kill the
--     signal).
--
-- This decay is a FILL-only-never-drains read on the UI side (the charge bar
-- only ever shows fraction climbing back); the denominator movement is never
-- surfaced as a countdown (Phase-39 / ToS aligned — no "your conditioning is
-- decaying" nag).
--
-- BACKFILL -----------------------------------------------------------------
-- Existing rows seed `vitality_ref_peak = vitality_peak`. This is a
-- ZERO-DISCONTINUITY rollout: on the first read after this migration, every
-- user's charge fraction is byte-identical to what the old `ewma / peak`
-- denominator produced. The new decay behavior then begins on the NEXT daily
-- step forward — nobody's charge fraction jumps the instant the migration
-- applies; it only starts to diverge (climb back) as the reference peak
-- decays day by day. Day-0 users (no rows) get the column DEFAULT 0, same as
-- the other vitality columns.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Column — the decaying reference peak (charge-fraction denominator).
-- ---------------------------------------------------------------------------
--
-- numeric(14,4) in lockstep with vitality_ewma / vitality_peak (same
-- incremental-UPSERT rounding-drift reasoning, BUG-RPG-003). NOT NULL DEFAULT 0
-- so day-0 inserts and the model's non-nullable `vitalityRefPeak` field never
-- see NULL.
ALTER TABLE public.body_part_progress
  ADD COLUMN IF NOT EXISTS vitality_ref_peak numeric(14,4) NOT NULL DEFAULT 0
    CHECK (vitality_ref_peak >= 0);

COMMENT ON COLUMN public.body_part_progress.vitality_ref_peak IS
  'Decaying reference peak — the DENOMINATOR for the post-session conditioning '
  'charge fraction (ewma / ref_peak). Half-life 21 days: '
  'GREATEST(new_ewma, prior_ref_peak * exp(-ln(2)/21)) per daily step. Unlike '
  'vitality_peak (monotone career-best, Saga screen), this FORGETS old peaks so '
  'a detrained comeback reads meaningfully. Maintained by '
  'recompute_vitality_for_user AND the vitality-nightly Edge Function (00083).';

-- ---------------------------------------------------------------------------
-- 2. Backfill — zero-discontinuity: ref_peak starts equal to the all-time peak.
-- ---------------------------------------------------------------------------
--
-- Behavior is identical to today on the first read; the decay only begins on
-- the next forward step. Without this, every existing row would read ref_peak=0
-- → divide-by-zero / charge undefined on the first post-migration session.
UPDATE public.body_part_progress
SET vitality_ref_peak = vitality_peak
WHERE vitality_ref_peak = 0
  AND vitality_peak > 0;

-- ---------------------------------------------------------------------------
-- 3. recompute_vitality_for_user — maintain vitality_ref_peak in the SAME
--    guarded upsert that writes vitality_ewma / vitality_peak.
-- ---------------------------------------------------------------------------
--
-- Body is the 00082 definition VERBATIM except:
--   * a REF_PEAK_DECAY constant,
--   * the `stepped` CTE also carries `prior_ref_peak`,
--   * the INSERT/UPDATE also writes
--       vitality_ref_peak = GREATEST(new_ewma, prior_ref_peak * REF_PEAK_DECAY).
--
-- Signature UNCHANGED (RETURNS void). The client detects the once-per-day guard
-- via `before.ewma == after.ewma` (exact) — we deliberately do NOT switch the
-- return type (avoids a DROP/recreate + keeps the existing grant/REVOKE shape).
--
-- The ref_peak step is gated by the SAME `last_vitality_date` guard as the
-- ewma step (it lives in the same row of the same CTE/upsert): if a bp is
-- already stamped today, neither ewma NOR ref_peak advances. ref_peak only
-- moves when ewma moves — they are written atomically.
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
  -- exp(-ln(2)/21) ≈ 0.96748120. See the file header for the rationale (forget
  -- stale peaks over ~3 weeks; active trainees re-top via GREATEST and are
  -- unaffected). MUST match TS REF_PEAK_DECAY in vitality-nightly/index.ts.
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
  -- Join prior state. ref_peak joins alongside ewma/peak; a brand-new bp has
  -- no row → prior_ref_peak 0 (the GREATEST(new_ewma, 0*decay) below seeds it
  -- to new_ewma on day-0, identical to how prior_peak seeds vitality_peak).
  targets AS (
    SELECT
      c.bp                                    AS body_part,
      COALESCE(bpp.vitality_ewma, 0)          AS prior_ewma,
      COALESCE(bpp.vitality_peak, 0)          AS prior_peak,
      COALESCE(bpp.vitality_ref_peak, 0)      AS prior_ref_peak
    FROM candidates c
    LEFT JOIN public.body_part_progress bpp
      ON bpp.user_id = p_user AND bpp.body_part = c.bp
    WHERE bpp.last_vitality_date IS DISTINCT FROM v_today
  ),
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
      t.prior_peak,
      t.prior_ref_peak
    FROM targets t
    LEFT JOIN weekly w ON w.body_part = t.body_part
  )
  INSERT INTO public.body_part_progress AS bpp (
    user_id, body_part, vitality_ewma, vitality_peak, vitality_ref_peak,
    last_vitality_date, updated_at
  )
  SELECT
    p_user,
    s.body_part,
    s.new_ewma,
    GREATEST(s.prior_peak, s.new_ewma),
    -- Decaying reference peak: re-topped by the fresh ewma, else the prior
    -- reference decayed one day toward the recent ceiling (00083).
    GREATEST(s.new_ewma, s.prior_ref_peak * c_ref_peak_decay),
    v_today,
    now()
  FROM stepped s
  ON CONFLICT (user_id, body_part) DO UPDATE
  SET vitality_ewma      = EXCLUDED.vitality_ewma,
      vitality_peak      = EXCLUDED.vitality_peak,
      vitality_ref_peak  = EXCLUDED.vitality_ref_peak,
      last_vitality_date = EXCLUDED.last_vitality_date,
      updated_at         = EXCLUDED.updated_at
  WHERE bpp.last_vitality_date IS DISTINCT FROM EXCLUDED.last_vitality_date;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.recompute_vitality_for_user(uuid, text[])
  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.recompute_vitality_for_user(uuid, text[])
  TO authenticated, service_role;

COMMIT;
