-- =============================================================================
-- RLS cross-user isolation test (Phase 38.9 T1.3)
--
-- PURPOSE
--   Prove — automatically, on every CI run — that Row Level Security actually
--   isolates one user's data from another's. RLS is ENABLEd on every
--   user-data table (`grep "ENABLE ROW LEVEL SECURITY" supabase/migrations`)
--   but until this gate existed, nothing verified the policies' BEHAVIOR: that
--   user A cannot SELECT / INSERT / UPDATE / DELETE user B's rows.
--
--   Prerequisite for Phase 40 (which adds the first cross-user RLS): this gate
--   pins the current isolation contract so a Phase-40 policy change that
--   accidentally widens read access to other users' rows turns a test RED.
--
-- WHAT GREEN MEANS
--   Current isolation is sound. A RED test here is NOT a flaky test — it is a
--   real RLS hole (one user reading/writing another's data). The fix is the
--   policy, never the assertion.
--
-- APPROACH
--   pgTAP via `supabase test db` against the LOCAL Supabase the CI pipeline
--   already boots (same instance pattern as the `integration-test` job). No
--   hosted instance, no secrets. `supabase test db` runs this file inside a
--   transaction that is ROLLED BACK afterwards, so the two seeded auth users
--   and all seeded rows never persist.
--
--   Auth is simulated with the standard PostgREST pattern: `set local role
--   authenticated` + `set local request.jwt.claims = '{"sub": "<uuid>",
--   "role": "authenticated"}'`. The installed `auth.uid()` reads
--   `current_setting('request.jwt.claim.sub')` first, falling back to
--   `request.jwt.claims ->> 'sub'` — this file sets the latter (the JSON
--   `claims` blob), which `auth.uid()` resolves correctly (verified against
--   the running `auth.uid()` definition).
--
--   SEEDING strategy: rows are seeded as the bootstrap superuser (which
--   BYPASSES RLS) so we can plant BOTH users' data regardless of the
--   per-table write policies. Several tables (`xp_events`,
--   `body_part_progress`, `exercise_peak_loads`, `exercise_peak_loads_by_rep_range`,
--   `backfill_progress`, `vitality_runs`, `subscriptions`, `subscription_events`)
--   are SELECT-only for `authenticated` by design — all
--   writes flow through SECURITY DEFINER RPCs or service-role Edge Functions
--   — so for those tables we assert
--   the READ isolation contract only (that is the entire authenticated-role
--   attack surface). Writable tables additionally assert INSERT/UPDATE/DELETE
--   isolation.
--
-- CLUSTER NOTE (supabase-cli-latest-grant-drift)
--   `supabase start` auto-applies every migration, including the explicit
--   `GRANT ... TO authenticated` statements (e.g. 00078 cardio_sessions). If
--   the local image ever drops implicit default grants again, the positive
--   (own-row) assertions below fail with permission-denied (42501) rather than
--   silently passing — this gate would surface that drift loudly.
-- =============================================================================

BEGIN;

-- pgTAP is installed transiently by `supabase test db`; create it defensively
-- so the file is also runnable via `psql -f` for local iteration.
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

-- -----------------------------------------------------------------------------
-- Plan: count every ok()/is()/throws-style assertion below.
-- -----------------------------------------------------------------------------
SELECT plan(58);

-- -----------------------------------------------------------------------------
-- Fixed test user UUIDs. Two distinct users:
--   A (the actor)  = 11111111-1111-1111-1111-111111111111
--   B (the victim) = 22222222-2222-2222-2222-222222222222
-- Seeded-row UUIDs use the prefix <a|b>0000000-...-000000000aNN where the NN
-- suffix is a per-table discriminator (01 workouts, 02 workout_exercises, 03
-- sets, 04 personal_records, 05 weekly_plans, 06 workout_templates, 07
-- cardio_sessions, 0e exercises, 0f xp_events; 08/09 = spoof-insert ids).
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- SEED (as superuser — bypasses RLS). Plant owned data for BOTH users.
-- -----------------------------------------------------------------------------

-- auth.users — minimal rows so FKs (profiles.id, *.user_id) resolve.
INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
VALUES
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rls_user_a@test.local', '', now(), now(), now()),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rls_user_b@test.local', '', now(), now(), now())
ON CONFLICT (id) DO NOTHING;

