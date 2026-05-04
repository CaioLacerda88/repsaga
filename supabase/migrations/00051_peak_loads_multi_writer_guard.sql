-- ============================================================================
-- 00051 — exercise_peak_loads multi-writer guard (BEFORE-INSERT trigger)
-- ============================================================================
--
-- ## Why this migration exists
--
-- Migration 00050 patched the `per_set` CTE inside `record_session_xp_batch`
-- (the function that `save_workout` delegates to) so bodyweight workouts —
-- where every working set has weight = 0 (Plank, Push-Up, Pull-Up, Hanging
-- Leg Raise, etc.) — no longer violate
-- `exercise_peak_loads_peak_weight_check (peak_weight > 0)` and roll back the
-- entire `save_workout` transaction.
--
-- That fix was incomplete. There are THREE functions on the server that write
-- to `exercise_peak_loads`:
--
--   1. `public.record_session_xp_batch` — patched in 00050. ✓
--   2. `public._rpg_backfill_chunk`     — NOT patched. Active production bug,
--                                         fires every time `RpgRepository.runBackfill()`
--                                         processes a user's bodyweight history
--                                         (called post-frame from `SagaIntroGate`
--                                         on first home render).
--   3. `public.record_set_xp`           — NOT patched. Latent: kept alive as
--                                         a diagnostic / regression entry
--                                         point and granted to `authenticated`
--                                         (callable directly via PostgREST RPC).
--
-- A fourth writer added by some future migration would silently re-introduce
-- the same bug if we kept the per-writer-filter pattern that 00050 used.
--
-- ## What this migration does
--
-- Installs a BEFORE-INSERT-OR-UPDATE trigger on `exercise_peak_loads` that
-- silently drops any row where `peak_weight IS NULL OR peak_weight <= 0`
-- (and likewise for `peak_reps`, defensively). The trigger fires before the
-- CHECK constraint, so the row never reaches PG's constraint evaluator —
-- the INSERT/UPDATE statement returns successfully with zero rows affected,
-- and the surrounding transaction commits.
--
-- This is the architectural backstop that makes the constraint un-violable
-- regardless of how many writers exist now or in the future. Per-writer
-- explicit guards (the "Option A" pattern from 00050) become redundant —
-- they would still be valid as documentation of intent at the writer site,
-- but functionally the trigger is sufficient on its own.
--
-- ## Why this is correct semantics, not a workaround
--
-- `peak_weight` is the heaviest weight ever lifted for an exercise. For
-- bodyweight movements, the concept is meaningless — you don't "lift" a
-- bodyweight at all. The data model's correct expression of this is the
-- ABSENCE of an `exercise_peak_loads` row for those exercises, not a
-- sentinel-value row with `peak_weight = 0`.
--
-- Downstream code already handles the absence correctly:
--   - `rpg_strength_mult(weight, peak)` returns 1.0 when `peak IS NULL OR
--     peak <= 0` (00040 line 367-369). So bodyweight sets earn full
--     strength multiplier — exactly the behavior we want.
--   - `record_session_xp_batch`'s pre-fetch step (00050 lines 1094-1106)
--     LEFT JOINs against `exercise_peak_loads` and treats missing rows
--     as `v_peak = 0`. Same behavior.
--
-- So the trigger's silent-drop is the *correct* canonicalization, not a
-- corner-cut. Bodyweight exercises don't get peak_loads rows. Done.
--
-- ## Cost
--
-- Trigger overhead is negligible: at most ~25 firings per `save_workout`
-- (bounded by distinct exercise count per session). The trigger function
-- is a 4-line plpgsql block with two integer comparisons. Sub-microsecond
-- per row.
--
-- ## Backward compatibility
--
-- Pre-existing `exercise_peak_loads` rows are untouched. The trigger only
-- gates new INSERTs / UPDATEs. If somehow a row with peak_weight = 0 had
-- previously snuck in (it hasn't — the CHECK constraint has been rejecting
-- those), this migration leaves it alone.
--
-- ## Future cleanup (not in scope of this migration)
--
-- The two unpatched writer functions (_rpg_backfill_chunk, record_set_xp)
-- still emit INSERT statements with peak_weight = 0 for bodyweight sets;
-- the trigger silently drops them so it works correctly, but the writer
-- code remains misleading on read. A future cleanup migration could
-- CREATE OR REPLACE both functions with explicit `IF weight > 0 THEN ...
-- END IF` wraps for code-review explicitness. Not blocking — the trigger
-- subsumes the bug entirely.
--
-- ## Lessons captured
--
-- See `tasks/lessons.md` for the rule: when patching a CHECK violation,
-- audit `pg_proc` for every writer to the constrained table; if 3+ writers
-- exist, install a BEFORE-INSERT trigger as the architectural backstop.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.guard_exercise_peak_loads_weight()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Silently drop rows that would violate the table's CHECK constraints.
  -- Returning NULL from a BEFORE-trigger cancels the INSERT/UPDATE for
  -- this row — the surrounding statement still completes successfully
  -- with zero rows affected for this row.
  IF NEW.peak_weight IS NULL OR NEW.peak_weight <= 0 THEN
    RETURN NULL;
  END IF;
  IF NEW.peak_reps IS NULL OR NEW.peak_reps <= 0 THEN
    RETURN NULL;
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.guard_exercise_peak_loads_weight() IS
  'BEFORE-INSERT/UPDATE trigger on exercise_peak_loads. Drops rows where '
  'peak_weight or peak_reps would violate their CHECK constraints. See '
  'migration 00051 for the architectural rationale.';

-- Idempotent: drop existing trigger if present, then recreate.
DROP TRIGGER IF EXISTS exercise_peak_loads_drop_invalid ON public.exercise_peak_loads;

CREATE TRIGGER exercise_peak_loads_drop_invalid
BEFORE INSERT OR UPDATE ON public.exercise_peak_loads
FOR EACH ROW
EXECUTE FUNCTION public.guard_exercise_peak_loads_weight();
