-- =============================================================================
-- 00062 — Phase 26e Task 2: backfill is_spontaneous = false on every entry
--
-- BucketRoutine gained `is_spontaneous: bool` (default false) in the Freezed
-- model. The JSONB column tolerates the missing key because fromJson defaults
-- to false on absent values, BUT once 00063's save_workout RPC starts
-- referencing v->>'is_spontaneous' inside SQL, NULL would surface as an
-- ambiguous third state. Backfill resolves this once: every existing entry
-- gets `is_spontaneous = false` written explicitly. From then on every writer
-- (client upsert, 00063 server-side append) sets the key.
--
-- Conservative default: existing entries represent the user's CURRENT plan;
-- treating them as planned (not spontaneous) preserves week-rollover behavior
-- (planned-only carries forward).
--
-- Idempotent: re-running this migration is a no-op against an already-backfilled
-- row (jsonb concatenation just overwrites with the same value).
-- =============================================================================

BEGIN;

UPDATE public.weekly_plans
SET routines = (
  SELECT COALESCE(
    jsonb_agg(
      CASE
        WHEN r ? 'is_spontaneous' THEN r
        ELSE r || jsonb_build_object('is_spontaneous', false)
      END
      ORDER BY (r->>'order')::int
    ),
    '[]'::jsonb
  )
  FROM jsonb_array_elements(routines) AS r
)
WHERE jsonb_typeof(routines) = 'array'
  AND EXISTS (
    SELECT 1
    FROM jsonb_array_elements(routines) AS r
    WHERE NOT (r ? 'is_spontaneous')
  );

COMMIT;