-- profiles (the handle_new_user trigger may already have inserted these via the
-- auth.users insert above; upsert defensively).
INSERT INTO public.profiles (id, username, display_name, fitness_level)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'rls_user_a', 'User A', 'beginner'),
  ('22222222-2222-2222-2222-222222222222', 'rls_user_b', 'User B', 'beginner')
ON CONFLICT (id) DO UPDATE SET username = EXCLUDED.username;

-- exercises (user-created / custom — is_default = false, owned via user_id).
-- Post-Phase-15f display text lives in exercise_translations; the base row
-- carries `slug` (NOT NULL), not `name`.
INSERT INTO public.exercises (id, slug, muscle_group, equipment_type, is_default, user_id)
VALUES
  ('a0000000-0000-0000-0000-000000000a0e', 'rls-a-custom-lift', 'chest', 'barbell', false,
   '11111111-1111-1111-1111-111111111111'),
  ('b0000000-0000-0000-0000-000000000a0e', 'rls-b-custom-lift', 'chest', 'barbell', false,
   '22222222-2222-2222-2222-222222222222');

-- workouts (owned directly via user_id).
INSERT INTO public.workouts (id, user_id, name, started_at, is_active)
VALUES
  ('a0000000-0000-0000-0000-000000000a01', '11111111-1111-1111-1111-111111111111',
   'A Workout', now(), false),
  ('b0000000-0000-0000-0000-000000000a01', '22222222-2222-2222-2222-222222222222',
   'B Workout', now(), false);

-- workout_exercises (owned via workout_id -> workouts ownership chain).
INSERT INTO public.workout_exercises (id, workout_id, exercise_id, "order")
VALUES
  ('a0000000-0000-0000-0000-000000000a02', 'a0000000-0000-0000-0000-000000000a01',
   'a0000000-0000-0000-0000-000000000a0e', 1),
  ('b0000000-0000-0000-0000-000000000a02', 'b0000000-0000-0000-0000-000000000a01',
   'b0000000-0000-0000-0000-000000000a0e', 1);

-- sets (owned via workout_exercises -> workouts two-hop chain).
INSERT INTO public.sets (id, workout_exercise_id, set_number, reps, weight, is_completed)
VALUES
  ('a0000000-0000-0000-0000-000000000a03', 'a0000000-0000-0000-0000-000000000a02',
   1, 5, 100.0, true),
  ('b0000000-0000-0000-0000-000000000a03', 'b0000000-0000-0000-0000-000000000a02',
   1, 5, 100.0, true);

-- personal_records (owned directly via user_id).
INSERT INTO public.personal_records (id, user_id, exercise_id, record_type, value, achieved_at)
VALUES
  ('a0000000-0000-0000-0000-000000000a04', '11111111-1111-1111-1111-111111111111',
   'a0000000-0000-0000-0000-000000000a0e', 'max_weight', 100.0, now()),
  ('b0000000-0000-0000-0000-000000000a04', '22222222-2222-2222-2222-222222222222',
   'b0000000-0000-0000-0000-000000000a0e', 'max_weight', 100.0, now());

-- weekly_plans (owned directly via user_id; FOR ALL owner policy).
INSERT INTO public.weekly_plans (id, user_id, week_start, routines)
VALUES
  ('a0000000-0000-0000-0000-000000000a05', '11111111-1111-1111-1111-111111111111',
   '2026-06-15', '[]'),
  ('b0000000-0000-0000-0000-000000000a05', '22222222-2222-2222-2222-222222222222',
   '2026-06-15', '[]');

