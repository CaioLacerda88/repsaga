-- =============================================================================
-- Make client + service table privileges EXPLICIT (stop relying on the
-- implicit Supabase default grant)
-- Migration: 00076_grant_authenticated_table_privileges
--
-- WHY THIS EXISTS
-- ---------------
-- RepSaga's schema has, until now, granted ZERO table-level privileges in its
-- migrations (the only prior data grant is `GRANT SELECT ON public.entitlements`
-- in 00025). Every role's reach to base tables — the `authenticated` client AND
-- the `service_role` admin used by the E2E seed harness — depended entirely on
-- Supabase's IMPLICIT default grant
-- (`GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role`)
-- that the local/hosted Postgres image applies at init time.
--
-- That implicit default is exactly the dependency that broke CI: around
-- 2026-06-11 the E2E workflow's `supabase/setup-cli@v1` (`version: latest`)
-- pulled a newer local image whose default no longer grants on `public` tables
-- to those roles. Two failures cascaded from the SAME cause:
--   1. `service_role` lost its grant → `global-setup.ts` (the seed harness)
--      got `42501 permission denied for table profiles/workouts/...` and seeded
--      NOTHING (the errors are swallowed as warnings, so it looked silent).
--   2. `authenticated` lost its grant → the app's first post-login query
--      `GET /rest/v1/profiles` returned 42501; the splash waits on that profile
--      load to route, so the app hung on the REPSAGA splash, `nav-home` never
--      rendered, and EVERY E2E test failed. Failures × retries × timeouts then
--      blew the 45-min job cap, which masked the real cause as a "timeout".
-- (With only `authenticated` restored, the app booted but found no seeded
--  profile → routed to /onboarding → `nav-home` still missing. Both roles must
--  be restored.)
--
-- This migration RESTORES those defaults EXPLICITLY and version-proofs them, so
-- the schema no longer depends on the image's default-grant behaviour — in CI
-- or on a future hosted-image upgrade. On the current hosted DB this is ADDITIVE
-- and a no-op (it already has the implicit defaults); GRANT never reduces
-- access, so applying it cannot break production.
--
-- WHY BLANKET `ON ALL TABLES` (not a hand-listed per-table grant)
-- --------------------------------------------------------------
-- A full schema audit (this PR) confirmed EVERY table in `public` has RLS
-- ENABLED with owner-scoped policies (`auth.uid() = user_id`/`id`), so a coarse
-- table grant to `authenticated` only opens the door — RLS still confines each
-- user to their own rows. `ON ALL TABLES IN SCHEMA public` is both safe AND
-- robust: it mirrors exactly the Supabase default production already runs, and
-- only ever touches tables that EXIST (a hand-maintained list silently rots —
-- e.g. the legacy `user_xp` table was created early then superseded, so listing
-- it aborts the whole migration). `service_role` gets full access (it is the
-- admin/seed role and bypasses RLS, but still needs the table GRANT). No grants
-- to `anon`: nothing in this schema is read by logged-out users (public-read
-- tables' policies are already `TO authenticated`).
-- =============================================================================

GRANT USAGE ON SCHEMA public TO authenticated, service_role;

-- service_role — full admin access (the E2E seed harness + any server-side
-- maintenance). Bypasses RLS, but still requires table/sequence grants.
GRANT ALL ON ALL TABLES    IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- authenticated — client CRUD, RLS-gated (verified owner-scoped on every table).
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Future-proof: any table/sequence a LATER migration creates inherits the same
-- grants automatically (migrations run as this role), so a new table can never
-- reintroduce the boot-time / seed-time 42501.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL                            ON TABLES    TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL                            ON SEQUENCES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT                  ON SEQUENCES TO authenticated;

-- Least privilege: keep the two service-role-only tables off the CLIENT role
-- (service_role keeps them — they are service-written). Both already have RLS
-- with ZERO client policies (deny-all), so this is belt-and-suspenders that
-- also documents intent if a future policy is ever added to either table.
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
--   ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL                            ON TABLES    FROM service_role;
--   ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL                            ON SEQUENCES FROM service_role;
--   ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLES    FROM authenticated;
--   ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE USAGE, SELECT                  ON SEQUENCES FROM authenticated;
--   REVOKE ALL                            ON ALL TABLES    IN SCHEMA public FROM service_role;
--   REVOKE ALL                            ON ALL SEQUENCES IN SCHEMA public FROM service_role;
--   REVOKE SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA public FROM authenticated;
--   REVOKE USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA public FROM authenticated;
--   GRANT EXECUTE ON FUNCTION public.record_set_xp(uuid)           TO authenticated;
--   GRANT EXECUTE ON FUNCTION public.record_session_xp_batch(uuid) TO authenticated;
--   REVOKE USAGE ON SCHEMA public FROM authenticated, service_role;  -- only if fully unwinding
-- (Re-granting the service-only tables to authenticated is intentionally
--  omitted — they were deny-all to clients before this migration. The schema
--  USAGE revoke is listed for completeness but is normally left in place —
--  USAGE without table grants yields no data access.)
-- =============================================================================
