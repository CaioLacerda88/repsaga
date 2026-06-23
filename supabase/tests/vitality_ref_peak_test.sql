-- =============================================================================
-- vitality_ref_peak — recompute_vitality_for_user decaying reference-peak gate
-- (Phase Vitality-2, 00083)
--
-- PURPOSE
--   `recompute_vitality_for_user` had ZERO pgTAP coverage before this file. It
--   is the single SQL writer of body_part_progress.vitality_* for BOTH the save
--   path and the nightly cron. 00083 adds `vitality_ref_peak` — a DECAYING
--   reference peak (21-day half-life) that is the denominator for the
--   post-session conditioning charge fraction (ewma / ref_peak), distinct from
--   the monotone career-best `vitality_peak`.
--
--   This gate pins the ref_peak contract deterministically (no wall-clock, no
--   network): a regression in the GREATEST(new_ewma, prior_ref_peak * decay)
--   expression, the half-life constant, or the once-per-day guard turns a test
--   RED. A RED here is a real schema/function regression — the fix is the
--   migration, never the assertion.
--
-- WHAT IS COVERED
--   (a) a fresh step on a day-0 bp (with weekly volume) sets
--       ref_peak = new_ewma (the new ewma tops the GREATEST when prior_ref_peak
--       is 0);
--   (b) a DETRAINING step (zero weekly volume → ewma decays) decays ref_peak by
--       exactly the per-day half-life factor, BELOW the monotone vitality_peak;
--   (c) the once-per-day `last_vitality_date` guard blocks a 2nd same-day step —
--       ewma AND ref_peak both unchanged;
--   (d) vitality_peak is NEVER decreased by any of this (career-best intact).
--
-- APPROACH
--   pgTAP via `supabase test db` — same harness as rls_isolation_test.sql,
--   auto-run by the rls-tests CI job (bare `supabase test db`, no --file
--   filter). Transaction-wrapped, rolled back, no hosted instance.
--
--   The function reads xp_events for the 7-day weekly volume. By NOT seeding
--   xp_events we force weekly_volume = 0 → the pure-decay branch, which is the
--   deterministic surface for the detrain + guard assertions. For the "new ewma
--   tops ref_peak" assertion we seed one in-window xp_events row.
--
--   recompute_vitality_for_user is SECURITY DEFINER and uses now() for the UTC
--   day stamp; we seed/read as the bootstrap superuser (bypasses RLS).
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(10);

-- -----------------------------------------------------------------------------
-- Fixed test user. body_part_progress.user_id FKs auth.users(id).
-- -----------------------------------------------------------------------------
INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
VALUES
  ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'refpeak_user@test.local', '', now(), now(), now())
ON CONFLICT (id) DO NOTHING;

-- The per-day reference-peak decay multiplier — MUST match c_ref_peak_decay in
-- recompute_vitality_for_user (00083): exp(-ln(2)/21), a 21-day half-life.
-- Recomputed here independently so a drift in the function's constant fails.
-- (Stored via a temp table since pgTAP runs are plain SQL, no session vars.)
CREATE TEMP TABLE _k(decay numeric);
INSERT INTO _k VALUES (exp(-ln(2.0) / 21.0));

-- =============================================================================
-- (a) Fresh step with weekly volume → ref_peak = new_ewma (new ewma tops the
--     GREATEST when prior_ref_peak is 0). Day-0 bp: no row yet.
-- =============================================================================