-- workout_templates (a.k.a. "routines" — user-created, is_default = false).
INSERT INTO public.workout_templates (id, user_id, name, is_default, exercises)
VALUES
  ('a0000000-0000-0000-0000-000000000a06', '11111111-1111-1111-1111-111111111111',
   'A Routine', false, '[]'),
  ('b0000000-0000-0000-0000-000000000a06', '22222222-2222-2222-2222-222222222222',
   'B Routine', false, '[]');

-- cardio_sessions (owned via workout_id -> workouts ownership chain).
INSERT INTO public.cardio_sessions (id, workout_id, exercise_id, duration_seconds)
VALUES
  ('a0000000-0000-0000-0000-000000000a07', 'a0000000-0000-0000-0000-000000000a01',
   'a0000000-0000-0000-0000-000000000a0e', 600),
  ('b0000000-0000-0000-0000-000000000a07', 'b0000000-0000-0000-0000-000000000a01',
   'b0000000-0000-0000-0000-000000000a0e', 600);

-- xp_events (SELECT-only for authenticated; writes via SECURITY DEFINER RPCs).
INSERT INTO public.xp_events (id, user_id, event_type, set_id, session_id, payload, attribution, total_xp)
VALUES
  ('a0000000-0000-0000-0000-000000000a0f', '11111111-1111-1111-1111-111111111111',
   'set', 'a0000000-0000-0000-0000-000000000a03', 'a0000000-0000-0000-0000-000000000a01',
   '{}', '{}', 10.0),
  ('b0000000-0000-0000-0000-000000000a0f', '22222222-2222-2222-2222-222222222222',
   'set', 'b0000000-0000-0000-0000-000000000a03', 'b0000000-0000-0000-0000-000000000a01',
   '{}', '{}', 10.0);

-- body_part_progress (SELECT-only for authenticated; PK (user_id, body_part)).
INSERT INTO public.body_part_progress (user_id, body_part, total_xp, rank)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'chest', 10.0, 1),
  ('22222222-2222-2222-2222-222222222222', 'chest', 10.0, 1);

-- exercise_peak_loads (SELECT-only for authenticated; PK (user_id, exercise_id)).
INSERT INTO public.exercise_peak_loads (user_id, exercise_id, peak_weight, peak_reps, peak_date)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'a0000000-0000-0000-0000-000000000a0e',
   100.0, 5, now()),
  ('22222222-2222-2222-2222-222222222222', 'b0000000-0000-0000-0000-000000000a0e',
   100.0, 5, now());

-- exercise_peak_loads_by_rep_range (SELECT-only; PK (user_id, slug, rep_band)).
INSERT INTO public.exercise_peak_loads_by_rep_range (user_id, exercise_slug, rep_band, best_weight, best_reps)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'a-custom-lift', 'strength', 100.0, 5),
  ('22222222-2222-2222-2222-222222222222', 'b-custom-lift', 'strength', 100.0, 5);

-- earned_titles (SELECT + INSERT + UPDATE for authenticated; PK (user_id, title_id)).
INSERT INTO public.earned_titles (user_id, title_id, is_active)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'a_title', false),
  ('22222222-2222-2222-2222-222222222222', 'b_title', false);

-- backfill_progress (SELECT-only for authenticated; PK user_id; writes via
-- SECURITY DEFINER backfill procedure).
INSERT INTO public.backfill_progress (user_id, sets_processed)
VALUES
  ('11111111-1111-1111-1111-111111111111', 5),
  ('22222222-2222-2222-2222-222222222222', 5);

-- vitality_runs (SELECT-only for authenticated; PK (user_id, run_date);
-- writes via the nightly vitality Edge Function using service-role).
INSERT INTO public.vitality_runs (user_id, run_date)
VALUES
  ('11111111-1111-1111-1111-111111111111', '2026-06-15'),
  ('22222222-2222-2222-2222-222222222222', '2026-06-15');

