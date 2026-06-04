-- =============================================================================
-- Cluster: data-protection-compliance — account-delete cascade gap (Blocker 1)
-- Migration: 00074_exercises_user_id_cascade
--
-- Problem: `exercises.user_id` was created at 00001:63 as
--          `uuid REFERENCES auth.users,` with no explicit ON DELETE
--          behaviour, defaulting to NO ACTION. Account deletion via the
--          `delete-user` Edge Function calls `auth.admin.deleteUser`,
--          which relies on FK CASCADE everywhere on `auth.users` to wipe
--          all user-owned rows. With NO ACTION on `exercises.user_id`,
--          a user who had ever created a custom exercise would either
--          (a) block the auth delete entirely, or (b) leak that
--          `exercises` row past their account erasure — both violations
--          of the LGPD/GDPR erasure guarantee.
--
-- Context: user-created exercise creation was retired in Phase 32h
-- (PR #281). The retirement removed the UI path, but legacy rows from
-- before retirement still live in production data, so the FK still has
-- effect for those users.
--
-- Fix:     Drop the auto-named FK from 00001 and re-add it with
--          `ON DELETE CASCADE` and the canonical name
--          `exercises_user_id_fkey`.
--
-- Rationale for CASCADE (not SET NULL):
--   * A custom exercise without its owner is meaningless — its rows are
--     filtered by `user_id = auth.uid()` in every read path, so a
--     null-owner row would be unreachable yet still consume disk.
--   * The account-delete contract is total erasure: every user-owned
--     row must be removed, not just unowned.
--   * Default exercises have `user_id IS NULL` already (the column was
--     nullable in 00001 — only custom rows carry a UUID), so the CASCADE
--     only touches custom rows. Defaults are unaffected because they
--     have no FK target row to cascade from.
--
-- Idempotency (pattern mirrors 00047_personal_records_exercise_id_on_delete):
--   * Step 1 (drop) — DO block looks up the FK name dynamically; no-op when
--     no FK on `exercise_id` exists.
--   * Step 2 (add)  — guarded by an existence check on the canonical
--     constraint name so partial-replay scenarios (e.g., manual
--     post-failure recovery) do not raise "constraint already exists".
--
-- Backfill safety: `ON DELETE CASCADE` is a metadata-only operation in
-- Postgres — it does not rewrite existing rows. There is no risk of
-- orphan-row breakage when adding the cascade; the constraint validates
-- against the current data shape (`exercises.user_id` either NULL for
-- default rows or matching an existing `auth.users.id` for custom rows).
--
-- NOTE: Supabase CLI wraps each migration in an implicit transaction; we do
-- not add explicit BEGIN/COMMIT here. Cluster `postgres-alter-type-transaction`
-- does NOT apply — this is FK constraint mutation, not enum mutation.
-- =============================================================================

-- Step 1: drop the existing FK constraint (auto-named by Postgres in 00001).
DO $$
DECLARE
  _constraint_name text;
BEGIN
  SELECT tc.constraint_name INTO _constraint_name
  FROM information_schema.table_constraints tc
  JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
    AND tc.table_schema = kcu.table_schema
  WHERE tc.table_schema = 'public'
    AND tc.table_name = 'exercises'
    AND tc.constraint_type = 'FOREIGN KEY'
    AND kcu.column_name = 'user_id';

  IF _constraint_name IS NOT NULL THEN
    EXECUTE format(
      'ALTER TABLE public.exercises DROP CONSTRAINT %I',
      _constraint_name
    );
  END IF;
END;
$$;

-- Step 2: re-add the FK with ON DELETE CASCADE and a canonical name.
-- Wrapped in an existence guard so partial replay does not raise
-- "constraint already exists".
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.table_constraints
    WHERE table_schema = 'public'
      AND table_name = 'exercises'
      AND constraint_name = 'exercises_user_id_fkey'
      AND constraint_type = 'FOREIGN KEY'
  ) THEN
    ALTER TABLE public.exercises
      ADD CONSTRAINT exercises_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
  END IF;
END;
$$;

-- Reload PostgREST schema cache (mirrors 00008 / 00047).
NOTIFY pgrst, 'reload schema';
