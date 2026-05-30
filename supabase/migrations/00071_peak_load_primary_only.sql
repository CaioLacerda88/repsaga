-- =============================================================================
-- 00071 — Phase 32 PR 32j: peak_load_per_body_part primary-only attribution
--
-- ## Why this exists
--
-- Caught during PR #285 (Phase 32 PR 32f) device verification on a Galaxy
-- S938B physical device. The stats deep-dive "Carga pico" column was
-- showing the same heaviest-weight value for two distinct body-parts
-- (shoulders + arms both at 240 kg) because the pre-existing RPC body in
-- migration 00064 counted ANY non-zero attribution share toward a body
-- part's peak.
--
-- Worked example of the bleed:
--   exercise: barbell_overhead_press
--   xp_attribution: { "shoulders": 0.60, "arms": 0.20, "core": 0.20 }
--   top set: 240 kg
-- → 00064 emits rows for shoulders=240, arms=240, core=240.
--
-- The user-facing meaning of "peak load for arms" is "the heaviest set the
-- user pushed where arms were the **primary** body-part engaged" — NOT
-- "the heaviest set that happened to nudge arms a little." The pre-launch
-- decision is to fix the meaning of the column, not to add a separate
-- column.
--
-- ## What changed
--
-- Attribution semantics flip from "any non-zero share counts" to
-- "primary-only: only the body-part(s) with the MAX(xp_attribution share)
-- per exercise count." For overhead_press the max is shoulders=0.60, so
-- only shoulders absorbs the 240 kg. Arms and core stop bleeding.
--
-- Ties theoretically include all max-share body-parts (e.g. a hypothetical
-- exercise with `{chest: 0.5, back: 0.5}` would push the weight onto both).
-- In practice no calibrated default exercise has a tied-primary split
-- after the Phase 29 v2 formula migration 00065 — every catalog entry has
-- a single dominant body-part. The tie-handling is here for correctness,
-- not because we ship a tied exercise today.
--
-- ## Why replace 00064's body rather than add a sibling RPC
--
-- Migration 00064's own docstring foresaw this variant:
--
--   > "If a future 'strictly primary' variant is wanted, it becomes a
--   >  sibling RPC, not a tweak to this one."
--
-- That advice assumed a post-launch world where existing user-facing
-- numbers had to be preserved during the transition. We are pre-launch
-- with zero live users — the previous values can be destroyed without
-- a backfill or compatibility story. So we inline the variant onto the
-- existing RPC name, keeping the Dart consumer
-- (`rpg_repository.dart::getPeakLoadPerBodyPart`) untouched.
--
-- ## Signature & contract unchanged
--
-- Same `(p_user_id uuid, p_days int, p_end_date timestamptz DEFAULT now())`
-- → `TABLE(body_part text, peak_load_kg numeric)`. Same `STABLE`,
-- `SECURITY INVOKER`, `SET search_path = public`. Same GRANT to
-- authenticated. Same half-open window `(end_date - days, end_date]` on
-- `COALESCE(w.started_at, w.finished_at)` — lock-step alignment with the
-- Volume column in `assembleStatsState` stays load-bearing (see 00064
-- §"Window timestamp source").
--
-- ## Algorithm
--
--   1. Per-set × per-attribution-entry tuple: unpack jsonb_each_text on
--      `e.xp_attribution`, filter to the window + non-zero weight.
--   2. Per-exercise max share: GROUP BY exercise_id, MAX(share). Only
--      consider shares > 0 (NULL/empty attribution exercises drop out
--      naturally — jsonb_each_text returns 0 rows over them).
--   3. Inner join (1) ↔ (2) on `(exercise_id, share = max_share)` —
--      only primary-share rows survive. Tie inclusion is free because the
--      equality check holds for every max-share BP.
--   4. Final aggregation: GROUP BY body_part, MAX(weight). One row per BP.
--
-- ## Performance
--
-- Same general order as 00064: per-set JSONB unpack + a window filter,
-- now with an additional self-aggregate over exercise_id. For a power
-- user with 7 sessions × 30 sets in 7 days that's ~210 sets × ~3 BPs/set
-- ≈ 630 tuples, ~10 distinct exercise_ids, ~6 BPs in the final group-by.
-- Well under 10 ms.
--
-- ## Idempotency
--
-- Pure read function. CREATE OR REPLACE swaps the body in a single
-- statement; no separate DROP needed, no dependent objects to recreate.
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
      e.id                  AS exercise_id,
      (kv).key              AS body_part,
      (kv).value::numeric   AS share
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
  ),
  max_share_per_exercise AS (
    SELECT exercise_id, MAX(share) AS max_share
    FROM attr_per_set
    WHERE share > 0
    GROUP BY exercise_id
  )
  SELECT
    a.body_part::text,
    MAX(a.weight)::numeric AS peak_load_kg
  FROM attr_per_set a
  JOIN max_share_per_exercise m USING (exercise_id)
  WHERE a.share = m.max_share
    AND a.share > 0
  GROUP BY a.body_part;
$$;

GRANT EXECUTE ON FUNCTION public.peak_load_per_body_part(uuid, int, timestamptz) TO authenticated;