-- Seed one in-window xp_events row attributing chest volume so weekly_volume>0.
-- event_type='cardio_session' sidesteps the set-FK CHECK (mirrors the
-- integration test's _seedXpEvent rationale); the worker aggregates attribution
-- regardless of event_type.
INSERT INTO public.xp_events (id, user_id, event_type, set_id, session_id,
                              occurred_at, total_xp, attribution, payload)
VALUES (
  gen_random_uuid(),
  '33333333-3333-3333-3333-333333333333',
  'cardio_session', NULL, NULL,
  now() - interval '1 day',
  500.0, '{"chest": 500.0}'::jsonb, '{"synthetic": true}'::jsonb
);

SELECT public.recompute_vitality_for_user(
  '33333333-3333-3333-3333-333333333333', ARRAY['chest']);

-- new_ewma = α_up * 500 (prior 0) ≈ 0.39346934 * 500 ≈ 196.73. ref_peak must
-- equal new_ewma exactly (GREATEST(new_ewma, 0 * decay) = new_ewma).
SELECT is(
  (SELECT vitality_ref_peak FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'chest'),
  (SELECT vitality_ewma FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'chest'),
  '(a) fresh step: ref_peak == new_ewma when prior ref_peak is 0');

SELECT cmp_ok(
  (SELECT vitality_ref_peak FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'chest'),
  '>', 0::numeric,
  '(a) fresh step: ref_peak is positive (ewma flowed in)');

-- last_vitality_date stamped today by the step.
SELECT is(
  (SELECT last_vitality_date FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'chest'),
  (now() AT TIME ZONE 'utc')::date,
  '(a) fresh step: last_vitality_date stamped to today');

-- =============================================================================
-- (b) Detraining step (zero weekly volume) decays ref_peak by exactly the
--     per-day half-life factor, and BELOW the monotone vitality_peak.
--
--     Seed a 'back' row with a high career peak + a known ref_peak, NO xp_events
--     for 'back' → weekly_volume 0 → ewma decays, ref_peak decays.
-- =============================================================================

INSERT INTO public.body_part_progress
  (user_id, body_part, total_xp, rank, vitality_ewma, vitality_peak,
   vitality_ref_peak, last_vitality_date)
VALUES
  ('33333333-3333-3333-3333-333333333333', 'back', 0, 1,
   100.0, 900.0, 800.0, NULL);  -- prior ewma 100, career peak 900, ref_peak 800

SELECT public.recompute_vitality_for_user(
  '33333333-3333-3333-3333-333333333333', ARRAY['back']);

-- Pure decay: new_ewma = (1-α_down_str)*100 ≈ exp(-7/42)*100 ≈ 84.65 (< 800),
-- so ref_peak = GREATEST(84.65, 800 * decay) = 800 * decay ≈ 773.99.
SELECT cmp_ok(
  (SELECT round(vitality_ref_peak, 4) FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'back'),
  '=',
  (SELECT round(800.0 * decay, 4) FROM _k),
  '(b) detrain step: ref_peak = prior_ref_peak * per-day half-life decay');

-- ref_peak must now be strictly below the monotone career peak (the whole point
-- — the denominator forgets so a comeback reads meaningfully).
SELECT cmp_ok(
  (SELECT vitality_ref_peak FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'back'),
  '<', 900::numeric,
  '(b) detrain step: decayed ref_peak is below the all-time vitality_peak');

-- And above the decayed ewma (it is a *reference ceiling*, not a copy of ewma).
SELECT cmp_ok(
  (SELECT vitality_ref_peak FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'back'),
  '>',
  (SELECT vitality_ewma FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'back'),
  '(b) detrain step: ref_peak stays above the decayed ewma (a real ceiling)');

-- =============================================================================
-- (d) vitality_peak is NEVER decreased — career best intact after the decay.
-- =============================================================================

SELECT is(
  (SELECT vitality_peak FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'back'),
  900.0::numeric(14,4),
  '(d) detrain step: vitality_peak (career best) NOT decreased by ref_peak decay');

-- =============================================================================
-- (c) Once-per-day guard: a 2nd same-day step is a no-op — ewma AND ref_peak
--     unchanged (last_vitality_date already today).
-- =============================================================================

-- Capture post-first-step state for 'back'.
CREATE TEMP TABLE _snap AS
  SELECT vitality_ewma, vitality_ref_peak, vitality_peak
  FROM public.body_part_progress
  WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'back';

-- Second same-day recompute — must short-circuit on the per-bp guard.
SELECT public.recompute_vitality_for_user(
  '33333333-3333-3333-3333-333333333333', ARRAY['back']);

SELECT is(
  (SELECT vitality_ewma FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'back'),
  (SELECT vitality_ewma FROM _snap),
  '(c) guard: 2nd same-day step does NOT advance vitality_ewma');

SELECT is(
  (SELECT vitality_ref_peak FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'back'),
  (SELECT vitality_ref_peak FROM _snap),
  '(c) guard: 2nd same-day step does NOT decay vitality_ref_peak again');

SELECT is(
  (SELECT vitality_peak FROM public.body_part_progress
     WHERE user_id = '33333333-3333-3333-3333-333333333333' AND body_part = 'back'),
  (SELECT vitality_peak FROM _snap),
  '(c) guard: 2nd same-day step leaves vitality_peak untouched');

-- -----------------------------------------------------------------------------
SELECT * FROM finish();
ROLLBACK;