-- subscriptions (SELECT-only for authenticated; UNIQUE(user_id); writes via
-- validate-purchase / rtdn-webhook Edge Functions using service-role).
INSERT INTO public.subscriptions (id, user_id, product_id, purchase_token, state)
VALUES
  ('a0000000-0000-0000-0000-000000000a10', '11111111-1111-1111-1111-111111111111',
   'premium_monthly', 'rls-a-token', 'active'),
  ('b0000000-0000-0000-0000-000000000a10', '22222222-2222-2222-2222-222222222222',
   'premium_monthly', 'rls-b-token', 'active');

-- subscription_events (SELECT-only for authenticated; append-only audit log;
-- writes via Edge Functions using service-role).
INSERT INTO public.subscription_events (id, user_id, purchase_token, notification_type, event_time)
VALUES
  ('a0000000-0000-0000-0000-000000000a11', '11111111-1111-1111-1111-111111111111',
   'rls-a-token', 'SUBSCRIPTION_PURCHASED', now()),
  ('b0000000-0000-0000-0000-000000000a11', '22222222-2222-2222-2222-222222222222',
   'rls-b-token', 'SUBSCRIPTION_PURCHASED', now());

-- =============================================================================
-- ASSERTIONS — each table: positive (own rows visible/writable) + negative
-- (other user's rows invisible / unwritable). The NEGATIVE assertions ARE the
-- security contract.
-- =============================================================================

-- Act as USER A for the SELECT-isolation block.
SET LOCAL role authenticated;
SET LOCAL request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';

-- ----- profiles -----
SELECT is(
  (SELECT count(*)::int FROM public.profiles WHERE id = '11111111-1111-1111-1111-111111111111'),
  1, 'profiles: A sees A''s own profile');
SELECT is(
  (SELECT count(*)::int FROM public.profiles WHERE id = '22222222-2222-2222-2222-222222222222'),
  0, 'profiles: A CANNOT see B''s profile (isolation)');

-- ----- exercises (custom rows) -----
SELECT is(
  (SELECT count(*)::int FROM public.exercises WHERE id = 'a0000000-0000-0000-0000-000000000a0e'),
  1, 'exercises: A sees A''s own custom exercise');
SELECT is(
  (SELECT count(*)::int FROM public.exercises WHERE id = 'b0000000-0000-0000-0000-000000000a0e'),
  0, 'exercises: A CANNOT see B''s custom exercise (isolation)');

-- ----- workouts -----
SELECT is(
  (SELECT count(*)::int FROM public.workouts WHERE id = 'a0000000-0000-0000-0000-000000000a01'),
  1, 'workouts: A sees A''s own workout');
SELECT is(
  (SELECT count(*)::int FROM public.workouts WHERE id = 'b0000000-0000-0000-0000-000000000a01'),
  0, 'workouts: A CANNOT see B''s workout (isolation)');

-- ----- workout_exercises (ownership chain via workouts) -----
SELECT is(
  (SELECT count(*)::int FROM public.workout_exercises WHERE id = 'a0000000-0000-0000-0000-000000000a02'),
  1, 'workout_exercises: A sees A''s own row');
SELECT is(
  (SELECT count(*)::int FROM public.workout_exercises WHERE id = 'b0000000-0000-0000-0000-000000000a02'),
  0, 'workout_exercises: A CANNOT see B''s row (chain isolation)');

-- ----- sets (two-hop ownership chain) -----
SELECT is(
  (SELECT count(*)::int FROM public.sets WHERE id = 'a0000000-0000-0000-0000-000000000a03'),
  1, 'sets: A sees A''s own set');
SELECT is(
  (SELECT count(*)::int FROM public.sets WHERE id = 'b0000000-0000-0000-0000-000000000a03'),
  0, 'sets: A CANNOT see B''s set (chain isolation)');

-- ----- personal_records -----
SELECT is(
  (SELECT count(*)::int FROM public.personal_records WHERE id = 'a0000000-0000-0000-0000-000000000a04'),
  1, 'personal_records: A sees A''s own PR');
SELECT is(
  (SELECT count(*)::int FROM public.personal_records WHERE id = 'b0000000-0000-0000-0000-000000000a04'),
  0, 'personal_records: A CANNOT see B''s PR (isolation)');

-- ----- weekly_plans -----
SELECT is(
  (SELECT count(*)::int FROM public.weekly_plans WHERE id = 'a0000000-0000-0000-0000-000000000a05'),
  1, 'weekly_plans: A sees A''s own plan');
SELECT is(
  (SELECT count(*)::int FROM public.weekly_plans WHERE id = 'b0000000-0000-0000-0000-000000000a05'),
  0, 'weekly_plans: A CANNOT see B''s plan (isolation)');

-- ----- workout_templates (routines) -----
SELECT is(
  (SELECT count(*)::int FROM public.workout_templates WHERE id = 'a0000000-0000-0000-0000-000000000a06'),
  1, 'workout_templates: A sees A''s own routine');
SELECT is(
  (SELECT count(*)::int FROM public.workout_templates WHERE id = 'b0000000-0000-0000-0000-000000000a06'),
  0, 'workout_templates: A CANNOT see B''s routine (isolation)');

-- ----- cardio_sessions (ownership chain via workouts) -----
SELECT is(
  (SELECT count(*)::int FROM public.cardio_sessions WHERE id = 'a0000000-0000-0000-0000-000000000a07'),
  1, 'cardio_sessions: A sees A''s own session');
SELECT is(
  (SELECT count(*)::int FROM public.cardio_sessions WHERE id = 'b0000000-0000-0000-0000-000000000a07'),
  0, 'cardio_sessions: A CANNOT see B''s session (chain isolation)');

-- ----- xp_events (SELECT-only) -----
SELECT is(
  (SELECT count(*)::int FROM public.xp_events WHERE id = 'a0000000-0000-0000-0000-000000000a0f'),
  1, 'xp_events: A sees A''s own event');
SELECT is(
  (SELECT count(*)::int FROM public.xp_events WHERE id = 'b0000000-0000-0000-0000-000000000a0f'),
  0, 'xp_events: A CANNOT see B''s event (isolation)');

-- ----- body_part_progress (SELECT-only) -----
SELECT is(
  (SELECT count(*)::int FROM public.body_part_progress
     WHERE user_id = '11111111-1111-1111-1111-111111111111' AND body_part = 'chest'),
  1, 'body_part_progress: A sees A''s own progress');
SELECT is(
  (SELECT count(*)::int FROM public.body_part_progress
     WHERE user_id = '22222222-2222-2222-2222-222222222222'),
  0, 'body_part_progress: A CANNOT see B''s progress (isolation)');

-- ----- exercise_peak_loads (SELECT-only) -----
SELECT is(
  (SELECT count(*)::int FROM public.exercise_peak_loads
     WHERE user_id = '11111111-1111-1111-1111-111111111111'),
  1, 'exercise_peak_loads: A sees A''s own peak');
SELECT is(
  (SELECT count(*)::int FROM public.exercise_peak_loads
     WHERE user_id = '22222222-2222-2222-2222-222222222222'),
  0, 'exercise_peak_loads: A CANNOT see B''s peak (isolation)');

-- ----- exercise_peak_loads_by_rep_range (SELECT-only) -----
SELECT is(
  (SELECT count(*)::int FROM public.exercise_peak_loads_by_rep_range
     WHERE user_id = '11111111-1111-1111-1111-111111111111'),
  1, 'exercise_peak_loads_by_rep_range: A sees A''s own band');
SELECT is(
  (SELECT count(*)::int FROM public.exercise_peak_loads_by_rep_range
     WHERE user_id = '22222222-2222-2222-2222-222222222222'),
  0, 'exercise_peak_loads_by_rep_range: A CANNOT see B''s band (isolation)');

-- ----- earned_titles (SELECT + INSERT + UPDATE) -----
SELECT is(
  (SELECT count(*)::int FROM public.earned_titles
     WHERE user_id = '11111111-1111-1111-1111-111111111111'),
  1, 'earned_titles: A sees A''s own title');
SELECT is(
  (SELECT count(*)::int FROM public.earned_titles
     WHERE user_id = '22222222-2222-2222-2222-222222222222'),
  0, 'earned_titles: A CANNOT see B''s title (isolation)');

-- ----- backfill_progress (SELECT-only) -----
SELECT is(
  (SELECT count(*)::int FROM public.backfill_progress
     WHERE user_id = '11111111-1111-1111-1111-111111111111'),
  1, 'backfill_progress: A sees A''s own progress');
SELECT is(
  (SELECT count(*)::int FROM public.backfill_progress
     WHERE user_id = '22222222-2222-2222-2222-222222222222'),
  0, 'backfill_progress: A CANNOT see B''s progress (isolation)');

-- ----- vitality_runs (SELECT-only) -----
SELECT is(
  (SELECT count(*)::int FROM public.vitality_runs
     WHERE user_id = '11111111-1111-1111-1111-111111111111'),
  1, 'vitality_runs: A sees A''s own run');
SELECT is(
  (SELECT count(*)::int FROM public.vitality_runs
     WHERE user_id = '22222222-2222-2222-2222-222222222222'),
  0, 'vitality_runs: A CANNOT see B''s run (isolation)');

-- ----- subscriptions (SELECT-only) -----
SELECT is(
  (SELECT count(*)::int FROM public.subscriptions
     WHERE user_id = '11111111-1111-1111-1111-111111111111'),
  1, 'subscriptions: A sees A''s own subscription');
SELECT is(
  (SELECT count(*)::int FROM public.subscriptions
     WHERE user_id = '22222222-2222-2222-2222-222222222222'),
  0, 'subscriptions: A CANNOT see B''s subscription (isolation)');

-- ----- subscription_events (SELECT-only) -----
SELECT is(
  (SELECT count(*)::int FROM public.subscription_events
     WHERE user_id = '11111111-1111-1111-1111-111111111111'),
  1, 'subscription_events: A sees A''s own event');
SELECT is(
  (SELECT count(*)::int FROM public.subscription_events
     WHERE user_id = '22222222-2222-2222-2222-222222222222'),
  0, 'subscription_events: A CANNOT see B''s event (isolation)');

-- =============================================================================
-- WRITE isolation — for the writable owner-scoped tables, prove A's writes to
-- B's rows affect ZERO rows (UPDATE/DELETE silently match nothing under RLS)
-- and A cannot INSERT a row owned by B (WITH CHECK rejects it).
-- =============================================================================

-- ----- profiles: A cannot UPDATE B's profile -----
WITH upd AS (
  UPDATE public.profiles SET display_name = 'HACKED'
  WHERE id = '22222222-2222-2222-2222-222222222222' RETURNING 1)
SELECT is((SELECT count(*)::int FROM upd), 0,
  'profiles: A''s UPDATE of B''s profile affects 0 rows (write isolation)');

-- ----- workouts: A cannot UPDATE / DELETE B's workout, cannot INSERT as B -----
WITH upd AS (
  UPDATE public.workouts SET name = 'HACKED'
  WHERE id = 'b0000000-0000-0000-0000-000000000a01' RETURNING 1)
SELECT is((SELECT count(*)::int FROM upd), 0,
  'workouts: A''s UPDATE of B''s workout affects 0 rows (write isolation)');

-- Make "0 rows affected" mean "row truly untouched": read B's row AS THE
-- BOOTSTRAP SUPERUSER (bypasses RLS) and assert its name is still the seeded
-- value, not 'HACKED'. The 0-affected count alone leaves "untouched" implicit;
-- this pins it explicitly for one representative writable table.
RESET role;  -- superuser read to inspect B's true row state
SELECT is(
  (SELECT name FROM public.workouts WHERE id = 'b0000000-0000-0000-0000-000000000a01'),
  'B Workout',
  'workouts: B''s row value is intact after A''s blocked UPDATE (truly untouched)');
SET LOCAL role authenticated;  -- re-establish actor A for the remaining write block
SET LOCAL request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';

WITH del AS (
  DELETE FROM public.workouts
  WHERE id = 'b0000000-0000-0000-0000-000000000a01' RETURNING 1)
SELECT is((SELECT count(*)::int FROM del), 0,
  'workouts: A''s DELETE of B''s workout affects 0 rows (write isolation)');

SELECT throws_ok(
  $$INSERT INTO public.workouts (id, user_id, name, started_at, is_active)
    VALUES ('a0000000-0000-0000-0000-000000000a09',
            '22222222-2222-2222-2222-222222222222', 'Spoofed', now(), false)$$,
  '42501',
  'new row violates row-level security policy for table "workouts"',
  'workouts: A INSERTing a row owned by B is rejected by WITH CHECK');

-- ----- sets: A cannot UPDATE / DELETE B's set (chain isolation) -----
WITH upd AS (
  UPDATE public.sets SET reps = 999
  WHERE id = 'b0000000-0000-0000-0000-000000000a03' RETURNING 1)
SELECT is((SELECT count(*)::int FROM upd), 0,
  'sets: A''s UPDATE of B''s set affects 0 rows (chain write isolation)');

WITH del AS (
  DELETE FROM public.sets
  WHERE id = 'b0000000-0000-0000-0000-000000000a03' RETURNING 1)
SELECT is((SELECT count(*)::int FROM del), 0,
  'sets: A''s DELETE of B''s set affects 0 rows (chain write isolation)');

-- ----- personal_records: A cannot UPDATE / DELETE B's PR -----
WITH upd AS (
  UPDATE public.personal_records SET value = 9999
  WHERE id = 'b0000000-0000-0000-0000-000000000a04' RETURNING 1)
SELECT is((SELECT count(*)::int FROM upd), 0,
  'personal_records: A''s UPDATE of B''s PR affects 0 rows (write isolation)');

WITH del AS (
  DELETE FROM public.personal_records
  WHERE id = 'b0000000-0000-0000-0000-000000000a04' RETURNING 1)
SELECT is((SELECT count(*)::int FROM del), 0,
  'personal_records: A''s DELETE of B''s PR affects 0 rows (write isolation)');

-- ----- exercises: A cannot UPDATE / DELETE B's custom exercise -----
WITH upd AS (
  UPDATE public.exercises SET slug = 'hacked'
  WHERE id = 'b0000000-0000-0000-0000-000000000a0e' RETURNING 1)
SELECT is((SELECT count(*)::int FROM upd), 0,
  'exercises: A''s UPDATE of B''s exercise affects 0 rows (write isolation)');

WITH del AS (
  DELETE FROM public.exercises
  WHERE id = 'b0000000-0000-0000-0000-000000000a0e' RETURNING 1)
SELECT is((SELECT count(*)::int FROM del), 0,
  'exercises: A''s DELETE of B''s exercise affects 0 rows (write isolation)');

-- ----- weekly_plans: A cannot UPDATE / DELETE B's plan -----
WITH upd AS (
  UPDATE public.weekly_plans SET routines = '[{"hacked": true}]'
  WHERE id = 'b0000000-0000-0000-0000-000000000a05' RETURNING 1)
SELECT is((SELECT count(*)::int FROM upd), 0,
  'weekly_plans: A''s UPDATE of B''s plan affects 0 rows (write isolation)');

WITH del AS (
  DELETE FROM public.weekly_plans
  WHERE id = 'b0000000-0000-0000-0000-000000000a05' RETURNING 1)
SELECT is((SELECT count(*)::int FROM del), 0,
  'weekly_plans: A''s DELETE of B''s plan affects 0 rows (write isolation)');

-- ----- workout_templates: A cannot UPDATE / DELETE B's routine -----
WITH upd AS (
  UPDATE public.workout_templates SET name = 'HACKED'
  WHERE id = 'b0000000-0000-0000-0000-000000000a06' RETURNING 1)
SELECT is((SELECT count(*)::int FROM upd), 0,
  'workout_templates: A''s UPDATE of B''s routine affects 0 rows (write isolation)');

WITH del AS (
  DELETE FROM public.workout_templates
  WHERE id = 'b0000000-0000-0000-0000-000000000a06' RETURNING 1)
SELECT is((SELECT count(*)::int FROM del), 0,
  'workout_templates: A''s DELETE of B''s routine affects 0 rows (write isolation)');

-- ----- cardio_sessions: A cannot UPDATE / DELETE B's session, cannot INSERT into B's workout -----
WITH upd AS (
  UPDATE public.cardio_sessions SET duration_seconds = 1
  WHERE id = 'b0000000-0000-0000-0000-000000000a07' RETURNING 1)
SELECT is((SELECT count(*)::int FROM upd), 0,
  'cardio_sessions: A''s UPDATE of B''s session affects 0 rows (chain write isolation)');

WITH del AS (
  DELETE FROM public.cardio_sessions
  WHERE id = 'b0000000-0000-0000-0000-000000000a07' RETURNING 1)
SELECT is((SELECT count(*)::int FROM del), 0,
  'cardio_sessions: A''s DELETE of B''s session affects 0 rows (chain write isolation)');

SELECT throws_ok(
  $$INSERT INTO public.cardio_sessions (id, workout_id, exercise_id, duration_seconds)
    VALUES ('a0000000-0000-0000-0000-000000000a08',
            'b0000000-0000-0000-0000-000000000a01',
            'b0000000-0000-0000-0000-000000000a0e', 60)$$,
  '42501',
  'new row violates row-level security policy for table "cardio_sessions"',
  'cardio_sessions: A INSERTing into B''s workout is rejected by WITH CHECK');

-- ----- earned_titles: A cannot UPDATE B's title, cannot INSERT a row owned by B -----
WITH upd AS (
  UPDATE public.earned_titles SET is_active = true
  WHERE user_id = '22222222-2222-2222-2222-222222222222' RETURNING 1)
SELECT is((SELECT count(*)::int FROM upd), 0,
  'earned_titles: A''s UPDATE of B''s title affects 0 rows (write isolation)');

SELECT throws_ok(
  $$INSERT INTO public.earned_titles (user_id, title_id, is_active)
    VALUES ('22222222-2222-2222-2222-222222222222', 'spoofed', false)$$,
  '42501',
  'new row violates row-level security policy for table "earned_titles"',
  'earned_titles: A INSERTing a row owned by B is rejected by WITH CHECK');

-- =============================================================================
-- STORAGE — avatars bucket own-prefix isolation (storage.objects RLS).
-- Avatars live at `{user_id}/avatar.jpg`; the policy gates on the first
-- folder segment matching auth.uid()::text. Seed one object per user as
-- superuser, then assert A reads only its own prefix.
-- =============================================================================

RESET role;  -- back to superuser to seed storage.objects (bypasses RLS)

INSERT INTO storage.objects (id, bucket_id, name, owner)
VALUES
  (gen_random_uuid(), 'avatars',
   '11111111-1111-1111-1111-111111111111/avatar.jpg',
   '11111111-1111-1111-1111-111111111111'),
  (gen_random_uuid(), 'avatars',
   '22222222-2222-2222-2222-222222222222/avatar.jpg',
   '22222222-2222-2222-2222-222222222222')
ON CONFLICT (id) DO NOTHING;

SET LOCAL role authenticated;
SET LOCAL request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';

SELECT is(
  (SELECT count(*)::int FROM storage.objects
     WHERE bucket_id = 'avatars'
       AND name = '11111111-1111-1111-1111-111111111111/avatar.jpg'),
  1, 'storage.objects: A reads A''s own avatar (own prefix)');
SELECT is(
  (SELECT count(*)::int FROM storage.objects
     WHERE bucket_id = 'avatars'
       AND name = '22222222-2222-2222-2222-222222222222/avatar.jpg'),
  0, 'storage.objects: A CANNOT read B''s avatar (cross-prefix isolation)');

-- -----------------------------------------------------------------------------
SELECT * FROM finish();
ROLLBACK;
