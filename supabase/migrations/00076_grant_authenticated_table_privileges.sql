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
-- (`GRANT ... ON ALL TABLES IN SCHEMA public TO anon, authenticated`) that the
-- local/hosted Postgres image applies at init time.
--
-- That implicit default is exactly the dependency that broke CI: around
-- 2026-06-11 the E2E workflow's `supabase/setup-cli@v1` (`version: latest`)
-- pulled a newer local image whose default no longer grants `SELECT` on
-- `public` tables to `authenticated`. The app's first post-login query
-- (`GET /rest/v1/profiles?id=eq.<uid>`) then returned
--   42501 — "permission denied for table profiles"
-- the splash screen waits on that profile load to route, so the app hung on
-- the REPSAGA splash forever, `nav-home` never rendered, and EVERY E2E test
-- failed. The failures × retries × timeouts blew the 45-min job cap, which
-- masked the real cause as a "timeout". (See PR adding e2e sharding.)
--
-- This migration makes the grants EXPLICIT and version-proof: the schema no
-- longer depends on the image's default-grant behaviour, in CI or on a future
-- hosted-image upgrade. On the current hosted DB these grants are ADDITIVE and
-- a no-op (it already has the implicit defaults) — GRANT never reduces access,
-- so applying this cannot break production.
--
-- SECURITY MODEL (why coarse grants are safe here)
-- ------------------------------------------------
-- A PostgREST request must pass BOTH layers: a table-level GRANT (can this role
-- touch the table at all) AND Row-Level Security (which rows). A full schema
-- audit (this PR) confirmed every table below has RLS ENABLED with
-- OWNER-SCOPED policies (`auth.uid() = user_id`/`id`), so a coarse grant only
-- opens the door — RLS still confines each user to their own rows. No table is
-- granted to `anon` (nothing in this schema is meant for logged-out reads), and
-- the two service-only tables (`account_deletion_events`, `migration_checkpoints`)
-- are deliberately NOT granted. Grants are scoped per-table to the commands the
-- client actually performs (least privilege), which is TIGHTER than the
-- blanket implicit default it replaces.
-- =============================================================================

-- Schema usage (part of the Supabase default; harmless if already present).
GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- --- Owner-scoped tables the client reads AND writes (RLS gates rows) --------
GRANT SELECT, INSERT, UPDATE          ON public.profiles             TO authenticated; -- no client DELETE (cascades from auth.users)
GRANT SELECT, INSERT, UPDATE, DELETE  ON public.exercises            TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE  ON public.workouts             TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE  ON public.workout_exercises    TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE  ON public.sets                 TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE  ON public.personal_records     TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE  ON public.workout_templates    TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE  ON public.weekly_plans         TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE  ON public.exercise_translations TO authenticated;
GRANT SELECT, INSERT, UPDATE          ON public.earned_titles        TO authenticated; -- no DELETE policy exists

-- --- Write-only telemetry (INSERT-own policy; no SELECT policy) --------------
GRANT INSERT                          ON public.analytics_events     TO authenticated;

-- --- Read-only to clients (writes happen via SECURITY DEFINER / service_role)-
GRANT SELECT ON public.subscriptions                     TO authenticated;
GRANT SELECT ON public.subscription_events               TO authenticated;
GRANT SELECT ON public.user_xp                           TO authenticated;
GRANT SELECT ON public.xp_events                         TO authenticated;
GRANT SELECT ON public.body_part_progress                TO authenticated;
GRANT SELECT ON public.exercise_peak_loads               TO authenticated;
GRANT SELECT ON public.exercise_peak_loads_by_rep_range  TO authenticated;
GRANT SELECT ON public.backfill_progress                 TO authenticated;
GRANT SELECT ON public.vitality_runs                     TO authenticated;
GRANT SELECT ON public.workout_template_translations     TO authenticated;
GRANT SELECT ON public.character_state                   TO authenticated; -- view (security_invoker=true → base-table RLS still applies)

-- Sequences backing any non-uuid identity/serial PK (USAGE+SELECT needed for
-- INSERTs to read nextval). Blanket over the schema; sequences carry no data.
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

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
--   REVOKE SELECT, INSERT, UPDATE          ON public.profiles             FROM authenticated;
--   REVOKE SELECT, INSERT, UPDATE, DELETE  ON public.exercises            FROM authenticated;
--   REVOKE SELECT, INSERT, UPDATE, DELETE  ON public.workouts             FROM authenticated;
--   REVOKE SELECT, INSERT, UPDATE, DELETE  ON public.workout_exercises    FROM authenticated;
--   REVOKE SELECT, INSERT, UPDATE, DELETE  ON public.sets                 FROM authenticated;
--   REVOKE SELECT, INSERT, UPDATE, DELETE  ON public.personal_records     FROM authenticated;
--   REVOKE SELECT, INSERT, UPDATE, DELETE  ON public.workout_templates    FROM authenticated;
--   REVOKE SELECT, INSERT, UPDATE, DELETE  ON public.weekly_plans         FROM authenticated;
--   REVOKE SELECT, INSERT, UPDATE, DELETE  ON public.exercise_translations FROM authenticated;
--   REVOKE SELECT, INSERT, UPDATE          ON public.earned_titles        FROM authenticated;
--   REVOKE INSERT                          ON public.analytics_events     FROM authenticated;
--   REVOKE SELECT ON public.subscriptions, public.subscription_events, public.user_xp,
--                    public.xp_events, public.body_part_progress, public.exercise_peak_loads,
--                    public.exercise_peak_loads_by_rep_range, public.backfill_progress,
--                    public.vitality_runs, public.workout_template_translations,
--                    public.character_state FROM authenticated;
--   REVOKE USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public FROM authenticated;
--   -- and restore the pre-existing function grants:
--   GRANT EXECUTE ON FUNCTION public.record_set_xp(uuid)           TO authenticated;
--   GRANT EXECUTE ON FUNCTION public.record_session_xp_batch(uuid) TO authenticated;
-- =============================================================================
