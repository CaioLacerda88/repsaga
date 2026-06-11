-- =============================================================================
-- Make client table privileges EXPLICIT (stop relying on the implicit default)
-- Migration: 00076_grant_authenticated_table_privileges
--
-- WHY THIS EXISTS
-- ---------------
-- RepSaga's schema has, until now, granted ZERO table-level privileges to the
-- `authenticated` role in its migrations (the only prior data grant is
-- `GRANT SELECT ON public.entitlements` in 00025). Client reach to base tables
-- depended entirely on Supabase's IMPLICIT default grant
-- (`GRANT ... ON ALL TABLES IN SCHEMA public TO authenticated`) that the
-- local/hosted Postgres image applies at init time.
--
-- That implicit default is exactly the dependency that broke CI: around
-- 2026-06-11 the E2E workflow's `supabase/setup-cli@v1` (`version: latest`)
-- pulled a newer local image whose default no longer grants on `public` tables
-- to `authenticated`. The app's first post-login query
-- (`GET /rest/v1/profiles?id=eq.<uid>`) then returned
--   42501 — "permission denied for table profiles"
-- the splash waits on that profile load to route, so the app hung on the
-- REPSAGA splash forever, `nav-home` never rendered, and EVERY E2E test failed.
-- The failures × retries × timeouts blew the 45-min job cap, which masked the
-- real cause as a "timeout". (See the e2e sharding PR.)
--
-- This migration RESTORES that default EXPLICITLY and version-proofs it, so the
-- schema no longer depends on the image's default-grant behaviour — in CI or on
-- a future hosted-image upgrade. On the current hosted DB this is ADDITIVE and a
-- no-op (it already has the implicit defaults); GRANT never reduces access, so
-- applying it cannot break production.
--
-- WHY A BLANKET GRANT (not a hand-listed per-table grant)
-- -------------------------------------------------------
-- A full schema audit (this PR) confirmed EVERY table in `public` has RLS
-- ENABLED with owner-scoped policies (`auth.uid() = user_id`/`id`), so a coarse
-- table grant only opens the door — RLS still confines each user to their own
-- rows. `ON ALL TABLES IN SCHEMA public` is therefore both safe AND robust: it
-- mirrors exactly the Supabase default production already runs, and it only ever
-- touches tables that EXIST (a hand-maintained per-table list silently rots —
-- e.g. the legacy `user_xp` table was created early and later superseded by the
-- RPG system, so listing it aborts the whole migration). The two service-only
-- tables that have deny-all RLS (`account_deletion_events`, `migration_checkpoints`)
-- are re-tightened below for least privilege. No grants to `anon`: nothing in
-- this schema is meant for logged-out reads (public-read tables' policies are
-- already `TO authenticated`).
-- =============================================================================

-- Schema usage (part of the Supabase default; harmless if already present).
GRANT USAGE ON SCHEMA public TO authenticated;

-- Restore the table/view + sequence defaults for the authenticated role. RLS
-- (verified enabled + owner-scoped on every table) remains the row-level gate.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Future-proof: any table/sequence a LATER migration creates inherits the same
-- grant automatically (migrations run as this role), so a new table can never
-- reintroduce the boot-time 42501.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT                  ON SEQUENCES TO authenticated;

-- Least privilege: re-tighten the two service-role-only tables. Both already
-- have RLS with ZERO client policies (deny-all), so the blanket grant above is
-- already inert for them — this REVOKE just makes the intent explicit so a
-- future policy added to either table can't silently widen client reach.
REVOKE ALL ON public.account_deletion_events FROM authenticated;
REVOKE ALL ON public.migration_checkpoints   FROM authenticated;

-- --- Audit finding I-1: close an unguarded SECURITY DEFINER authz gap --------
-- `record_set_xp(uuid)` / `record_session_xp_batch(uuid)` are SECURITY DEFINER
-- and were granted EXECUTE to `authenticated` (00065), but neither asserts the
-- target set/workout belongs to the caller. The client NEVER calls them
-- directly (zero `.rpc()` call sites in lib/); the production path is
-- `save_workout` (SECURITY DEFINER, auth.uid()-guarded) which calls
-- `record_session_xp_batch` INTERNALLY — internal calls run with the definer's
-- rights, so revoking the client EXECUTE grant removes the standalone abuse
-- path with ZERO impact on the real save path and ZERO change to the XP math.
REVOKE EXECUTE ON FUNCTION public.record_set_xp(uuid)           FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.record_session_xp_batch(uuid) FROM authenticated;

-- =============================================================================
-- ROLLBACK (backout plan — ship as a new migration if this ever needs reverting)
-- -----------------------------------------------------------------------------
-- These grants are additive (a no-op on a DB that has the implicit defaults),
-- so "going south" is near-impossible. If a revert is ever required, apply the
-- inverse as a fresh migration:
--
--   ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLES    FROM authenticated;
--   ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE USAGE, SELECT                  ON SEQUENCES FROM authenticated;
--   REVOKE SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA public FROM authenticated;
--   REVOKE USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA public FROM authenticated;
--   -- restore the pre-existing function grants:
--   GRANT EXECUTE ON FUNCTION public.record_set_xp(uuid)           TO authenticated;
--   GRANT EXECUTE ON FUNCTION public.record_session_xp_batch(uuid) TO authenticated;
-- (Re-granting the service-only tables is intentionally omitted — they were
--  deny-all to clients before this migration and should stay that way.)
-- =============================================================================
